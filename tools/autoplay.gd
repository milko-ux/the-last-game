extends SceneTree
# ============================================================
# HEADLESS AUTOPLAYER for the Phase R prototype.
#
#   godot --headless --path . -s tools/autoplay.gd -- bars=99 mode=validator
#   godot --headless --path . -s tools/autoplay.gd -- bars=99 mode=human seed=3
#   ... start_bar=17 maxdeaths=3      (jump in at bar 17, stop after 3 deaths)
#
# mode=validator  follows the plan the fairness validator found. It
#                 must never die: every death is a place where the
#                 runtime disagrees with rules.gd.
# mode=human      the "five deaths" bot (addendum 2): notices changes
#                 200 ms late, walks to the nearest safe tile (10 % of
#                 the time the second-nearest), never goes for notes.
# mode=naive      replays the first phone report: through the first
#                 gate's opening, then stands still.
#
# Runs in real time (the song clock is the system clock). Prints the
# scene's DEATH log lines and a summary.
# ============================================================

# Loaded at runtime: anything this -s script preloads is compiled before
# the autoloads exist, and these scripts reference BeatClock.
var Rules: GDScript = null
var HazardMath: GDScript = null

# The -s script is compiled before autoloads exist, so the clock is
# fetched from the tree at runtime (and created if script mode skipped it).
var clock: Node = null
var mode := "validator"
var max_bar := 20
var seed := 1
var max_deaths := 999
var start_bar := 0            # start_bar=N: begin at bar N as if from a checkpoint
var level := 1                # level=N: which level to play (levels/curriculum.json)
var _started_at_bar := false
var rng := RandomNumberGenerator.new()
# Human bot knobs: see the HUMAN BOT section at the bottom.
const HUMAN_DELAY := 0.2       # notices a state change this late
const HUMAN_COMFORT := 4.0     # wants to stay this far ahead of the death line
# Margins are the real hit box (Rules.PLAYER_HALF_W, 0.83 since 2026-09-19)
# plus a little; the offsets are the ones tuned on the old 0.4 box.
const HUMAN_MARGIN := 0.83 + 0.15     # plans against walls / orbs with this half-width
const HUMAN_MARGIN_GO := 0.83 + 0.02  # ...but a walk already under way is only abandoned below this
const HUMAN_FOOT := 0.15       # plate checks: the centre point plus this much slack
const HUMAN_WALL_LOOK := 16.0  # heads for a wall this far ahead and waits for the gap
const HUMAN_MARGIN_WALL := 0.83 + 0.05 # half-width used against a wall while crossing it
const HUMAN_ARMED_PENALTY := 3.0 # a tile that is armed when I land counts this much further away
var _human_target: Variant = null
var _near_specs: Array = []
var _hold_dbg_t := -1.0
var test: Node = null
var path: Array = []
var first_beat := 0
var naive_target: Variant = null
var naive_done := false
var last_deaths := 0
var death_bars := []
var t_wall0 := 0
var min_fps := 999


func _process(_delta: float) -> bool:
	if test == null:
		_setup()
		return false
	if test.state == test.State.WAIT:
		test.start_now()
		return false
	if start_bar > 0 and not _started_at_bar and test.state == test.State.RUN:
		# Jump in at bar N the way a checkpoint rewind would.
		_started_at_bar = true
		var lead: float = Rules.WINDOW_DEPTH * 0.45 / clock.track_speed
		var t0: float = maxf(clock.start_offset, clock.bar_start(start_bar) - lead)
		test.player.reset_to(0.0, clock.z_at(clock.bar_start(start_bar)) + 1.0)
		clock.seek(t0)
		return false
	if test.deaths != last_deaths:
		last_deaths = test.deaths
		death_bars.append(clock.current_bar())
	if test.state == test.State.RUN and clock.song_time() > clock.start_offset + 3.0:
		min_fps = mini(min_fps, int(Engine.get_frames_per_second()))
	var done: bool = clock.current_bar() > max_bar or test.state == test.State.WON or test.state == test.State.GAMEOVER \
		or test.deaths >= max_deaths or (Time.get_ticks_msec() - t_wall0) > 900000
	if done:
		print("AUTOPLAY mode=%s level=%d seed=%d bars<=%d deaths=%d at_bars=%s notes=%d state=%d goal=%s min_fps=%d" % [
			mode, level, seed, max_bar, test.deaths, str(death_bars), test.notes, test.state,
			"yes" if test.state == test.State.WON else "no", min_fps])
		return true
	return false


