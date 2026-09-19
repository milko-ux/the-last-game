extends RefCounted
# ============================================================
# FAIRNESS VALIDATOR — mandatory (addendum).
#
# For every beat of the song there must be at least one safe tile
# inside the window that a player can actually get to from a safe
# tile of the previous beat. Runs on the generated layout before
# play starts and fails loudly if it does not hold.
#
# The movement model is the runtime's, sampled in time:
#  - at the start of beat i the player stands on tile A (safe on
#    beat i); at some moment (`leave`, a fraction of the beat) they
#    walk in a straight line at PLAYER_SPEED to tile B and wait
#    there until beat i+1 starts;
#  - every sample of that plan (standing, walking, waiting) is
#    checked against the pulse plates and the hazard boxes AT THAT
#    TIME, with the same rules the game uses to kill you;
#  - B may be up to two tile-steps away (Manhattan), the window's
#    back edge is respected with a margin.
#
# validate() also returns the plan it found (one tile + leave moment
# per beat), which tools/autoplay.gd follows exactly. If the
# autoplayer dies, the runtime and these rules disagree somewhere.
# ============================================================

const Rules := preload("res://prototype/rules.gd")
const HazardMath := preload("res://prototype/hazard_math.gd")

# Bump when the movement model or the rules change: it invalidates the
# per-device cache of validation verdicts (see Field.build).
const VERSION := 10  # 10: hit box 0.83 (the creature's footprint); orbiter margin covers the sample step

# Wider than the runtime's box so a plan never relies on centimetres.
# Two margins since the 0.83 box (2026-09-19): against plates the box is
# real + 0.1, so a tile next to a live plate (1.0 to its edge) is still a
# place to stand; against moving hazards it is real + 0.25, because the
# walk is sampled every 0.08 s and a sweeper moves ~0.7 units in that
# time — with the old 0.4 box a single 0.2 margin covered both.
const PLAYER_HALF := Rules.PLAYER_HALF_W + 0.1
const HAZARD_HALF := Rules.PLAYER_HALF_W + 0.25
# An orbiter's orb moves 9 units/s (18 at `speed` 2): 0.7-1.5 units between
# two waiting samples. The check against it is widened by half of that, so
# a plan can never sit in the orb's path between samples. (With the 0.4
# box this hid inside the old margin; the 0.83 box exposed it: the
# validator bot died 11 times on level 6, all orbiters.)
static func orbiter_sweep(spec: Dictionary) -> float:
	var per_bar := TAU * HazardMath.ORBIT_R * float(spec.get("speed", 1))
	return per_bar / (4.0 * BeatClock.beat_interval) * WAIT_DT * 0.5
const STEP := 0.25          # walk sample spacing (units)
const WAIT_DT := 0.08       # standing / waiting sample spacing (s)
const LEAVE_OPTIONS := [0.0, 0.5]

# Working state for one validation run (static funcs, passed around).
class Ctx:
	var plan: Dictionary
	var clock
	var bar_z0 := {}
	var bar_depth := {}
	var specs: Array = []