func _setup() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() == 2 and kv[0] == "mode":
			mode = kv[1]
		if kv.size() == 2 and kv[0] == "bars":
			max_bar = int(kv[1])
		if kv.size() == 2 and kv[0] == "seed":
			seed = int(kv[1])
		if kv.size() == 2 and kv[0] == "maxdeaths":
			max_deaths = int(kv[1])
		if kv.size() == 2 and kv[0] == "start_bar":
			start_bar = int(kv[1])
		if kv.size() == 2 and kv[0] == "level":
			level = int(kv[1])
	rng.seed = 424242 + seed * 7919
	Engine.max_fps = 30
	Rules = load("res://prototype/rules.gd")
	Rules.LEVEL = level
	Rules.LIVES_OVERRIDE = 0   # bots measure the level, never the lives
	HazardMath = load("res://prototype/hazard_math.gd")
	clock = root.get_node_or_null("BeatClock")
	if clock == null:
		clock = load("res://prototype/beat_clock.gd").new()
		clock.name = "BeatClock"
		root.add_child(clock)
	var scene: PackedScene = load("res://prototype/track_test.tscn")
	test = scene.instantiate()
	root.add_child(test)
	test.bot = self
	var fair: Dictionary = test.field.fairness
	if fair.get("cached", false) or fair["path"].is_empty():
		# The game reused a cached verdict; compute the path here.
		fair = load("res://prototype/fairness.gd").validate(test.field.plan, clock)
	path = fair["path"]
	first_beat = int(fair["first_beat"])
	t_wall0 = Time.get_ticks_msec()
	print("AUTOPLAY start mode=%s validator_ok=%s path_len=%d" % [mode, fair["ok"], path.size()])


# Called by the scene every frame instead of reading the joystick.
# Returns (screen-right, forward); world +x is screen-left.
func move_dir(scene: Node) -> Vector2:
	var target: Variant
	match mode:
		"naive":
			target = _naive_target(scene)
		"human":
			target = _human_target_for(scene)
		_:
			target = _validator_target(scene)
	if target == null:
		return Vector2.ZERO
	var p: Vector3 = scene.player.position
	var d := Vector2(float(target.x) - p.x, float(target.y) - p.z)
	var dist := d.length()
	# Full speed until practically there: a slow final approach leaves a
	# sideways move unfinished when the next forward move starts, and the
	# bot then cuts the corner into a wall.
	if dist < 0.06:
		return Vector2.ZERO
	var v := d / dist
	return Vector2(-v.x, v.y)


func _validator_target(scene: Node) -> Variant:
	var t: float = clock.hazard_time()
	var z_back: float = clock.z_at(clock.song_time())
	var i: int = clock.beat_at(t)
	if i < first_beat:
		# Run-up: ride the front of the window in the first tile's column,
		# so the first tile is reached well before the first downbeat.
		var front: float = z_back + Rules.WINDOW_DEPTH - 1.5
		if path.size() > 0 and path[0] != null:
			var p0: Vector2 = path[0]["pos"]
			return Vector2(p0.x, minf(p0.y, front))
		return Vector2(0.0, front)
	var idx := i - first_beat
	if idx >= path.size() or path[idx] == null:
		return Vector2(0.0, z_back + Rules.WINDOW_DEPTH * 0.6)
	var here: Dictionary = path[idx]
	if idx + 1 >= path.size() or path[idx + 1] == null:
		# Plan over (the outro): keep ahead of the back edge to the goal.
		return Vector2(here["pos"].x, z_back + Rules.WINDOW_DEPTH * 0.6)
	# Set off for the next tile at this beat's planned "leave" moment.
	if clock.beat_phase_at(t) >= float(here["leave"]):
		return path[idx + 1]["pos"]
	return here["pos"]


func _naive_target(scene: Node) -> Variant:
	if naive_done:
		return null
	if naive_target == null:
		for spec in scene.field.plan["hazards"]:
			if String(spec["kind"]) == "gate":
				naive_target = spec
				break
		if naive_target == null:
			naive_done = true
			return null
	var spec: Dictionary = naive_target
	var t: float = clock.hazard_time()
	var z_back: float = clock.z_at(clock.song_time())
	var goal := Vector2(HazardMath.gate_opening_x(spec, t), float(spec["z"]) + 1.5)
	if goal.y > z_back + Rules.WINDOW_DEPTH - 1.0:
		return Vector2(goal.x, z_back + Rules.WINDOW_DEPTH - 1.5)
	var p: Vector3 = scene.player.position
	if p.z > float(spec["z"]) + 1.0:
		naive_done = true
		print("AUTOPLAY naive: through the gate at t=%.2f, standing still at (%.2f, %.2f)" % [clock.song_time(), p.x, p.z])
		return null
	return goal


# ------------------------------------------------------------
# HUMAN BOT — a plausible new player, deliberately NOT an oracle
# (addendum 2, section 5).
#  - NOTICES a state change HUMAN_DELAY seconds late: its own plate
#    going dark, a gate's opening jumping. Continuous motion (a
#    sweeper's gap, an orbiter's orb) it tracks and extrapolates, the
#    way anyone watching a moving thing does;
#  - stands still while its own tile looks plain and the death line
#    is not pushing;
#  - when it has to move it steps to the NEAREST tile that is safe
#    when it lands (10 % of the time the second-nearest), by a straight
#    walk that is clear at every moment of the walk. Forward wins ties,
#    backward loses them. Never through a gate it saw jump, never
#    across a gate whose opening will jump before it is through;
#  - in front of a wall (sweeper / gate) it walks up to the row before
#    the wall, waits, edges toward the gap, and goes the moment a walk
#    through the gap fits — straight, or diagonally riding the gap;
#  - a walk under way is re-checked every frame and abandoned when it
#    stops fitting (a person swerves);
#  - never goes for notes, never jumps.
# ------------------------------------------------------------
func _human_target_for(scene: Node) -> Variant:
	var t: float = clock.hazard_time()
	var tp: float = t - HUMAN_DELAY
	var z_back: float = clock.z_at(clock.song_time())
	var line: float = Rules.min_z(z_back) + 1.5
	var comfort: float = line + HUMAN_COMFORT
	var z_front: float = z_back + Rules.WINDOW_DEPTH - 1.0
	var field = scene.field
	var p: Vector3 = scene.player.position
	var here := Vector2(p.x, p.z)
	var speed: float = Rules.player_speed()
	_near_specs = []
	for spec in field.plan["hazards"]:
		if absf(float(spec["z"]) - here.y) < 14.0:
			_near_specs.append(spec)

	# Run-up slab (no tiles yet): ride the window ahead of the line.
	if here.y < field.plan_first_z() - 0.5:
		_human_target = null
		return Vector2(0.0, comfort + 2.0)
	# Past the last bar: nothing left to dodge, run for the goal.
	var last_z1: float = clock.z_at(clock.bar_end(clock.bar_count()))
	if here.y >= last_z1:
		_human_target = null
		return Vector2(here.x, z_front)

	# 1. A walk under way: keep it while it still works. "Arrived" is a
	#    third of a unit: one frame at full speed moves 0.29, so a tighter
	#    test made the bot jitter around a tile for seconds without ever
	#    re-planning while the death line closed in (addendum-4 batch).
	#    A target that is not ahead is dropped the moment the line pushes.
	if _human_target != null:
		var tgt: Vector2 = _human_target
		var d := here.distance_to(tgt)
		var line_pushing: bool = here.y < line + HUMAN_COMFORT - 1.0
		if d < 0.35 or tgt.y < line or tgt.y > z_front or (line_pushing and tgt.y <= here.y + 0.5):
			_human_target = null
		elif not _human_walk_ok(field, here, tgt, t, HUMAN_MARGIN_GO) \
				or not _human_landing_ok(field, tgt, t + d / speed, HUMAN_MARGIN_GO):
			if OS.has_environment("HUMAN_DEBUG"):
				print("ABANDON t=%.3f here=(%.2f,%.2f) target=(%.1f,%.1f)" % [t, here.x, here.y, tgt.x, tgt.y])
			_human_target = null
		else:
			return tgt

	# 2. Do I have to move? Plates as they looked HUMAN_DELAY ago;
	#    orbs as they will be over the next moment.
	var own3: Vector3 = field.tile_centre_at(here.x, here.y)
	var own := Vector2(own3.x, own3.z)
	var own_plain: bool = field.floor_at(own.x, own.y) \
		and field.tile_state_at(own.x, own.y, tp) == field.TileState.SAFE \
		and not _human_boxed_within(own, t, 0.6, HUMAN_MARGIN) \
		and not _human_volley_warned(own, tp)
	var pushed: bool = own.y < comfort - 1.0
	var wall_z: float = _human_wall_ahead(here.y, t)
	var staged: bool = wall_z > 0.0 and own.y > wall_z - 2.0
	if own_plain and not pushed and wall_z < 0.0:
		return null

	# 3. Candidates: tiles within reach that are safe when I land, by a
	#    walk that is clear all the way.
	var cands := _human_candidates(field, here, own, t, line, z_front, speed, last_z1, false)
	var why := "move"
	if wall_z > 0.0:
		var beyond := cands.filter(func(c): return c["c"].y > wall_z + 0.5)
		if not beyond.is_empty():
			cands = beyond
			why = "through"
		elif not staged and own_plain:
			# Head for the row before the wall in as few stops as possible.
			cands = cands.filter(func(c): return c["c"].y > own.y + 0.5 and c["c"].y < wall_z - 0.3)
			for c in cands:
				c["d"] = -c["c"].y + (HUMAN_ARMED_PENALTY if c["armed"] else 0.0)
			why = "stage"
		elif own_plain:
			cands = _human_approach(cands, here, own, wall_z, t, tp)
			why = "approach"
	elif pushed and own_plain:
		cands = cands.filter(func(c): return c["c"].y > own.y + 0.5)
		why = "pushed"
	elif pushed:
		var fwd := cands.filter(func(c): return c["c"].y > own.y + 0.5)
		if not fwd.is_empty():
			cands = fwd
	if cands.is_empty():
		# Nothing fits. Hold while my tile stays quiet; otherwise bolt to
		# the nearest tile that is at least not lit when I land.
		if own_plain and not _human_lit_within(field, own, t, 0.35):
			if OS.get_environment("HUMAN_DEBUG") == "2" and t - _hold_dbg_t > 0.25:
				_hold_dbg_t = t
				print("HOLD %s t=%.3f here=(%.2f,%.2f) own=(%.1f,%.1f) wall=%.1f staged=%s pushed=%s :: %s" % [
					why, t, here.x, here.y, own.x, own.y, wall_z, staged, pushed,
					_human_reasons(field, here, own, t, line, z_front, speed)])
			return null
		cands = _human_candidates(field, here, own, t, line, z_front, speed, last_z1, true)
		why = "bolt"
		if cands.is_empty():
			return null
	cands.sort_custom(func(a, b): return a["d"] < b["d"])
	var pick: int = 1 if (cands.size() > 1 and rng.randf() < 0.10) else 0
	_human_target = cands[pick]["c"]
	if OS.has_environment("HUMAN_DEBUG"):
		print("PLAN %s t=%.3f bar=%d phase=%.2f here=(%.2f,%.2f) own_state=%d pushed=%s wall=%.1f -> (%.1f,%.1f) cands=%d" % [
			why, t, clock.bar_at(t), clock.beat_phase_at(t), here.x, here.y,
			field.tile_state_at(own.x, own.y, tp), pushed, wall_z, _human_target.x, _human_target.y, cands.size()])
	return _human_target