static func validate(plan: Dictionary, clock) -> Dictionary:
	var ctx := Ctx.new()
	ctx.plan = plan
	ctx.clock = clock
	for bar in range(1, clock.bar_count() + 1):
		ctx.bar_z0[bar] = clock.z_at(clock.bar_start(bar))
		ctx.bar_depth[bar] = clock.z_at(clock.bar_end(bar)) - ctx.bar_z0[bar]

	var problems := []
	var beats: PackedFloat64Array = clock.beats
	var speed: float = Rules.player_speed()
	var last_bar_end: float = clock.z_at(clock.bar_end(clock.bar_count()))
	var outro_bar: int = clock.bar_count() + 1

	var layers := []          # [{safe:{key:Vector2}, reach:{key:[parent_key, leave]}}]
	var prev_reach := {}
	var prev_safe := {}
	var first := true

	for i in range(clock.first_bar_beat, beats.size()):
		var t0: float = beats[i]
		var t1: float = beats[i + 1] if i + 1 < beats.size() else t0 + clock.beat_interval
		var tp: float = beats[i - 1] if i > 0 else t0 - clock.beat_interval
		var z_back0: float = clock.z_at(t0)
		var z_back1: float = clock.z_at(t1)
		var z_front: float = z_back0 + Rules.WINDOW_DEPTH
		var k: int = clock.beat_in_bar_at(t0)
		if z_back0 > last_bar_end + Rules.WINDOW_DEPTH:
			break

		ctx.specs = []
		for spec in plan["hazards"]:
			if absf(float(spec["z"]) - (z_back0 + z_front) * 0.5) > Rules.WINDOW_DEPTH:
				continue
			ctx.specs.append(spec)

		# Safe = where the player may BE at t0 (and, if they stay, through
		# the beat: the back edge must not pass the tile before t1).
		var safe := {}
		for bar in range(1, clock.bar_count() + 1):
			var z0: float = ctx.bar_z0[bar]
			var depth: float = ctx.bar_depth[bar]
			if z0 + depth < z_back0 or z0 > z_front:
				continue
			var entry: Dictionary = plan["bars"][bar]
			for col in Rules.COLS:
				for row in Rules.ROWS:
					if entry["pits"].has([col, row]):
						continue
					var cz := z0 + (row + 0.5) * depth / Rules.ROWS
					if cz < Rules.min_z(z_back1) + 0.6 or cz > z_front - 1.0:
						continue
					var cx := Rules.col_x(col)
					if _lethal_at(ctx, Vector2(cx, cz), t0):
						continue
					safe[Vector3i(bar, col, row)] = Vector2(cx, cz)
		if z_front - 1.0 > last_bar_end:
			for col in Rules.COLS:
				safe[Vector3i(outro_bar, col, 0)] = Vector2(Rules.col_x(col), maxf(last_bar_end + 1.0, Rules.min_z(z_back1) + 0.6))

		var reachable := {}
		if first:
			for key in safe:
				reachable[key] = [null, 0.0]
		else:
			for key in safe:
				var b: Vector2 = safe[key]
				var found := false
				# Own tile first (standing still is the cheapest plan).
				var cands := [key]
				cands.append_array(_neighbours(key, clock.bar_count()))
				for nkey in cands:
					if not prev_reach.has(nkey):
						continue
					var a: Vector2 = prev_safe[nkey]
					for leave in LEAVE_OPTIONS:
						var t_leave: float = tp + (t0 - tp) * float(leave)
						var dist := a.distance_to(b)
						if dist > speed * (t0 - t_leave) - 0.15:
							continue
						if _plan_ok(ctx, a, b, tp, t_leave, t0, speed):
							reachable[key] = [nkey, leave]
							found = true
							break
					if found:
						break

		if safe.is_empty():
			problems.append("beat %d (bar %d, beat %d): no safe tile in the window" % [i, clock.bar_at(t0), k + 1])
		elif reachable.is_empty():
			problems.append("beat %d (bar %d, beat %d): no safe tile reachable from the previous beat" % [i, clock.bar_at(t0), k + 1])
			if OS.has_environment("FAIR_DEBUG"):
				_explain(ctx, safe, prev_safe, prev_reach, tp, t0, speed, z_back0, z_back1)
			for key in safe:
				reachable[key] = [null, 0.0]

		layers.append({"safe": safe, "reach": reachable, "z_back": z_back0})
		prev_reach = reachable
		prev_safe = safe
		first = safe.is_empty()

	# Read the plan off the back-pointers, last beat to first. Each entry:
	# {"pos": Vector2, "leave": phase of THIS beat at which to set off for
	# the next entry}.
	var path := []
	path.resize(layers.size())
	var want: Variant = null
	var next_leave := 0.0
	for li in range(layers.size() - 1, -1, -1):
		var layer: Dictionary = layers[li]
		var reach_map: Dictionary = layer["reach"]
		if want == null or not reach_map.has(want):
			want = _pick_central(reach_map, layer["safe"], layer["z_back"])
			next_leave = 0.5
		if want == null:
			path[li] = null
			continue
		path[li] = {"pos": layer["safe"][want], "leave": next_leave}
		var link: Array = reach_map[want]
		want = link[0]
		next_leave = float(link[1])

	return {"ok": problems.is_empty(), "problems": problems, "path": path,
		"first_beat": clock.first_bar_beat}


# FAIR_DEBUG=1: why nothing was reachable at this beat.
static func _explain(ctx: Ctx, safe: Dictionary, prev_safe: Dictionary, prev_reach: Dictionary,
		tp: float, t0: float, speed: float, z_back0: float, z_back1: float) -> void:
	print("  FAIR_DEBUG beat t0=%.3f tp=%.3f z_back0=%.2f z_back1=%.2f min_z1=%.2f safe=%d prev_reach=%d specs=%s" % [
		t0, tp, z_back0, z_back1, Rules.min_z(z_back1), safe.size(), prev_reach.size(),
		str(ctx.specs.map(func(sp): return "%s@%.1f" % [sp["kind"], sp["z"]]))])
	var shown := 0
	for key in safe:
		var b: Vector2 = safe[key]
		var cands := [key]
		cands.append_array(_neighbours(key, ctx.clock.bar_count()))
		for nkey in cands:
			if not prev_reach.has(nkey):
				continue
			var a: Vector2 = prev_safe[nkey]
			var why := _plan_why(ctx, a, b, tp, tp, t0, speed)
			print("    to %s (%.1f,%.1f) from %s (%.1f,%.1f): %s" % [str(key), b.x, b.y, str(nkey), a.x, a.y, why])
			shown += 1
			if shown > 12:
				return