# Tiles within two steps of here, off my own tile, inside the window,
# safe on landing; with `loose` the walk itself is not checked.
func _human_candidates(field, here: Vector2, own: Vector2, t: float, line: float, z_front: float,
		speed: float, last_z1: float, loose: bool) -> Array:
	var out := []
	var pts := []
	var bar_lo: int = field.bar_at_z(maxf(here.y - 5.0, field.plan_first_z()))
	for bar in range(maxi(1, bar_lo), clock.bar_count() + 1):
		var bz0: float = clock.z_at(clock.bar_start(bar))
		if bz0 > here.y + 5.0:
			break
		var depth: float = clock.z_at(clock.bar_end(bar)) - bz0
		for col in Rules.COLS:
			for row in Rules.ROWS:
				pts.append(Vector2(Rules.col_x(col), bz0 + (row + 0.5) * depth / Rules.ROWS))
	if here.y + 4.5 > last_z1:
		# The outro slabs have no tiles: two plain steps ahead.
		for dz in [2.0, 4.0]:
			pts.append(Vector2(here.x, here.y + dz))
	for c in pts:
		if c.distance_to(own) < 0.3 or c.y > z_front:
			continue
		if c.y < line + 1.0 and c.y < own.y - 0.5:
			continue
		if absf(c.x - here.x) > 4.5 or absf(c.y - here.y) > 4.5:
			continue
		if not field.floor_at(c.x, c.y):
			continue
		var d := here.distance_to(c)
		if d < 0.3:
			continue
		if not _human_landing_ok(field, c, t + d / speed, HUMAN_MARGIN):
			continue
		if not _human_walk_ok(field, here, c, t, HUMAN_MARGIN, loose, own):
			continue
		# Forward wins ties, backward loses them; a tile that will be armed
		# when I land (dark magenta: fires next beat) is a last resort.
		var armed: bool = field.tile_state_at(c.x, c.y, t + d / speed) == field.TileState.ARMED \
			or _human_volley_warned(c, t + d / speed)
		out.append({"c": c, "armed": armed,
			"d": d + 0.05 * clampf(here.y - c.y, -1.0, 1.0) + (HUMAN_ARMED_PENALTY if armed else 0.0)})
	return out


# Waiting at a wall with no walk through it yet: edge sideways toward
# where the gap is (sweeper: where it is now; gate: where I last saw it).
func _human_approach(cands: Array, here: Vector2, own: Vector2, wall_z: float, t: float, tp: float) -> Array:
	var spec: Variant = _human_wall_spec(wall_z)
	if spec == null:
		return []
	var gx: float
	var need: float
	if String(spec["kind"]) == "gate":
		gx = HazardMath.gate_opening_x(spec, tp)
		need = 1.0
	else:
		gx = HazardMath.sweeper_gap_x(spec, t)
		need = 4.5
	if absf(gx - here.x) <= need:
		return []
	var out := []
	for c in cands:
		var cc: Vector2 = c["c"]
		if absf(cc.y - own.y) > 0.5:
			continue
		if absf(cc.x - gx) < absf(here.x - gx) - 0.5:
			out.append(c)
	return out


# z of the nearest live wall (sweeper / gate) ahead of z, or -1.
func _human_wall_ahead(z: float, t: float) -> float:
	var best := -1.0
	for spec in _near_specs:
		var kind := String(spec["kind"])
		if kind != "sweeper" and kind != "gate":
			continue
		if bool(spec.get("demo", false)) or not clock.hazards_armed_at(t + 1.0):
			continue
		var wz := float(spec["z"])
		if wz > z + 0.3 and wz <= z + HUMAN_WALL_LOOK and (best < 0.0 or wz < best):
			best = wz
	return best


func _human_wall_spec(wall_z: float) -> Variant:
	for spec in _near_specs:
		if absf(float(spec["z"]) - wall_z) < 0.01 and String(spec["kind"]) in ["sweeper", "gate"]:
			return spec
	return null


# The tile's flash is over when I land and does not restart right away,
# and nothing sweeps through it for a moment after.
func _human_landing_ok(field, c: Vector2, t_arr: float, margin: float) -> bool:
	for dt in [-0.05, 0.0, 0.15]:
		if _human_lit(field, c, t_arr + dt):
			return false
	if _human_boxed_within(c, t_arr - 0.05, 0.35, margin):
		return false
	return true


func _human_lit(field, c: Vector2, tt: float) -> bool:
	for off in [Vector2.ZERO, Vector2(HUMAN_FOOT, 0), Vector2(-HUMAN_FOOT, 0), Vector2(0, HUMAN_FOOT), Vector2(0, -HUMAN_FOOT)]:
		var q: Vector2 = c + off
		if field.tile_state_at(q.x, q.y, tt) == field.TileState.LETHAL:
			return true
	return false


func _human_lit_within(field, c: Vector2, t0: float, dur: float) -> bool:
	var tt := t0
	while tt <= t0 + dur:
		if _human_lit(field, c, tt):
			return true
		tt += 0.05
	return false


# Any wall / orb / slammer box over c at time tt (gates are planes, not
# boxes: see _human_walk_ok).
func _human_boxed_at(c: Vector2, tt: float, margin: float) -> bool:
	for spec in _near_specs:
		if String(spec["kind"]) == "gate" or absf(float(spec["z"]) - c.y) > 5.0:
			continue
		for b in HazardMath.boxes_at(spec, tt):
			var bb: AABB = b
			if bb.position.y > 1.6:
				continue
			if c.x + margin > bb.position.x and c.x - margin < bb.end.x \
					and c.y + margin > bb.position.z and c.y - margin < bb.end.z:
				return true
	return false