static func _plan_why(ctx: Ctx, a: Vector2, b: Vector2, t_stand: float, t_leave: float, t_end: float, speed: float) -> String:
	var t := t_stand
	while t < t_leave:
		if _lethal_at(ctx, a, t):
			return "standing lethal at t=%.3f" % t
		t += WAIT_DT
	var dist := a.distance_to(b)
	if dist > speed * (t_end - t_leave) - 0.15:
		return "too far (%.2f > %.2f)" % [dist, speed * (t_end - t_leave) - 0.15]
	var steps := maxi(1, int(ceil(dist / STEP)))
	for st in steps + 1:
		var u := float(st) / steps
		var tt: float = t_leave + dist * u / speed
		if _lethal_at(ctx, a.lerp(b, u), tt):
			return "walk lethal at u=%.2f t=%.3f" % [u, tt]
	t = t_leave + dist / speed
	while t < t_end:
		if _lethal_at(ctx, b, t):
			return "waiting lethal at t=%.3f" % t
		t += WAIT_DT
	return "OK?!"


# Stand on a from t_stand to t_leave, walk a->b at full speed, wait on b
# until t_end. Every sample must be non-lethal at its time.
static func _plan_ok(ctx: Ctx, a: Vector2, b: Vector2, t_stand: float, t_leave: float, t_end: float, speed: float) -> bool:
	var t := t_stand
	while t < t_leave:
		if _lethal_at(ctx, a, t):
			return false
		t += WAIT_DT
	var dist := a.distance_to(b)
	var steps := maxi(1, int(ceil(dist / STEP)))
	for s in steps + 1:
		var u := float(s) / steps
		if _lethal_at(ctx, a.lerp(b, u), t_leave + dist * u / speed):
			return false
	t = t_leave + dist / speed
	while t < t_end:
		if _lethal_at(ctx, b, t):
			return false
		t += WAIT_DT
	return true


# The rules, at a point and a time: a pulse plate under any corner of the
# (widened) player box — the game tests the centre, this is stricter on
# purpose so a plan never depends on which side of a tile corner the
# player lands — or any hazard box overlapping that box.
static func _lethal_at(ctx: Ctx, p: Vector2, t: float) -> bool:
	if ctx.clock.hazards_armed_at(t):
		for corner in [Vector2(-PLAYER_HALF, -PLAYER_HALF), Vector2(PLAYER_HALF, -PLAYER_HALF),
				Vector2(-PLAYER_HALF, PLAYER_HALF), Vector2(PLAYER_HALF, PLAYER_HALF)]:
			var c: Vector2 = p + corner
			var bar := _bar_at(ctx, c.y)
			if bar == 0:
				continue
			var entry: Dictionary = ctx.plan["bars"][bar]
			if entry["pattern"] == "none" and entry["plates"].is_empty():
				continue
			var depth: float = ctx.bar_depth[bar]
			var row := clampi(int(floor((c.y - ctx.bar_z0[bar]) / (depth / Rules.ROWS))), 0, Rules.ROWS - 1)
			var col := clampi(Rules.col_at(c.x), 0, Rules.COLS - 1)
			if Rules.plate_state(entry, col, row, t) == 2:
				return true
	for spec in ctx.specs:
		var is_orbiter := String(spec["kind"]) == "orbiter"
		var band := 6.0 if is_orbiter else 2.3
		if absf(float(spec["z"]) - p.y) > band:
			continue
		var half := HAZARD_HALF + (orbiter_sweep(spec) if is_orbiter else 0.0)
		for box in HazardMath.boxes_at(spec, t):
			var bb: AABB = box
			if bb.position.y > 1.6:
				continue
			if p.x + half > bb.position.x and p.x - half < bb.end.x \
				and p.y + half > bb.position.z and p.y - half < bb.end.z:
				return true
	return false


static func _bar_at(ctx: Ctx, z: float) -> int:
	var n: int = ctx.clock.bar_count()
	if n == 0 or z < ctx.bar_z0[1] or z >= ctx.bar_z0[n] + ctx.bar_depth[n]:
		return 0
	var lo := 1
	var hi := n
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if ctx.bar_z0[mid] <= z:
			lo = mid
		else:
			hi = mid - 1
	return lo


# Tiles within two steps (Manhattan), across bar boundaries.
static func _neighbours(key: Vector3i, bar_count: int) -> Array:
	var out := []
	for dc in range(-2, 3):
		for dr in range(-2, 3):
			if dc == 0 and dr == 0:
				continue
			if absi(dc) + absi(dr) > 2:
				continue
			var col := key.y + dc
			if col < 0 or col >= Rules.COLS:
				continue
			var bar := key.x
			var row := key.z + dr
			while row < 0 and bar > 1:
				bar -= 1
				row += Rules.ROWS
			while row >= Rules.ROWS and bar <= bar_count:
				bar += 1
				row -= Rules.ROWS
			if row < 0 or row >= Rules.ROWS:
				continue
			if bar > bar_count and row != 0:
				continue
			out.append(Vector3i(bar, col, row))
	return out


static func _pick_central(reach_map: Dictionary, safe: Dictionary, z_back: float) -> Variant:
	var best: Variant = null
	var best_d := 1e18
	for key in reach_map:
		var p: Vector2 = safe[key]
		var d := absf(p.x) + absf(p.y - (z_back + 5.0)) * 0.5
		if d < best_d:
			best_d = d
			best = key
	return best