# A volley's warning line runs along this row: a person does not stand
# there (noticed HUMAN_DELAY late, like any state change).
func _human_volley_warned(c: Vector2, tt: float) -> bool:
	for spec in _near_specs:
		if String(spec["kind"]) != "volley" or bool(spec.get("demo", false)):
			continue
		if absf(float(spec["z"]) - c.y) < 1.0 and HazardMath.volley_warning(spec, tt):
			return true
	return false


func _human_boxed_within(c: Vector2, t0: float, dur: float, margin: float) -> bool:
	var tt := t0
	while tt <= t0 + dur:
		if _human_boxed_at(c, tt, margin):
			return true
		tt += 0.05
	return false


# Straight walk a->b at full speed starting at t_start: no plate lit
# under me at the moment I am on it, no wall / orb where I am at that
# moment, and any gate plane crossed inside the opening as I last saw
# it, before it can jump again.
# `bolt`: my own tile is about to fire and nothing fits, so ignore my own
# tile and the walls (a person runs); still never onto another lit plate.
func _human_walk_ok(field, a: Vector2, b: Vector2, t_start: float, margin: float, bolt: bool = false, own: Vector2 = Vector2.INF) -> bool:
	var dist := a.distance_to(b)
	var speed: float = Rules.player_speed()
	var steps := maxi(1, int(ceil(dist / 0.25)))
	for s in range(1, steps + 1):
		var u := float(s) / steps
		var q := a.lerp(b, u)
		var tt: float = t_start + dist * u / speed
		var on_own: bool = bolt and q.distance_to(own) < 1.0
		if not field.floor_at(q.x, q.y):
			return false   # nobody walks into a hole
		for dt in [-0.05, 0.05]:
			if not on_own and _human_lit(field, q, tt + dt):
				return false
			if not bolt and _human_boxed_at(q, tt + dt, minf(margin, HUMAN_MARGIN_WALL)):
				return false
	for spec in _near_specs:
		if String(spec["kind"]) != "gate" or bool(spec.get("demo", false)):
			continue
		var gz := float(spec["z"])
		if (a.y < gz) == (b.y < gz):
			continue
		var u := (gz - a.y) / (b.y - a.y)
		var t_cross: float = t_start + dist * u / speed
		if not clock.hazards_armed_at(t_cross):
			continue
		var seen_t: float = t_start - HUMAN_DELAY
		if clock.bar_at(t_cross) != clock.bar_at(seen_t):
			return false
		var x := lerpf(a.x, b.x, u)
		if absf(x - HazardMath.gate_opening_x(spec, seen_t)) + margin > Rules.gate_gap() * 0.5:
			return false
	return true


# Debug (HUMAN_DEBUG=2): why each forward tile within reach is not a
# candidate right now.
func _human_reasons(field, here: Vector2, own: Vector2, t: float, line: float, z_front: float, speed: float) -> String:
	var out := []
	var bar_lo: int = field.bar_at_z(maxf(here.y - 5.0, field.plan_first_z()))
	for bar in range(maxi(1, bar_lo), clock.bar_count() + 1):
		var bz0: float = clock.z_at(clock.bar_start(bar))
		if bz0 > here.y + 5.0:
			break
		var depth: float = clock.z_at(clock.bar_end(bar)) - bz0
		for col in Rules.COLS:
			for row in Rules.ROWS:
				var c := Vector2(Rules.col_x(col), bz0 + (row + 0.5) * depth / Rules.ROWS)
				if c.y <= own.y + 0.5 or absf(c.x - here.x) > 2.5 or absf(c.y - here.y) > 4.5:
					continue
				var d := here.distance_to(c)
				var r := "OK"
				if c.y < line + 1.0:
					r = "behind_line"
				elif c.y > z_front:
					r = "past_front"
				elif not field.floor_at(c.x, c.y):
					r = "pit"
				elif not _human_landing_ok(field, c, t + d / speed, HUMAN_MARGIN):
					var lit := false
					for dt in [-0.05, 0.0, 0.15]:
						if _human_lit(field, c, t + d / speed + dt):
							lit = true
					r = "land_lit" if lit else "land_boxed"
				elif not _human_walk_ok(field, here, c, t, HUMAN_MARGIN):
					r = "walk"
				out.append("(%.0f,%.1f)=%s" % [c.x, c.y, r])
	return " ".join(out)
