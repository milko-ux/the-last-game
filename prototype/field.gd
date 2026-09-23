extends Node3D
# ============================================================
# FIELD — builds and animates the wide floor from the beatmap.
#
# One slab per bar, 18 wide x 8 long, made of a 9 x 4 grid of tiles
# (2 x 2). Each tile is its own mesh so it can change colour on its
# own: cyan = safe, dark magenta = armed (lethal on the next beat),
# bright magenta = lethal now. Pits are simply missing tiles.
#
# The floor pattern is a pure function of song time, live whenever
# the bar is on screen — the floor IS the game.
#
# LAPS (Phase E brief 1, section 3). The field holds a ROLLING SET OF
# LAPS. Bars carry run-wide numbers (run bar = lap x 72 + bar), so
# plan["bars"][run_bar], a hazard's spec["bar"], a checkpoint's "bar"
# all count on across laps, exactly like BeatClock.bar_at() does. Each
# lap has its own knob dictionary: a hazard or a plate is always asked
# about with the knobs of the lap it belongs to (knobs_of / knobs_at),
# because two laps with different rates and gaps are alive at once.
#   add_lap()     merges a generated lap and QUEUES its nodes
#   build_step()  builds queued nodes for a few hundred microseconds
#   free_lap()    drops a lap that is behind the death line
# The dev level path is the same thing with one "lap": the whole song,
# generated, validated and built in one go by build() (as it always was).
# ============================================================

const Rules := preload("res://prototype/rules.gd")
const Mats := preload("res://prototype/flat_mats.gd")
const Placement := preload("res://prototype/placement.gd")
const Fairness := preload("res://prototype/fairness.gd")
const Slammer := preload("res://prototype/hazard_slammer.gd")
const Sweeper := preload("res://prototype/hazard_sweeper.gd")
const Orbiter := preload("res://prototype/hazard_orbiter.gd")
const Gate := preload("res://prototype/hazard_gate.gd")
const Volley := preload("res://prototype/hazard_volley.gd")
const Monoliths := preload("res://prototype/monoliths.gd")

enum TileState { SAFE, ARMED, LETHAL }

# Brief 2: tiles touch; the seams between them are drawn by the tile
# shader (flat_mats.gd TILE_SHADER), not left as gaps. The slab is 2.0
# units thick so it reads as a floating block, with its side faces and
# the pit walls in the face colour's shadow tones (brief 6).
# Brief 6 section 4 (Milko): the slab reads as a THICK block -- its front
# face and outer sides dark stone several tiles deep, fading into the fog
# (flat_mats.gd: SLAB_SIDE in the light's tones, then the height fog).
# Same boxes, same triangle count; only their depth changed (was 2.0).
const THICK := 6.0
const PLAIN_LEN := 8.0
const GOAL_WIDEN := 1.5     # brief 3: each goal post moves out this far over the last bar
# Hazards are posed only this far either side of the window's back edge
# (they are a pure function of time, so one that is not posed loses
# nothing; the rules never read the nodes).
const POSE_BEHIND := 14.0
const POSE_AHEAD := 52.0
# A lap's monoliths are placed in strips this long (one queue item each).
const MONOLITH_STRIP := 64.0
# The plain strip behind a later lap's first bar (see _lead_in).
const LEAD_IN_LEN := 12.0

# One lap of the rolling set.
class Lap:
	var lap := 0
	var knobs: Dictionary
	var first_bar := 1          # run bars
	var last_bar := 1
	var z0 := 0.0
	var z1 := 0.0
	var root: Node3D
	var monoliths: Node3D
	var hazards: Array = []
	var notes: Array = []
	var checkpoints: Array = []
	var fairness := {}
	var first_beat := 0         # run-wide index of the lap's first beat (the bots' path starts there)
	var queue: Array[Callable] = []
	var lead_in: MeshInstance3D
	var clock                   # the clock the lap was generated with (BeatClock, or its LapClock)
	var bar_offset := 0

var _goal_posts: Array = []
var _goal_top: MeshInstance3D
var _goal_u := -1.0

# Everything below is the union of the live laps, run-bar numbered.
var plan := {"bars": {}, "hazards": [], "notes": [], "checkpoints": [], "demo_bars": {}}
# The level path: the level's knobs. The endless run: the knobs of the lap
# the window's back edge is in (set_current()): "the lap being played".
var knobs := {}
var laps := {}                 # lap index -> Lap
var fairness := {"ok": true, "problems": []}
var hazards: Array = []
var notes: Array = []          # {x, z, node, taken}
var checkpoints: Array = []    # {bar, t, resume_t, x, z, node, lap}
var goal_z := INF              # the level path sets it; an endless run has no goal
var runup_z0 := -PLAIN_LEN
var outro_z1 := 0.0

var _first_bar := 1                    # run bar of _bar_z0[0]
var _bar_z0 := PackedFloat64Array()
var _bar_z1 := PackedFloat64Array()
var _tiles := {}                       # run bar -> Array[36] of MeshInstance3D or null (pit)
var _tile_state := {}                  # run bar -> PackedInt32Array


# ------------------------------------------------------------
# The level path: one level, everything at once
# ------------------------------------------------------------
func build(with_knobs: Dictionary) -> void:
	knobs = with_knobs
	var c := BeatClock
	if not c.loaded:
		push_error("Field: beatmap not loaded")
		return
	# Generate, validate, and re-roll any bar the validator rejects (and,
	# if a bar keeps failing, the bar before it too). Deterministic, so
	# the level is still identical on every run and device.
	# A verdict already computed on this device for this beatmap (and this
	# version of the rules) is reused: validation costs a second or two,
	# which would otherwise be paid on every launch. tools/autoplay.gd
	# recomputes the path it needs itself.
	var cached := _load_verdict()
	var rerolls: Dictionary = cached.get("rerolls", {})
	var passes := 0
	var level_plan := {}
	if cached.get("ok", false):
		level_plan = Placement.build(c, rerolls, knobs)
		fairness = {"ok": true, "problems": [], "path": [], "first_beat": c.first_bar_beat, "cached": true}
	else:
		fairness = {"ok": false, "problems": []}
		for attempt in Rules.reroll_passes(knobs):
			passes += 1
			level_plan = Placement.build(c, rerolls, knobs)
			fairness = Fairness.validate(level_plan, c, knobs)
			if fairness["ok"]:
				break
			for prob in fairness["problems"]:
				# The failing bar AND the one before it: the block is usually
				# the pair (what the previous bar funnels you into).
				var bar := int(String(prob).get_slice("bar ", 1).get_slice(",", 0))
				rerolls[bar] = int(rerolls.get(bar, 0)) + 1
				if bar > 1:
					rerolls[bar - 1] = int(rerolls.get(bar - 1, 0)) + 1
				# ...and the bar after: the window at the failing beat is mostly that one.
				rerolls[bar + 1] = int(rerolls.get(bar + 1, 0)) + 1
		if fairness["ok"]:
			_save_verdict(rerolls)
	fairness["rerolls"] = rerolls
	fairness["passes"] = passes
	FrameMeter.load_mark("validate", "cached" if fairness.get("cached", false) else "NOT cached, %d passes" % passes, true)
	if not fairness["ok"]:
		for p in fairness["problems"]:
			push_error("FAIRNESS: " + String(p))

	var lap := _install(0, knobs, c, level_plan, fairness, 0, true, false)
	lap.first_beat = c.first_bar_beat
	# The outro and the goal gate: three plain slabs after the last bar.
	var end_z := lap.z1
	for k in 3:
		lap.queue.append(_slab.bind(lap.root, end_z + k * PLAIN_LEN, PLAIN_LEN))
	outro_z1 = end_z + 3 * PLAIN_LEN
	goal_z = outro_z1 - 1.0
	lap.queue.append(_gate_mesh.bind(lap.root, goal_z))
	lap.monoliths.seed_level = Rules.level_of(knobs)
	lap.queue.append(lap.monoliths.build_range.bind(runup_z0 - 2.0 * PLAIN_LEN, outro_z1 + 3.0 * PLAIN_LEN))
	build_step(-1)
	FrameMeter.load_mark("nodes", "%d hazards" % hazards.size())


# The validation verdict (and the re-roll choices it settled on) is
# cached per beatmap and rules version on the device.
func _verdict_path() -> String:
	# Keyed by the rules version, the beatmap, the level AND a hash of the
	# scripts that shape the layout, so an edit to the generator can never
	# revive a stale "ok" (that would skip validation of a changed level).
	var src := ""
	for f in ["res://prototype/placement.gd", "res://prototype/rules.gd", "res://prototype/hazard_math.gd",
			"res://prototype/fairness.gd", "res://levels/curriculum.json"]:
		src += FileAccess.get_md5(f)
	return "user://fairness_v%d_L%d_%s_%s.json" % [Fairness.VERSION, Rules.level_of(knobs),
		FileAccess.get_md5(BeatClock.beatmap_path).substr(0, 12), src.md5_text().substr(0, 12)]


func _load_verdict() -> Dictionary:
	var f := FileAccess.open(_verdict_path(), FileAccess.READ)
	if f == null:
		return {}
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		return {}
	var rerolls := {}
	for k in data.get("rerolls", {}):
		rerolls[int(k)] = int(data["rerolls"][k])
	return {"ok": bool(data.get("ok", false)), "rerolls": rerolls}


func _save_verdict(rerolls: Dictionary) -> void:
	var f := FileAccess.open(_verdict_path(), FileAccess.WRITE)
	if f != null:
		var out := {}
		for k in rerolls:
			out[str(k)] = rerolls[k]
		f.store_string(JSON.stringify({"ok": true, "rerolls": out}))


# ------------------------------------------------------------
# The endless run: laps come and go
# ------------------------------------------------------------
# A generated lap (lap_gen.gd): its plan is merged under run-bar numbers
# and its nodes are queued. `with_runup`: the first lap of a run also
# gets the plain slabs of the run-up behind it.
func add_lap(lap_index: int, lap_knobs: Dictionary, lap_clock, lap_plan: Dictionary, lap_fairness: Dictionary, with_runup: bool) -> void:
	var lap := _install(lap_index, lap_knobs, lap_clock, lap_plan, lap_fairness, int(lap_clock.bar_offset), with_runup, true)
	lap.first_beat = lap_clock.global_first_beat()
	outro_z1 = maxf(outro_z1, lap.z1)
	fairness = lap_fairness
	if knobs.is_empty():
		knobs = lap_knobs


func has_lap(lap_index: int) -> bool:
	return laps.has(lap_index)


# True once every queued node of the lap exists.
func lap_built(lap_index: int) -> bool:
	return laps.has(lap_index) and laps[lap_index].queue.is_empty()


func pending_items() -> int:
	var n := 0
	for li in laps:
		n += laps[li].queue.size()
	return n


# Builds queued nodes, oldest lap first, until `budget_usec` microseconds
# are spent (-1 = everything). One item = one bar's tiles, one hazard, one
# strip of monoliths: a few hundred microseconds each. Returns true when
# nothing is left.
func build_step(budget_usec: int) -> bool:
	var until := Time.get_ticks_usec() + budget_usec
	var order := laps.keys()
	order.sort()
	for li in order:
		var lap: Lap = laps[li]
		while not lap.queue.is_empty():
			lap.queue.pop_front().call()
			if budget_usec >= 0 and Time.get_ticks_usec() >= until:
				return false
	return true


# The lap is behind the death line for good: its nodes and its data go.
func free_lap(lap_index: int) -> void:
	if not laps.has(lap_index):
		return
	var lap: Lap = laps[lap_index]
	for bar in range(lap.first_bar, lap.last_bar + 1):
		plan["bars"].erase(bar)
		plan["demo_bars"].erase(bar)
		_tiles.erase(bar)
		_tile_state.erase(bar)
	var gone := func(d) -> bool: return int(d["bar"]) >= lap.first_bar and int(d["bar"]) <= lap.last_bar
	plan["hazards"] = plan["hazards"].filter(func(d): return not gone.call(d))
	plan["notes"] = plan["notes"].filter(func(d): return not gone.call(d))
	plan["checkpoints"] = plan["checkpoints"].filter(func(d): return not gone.call(d))
	hazards = hazards.filter(func(h): return not lap.hazards.has(h))
	notes = notes.filter(func(n): return not lap.notes.has(n))
	checkpoints = checkpoints.filter(func(cp): return not lap.checkpoints.has(cp))
	if lap.first_bar == _first_bar:
		var n := lap.last_bar - lap.first_bar + 1
		_bar_z0 = _bar_z0.slice(n)
		_bar_z1 = _bar_z1.slice(n)
		_first_bar = lap.last_bar + 1
		runup_z0 = lap.z1
	# The next lap's lead-in slab takes over the strip behind its first bar.
	if laps.has(lap_index + 1) and laps[lap_index + 1].lead_in != null:
		laps[lap_index + 1].lead_in.visible = true
		runup_z0 = lap.z1 - LEAD_IN_LEN
	lap.root.queue_free()
	laps.erase(lap_index)


# The lap the window's back edge is in: `knobs` follows it.
func set_current(lap_index: int) -> void:
	if laps.has(lap_index):
		knobs = laps[lap_index].knobs


# The knobs a run bar / a hazard spec / a place on the field belongs to.
func knobs_for_bar(bar: int) -> Dictionary:
	for li in laps:
		var lap: Lap = laps[li]
		if bar >= lap.first_bar and bar <= lap.last_bar:
			return lap.knobs
	return knobs


func knobs_of(spec: Dictionary) -> Dictionary:
	return knobs_for_bar(int(spec["bar"]))


func knobs_at(z: float) -> Dictionary:
	var bar := bar_at_z(z)
	return knobs_for_bar(bar) if bar > 0 else knobs


func lap_of_bar(bar: int) -> int:
	for li in laps:
		if bar >= laps[li].first_bar and bar <= laps[li].last_bar:
			return li
	return -1


# One lap's plan as the validator wants it (bars numbered inside the lap),
# for the bots: they validate a lap themselves to get a path to follow.
func lap_plan_view(lap_index: int) -> Dictionary:
	var lap: Lap = laps[lap_index]
	var bars := {}
	for bar in range(lap.first_bar, lap.last_bar + 1):
		bars[bar - lap.bar_offset] = plan["bars"][bar]
	var specs: Array = plan["hazards"].filter(func(s): return int(s["bar"]) >= lap.first_bar and int(s["bar"]) <= lap.last_bar)
	return {"bars": bars, "hazards": specs}


func first_bar() -> int:
	return _first_bar


func last_bar() -> int:
	return _first_bar + _bar_z0.size() - 1


# Monoliths inside the fade-visible range of the window, per side, over
# every lap (tools/autoplay.gd measures the longest stretch with none).
func monoliths_in_view(z_back: float) -> Vector2i:
	var n := Vector2i.ZERO
	for li in laps:
		n += laps[li].monoliths.in_view(z_back)
	return n


func monolith_counts() -> Dictionary:
	var out := {"total": 0, "shown": 0, "detailed": 0}
	for li in laps:
		var c: Dictionary = laps[li].monoliths.counts()
		for k in out:
			out[k] += int(c[k])
	return out


# ------------------------------------------------------------
# Merging a lap and queueing its nodes (both paths)
# ------------------------------------------------------------
func _install(lap_index: int, lap_knobs: Dictionary, c, lap_plan: Dictionary, lap_fairness: Dictionary,
		bar_offset: int, with_runup: bool, monolith_strips: bool) -> Lap:
	var lap := Lap.new()
	lap.lap = lap_index
	lap.knobs = lap_knobs
	lap.fairness = lap_fairness
	lap.clock = c
	lap.bar_offset = bar_offset
	lap.first_bar = bar_offset + 1
	lap.last_bar = bar_offset + c.bar_count()
	lap.z0 = c.z_at(c.bar_start(1))
	lap.z1 = c.z_at(c.bar_end(c.bar_count()))
	lap.root = Node3D.new()
	lap.root.name = "Lap%d" % lap_index
	add_child(lap.root)
	lap.monoliths = Monoliths.new()
	lap.root.add_child(lap.monoliths)
	laps[lap_index] = lap
	if _bar_z0.is_empty():
		_first_bar = lap.first_bar

	# The plan, under run-bar numbers.
	for b in lap_plan["bars"]:
		plan["bars"][bar_offset + int(b)] = lap_plan["bars"][b]
	for b in lap_plan["demo_bars"]:
		plan["demo_bars"][bar_offset + int(b)] = lap_plan["demo_bars"][b]
	for spec in lap_plan["hazards"]:
		spec["bar"] = bar_offset + int(spec["bar"])
		plan["hazards"].append(spec)
	for n in lap_plan["notes"]:
		n["bar"] = bar_offset + int(n["bar"])
		plan["notes"].append(n)
	for cp in lap_plan["checkpoints"]:
		cp["bar"] = bar_offset + int(cp["bar"])
		plan["checkpoints"].append(cp)
	if lap_plan.has("curriculum"):
		plan["curriculum"] = lap_plan["curriculum"]

	if with_runup:
		# Run-up: plain slabs from behind the start to the first bar.
		var z := runup_z0
		while z < lap.z0 - 0.01:
			var length := minf(PLAIN_LEN, lap.z0 - z)
			lap.queue.append(_slab.bind(lap.root, z, length))
			z += length
	else:
		lap.queue.append(_lead_in.bind(lap))
	for bar in range(1, c.bar_count() + 1):
		var z0: float = c.z_at(c.bar_start(bar))
		var z1: float = c.z_at(c.bar_end(bar))
		_bar_z0.append(z0)
		_bar_z1.append(z1)
		lap.queue.append(_bar_tiles.bind(lap, bar_offset + bar, z0, z1))
	if monolith_strips:
		lap.monoliths.seed_level = int(lap_knobs.get("seed", Rules.level_of(lap_knobs)))
		var mz := (runup_z0 - 2.0 * PLAIN_LEN) if with_runup else lap.z0
		while mz < lap.z1:
			lap.queue.append(lap.monoliths.build_range.bind(mz, minf(mz + MONOLITH_STRIP, lap.z1)))
			mz += MONOLITH_STRIP
	for spec in lap_plan["hazards"]:
		lap.queue.append(_hazard.bind(lap, spec))
	lap.queue.append(_notes_and_checkpoints.bind(lap, c, lap_plan))
	return lap


func plan_first_z() -> float:
	return _bar_z0[0] if not _bar_z0.is_empty() else 0.0


func _slab(parent: Node3D, z_start: float, length: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(Rules.FIELD_WIDTH, THICK, length)
	mi.mesh = bm
	mi.material_override = Mats.tile(TileState.SAFE, bm.size * 0.5, Vector2.ONE)
	mi.position = Vector3(0.0, -THICK * 0.5, z_start + length * 0.5)
	parent.add_child(mi)
	return mi


# A later lap: a plain strip BEHIND its first bar, hidden while the lap
# before it is still there, shown when that one is freed. A rewind to the
# lap's bar-1 checkpoint puts the window's back edge a few units before
# the lap, and there must be floor to see there.
func _lead_in(lap: Lap) -> void:
	lap.lead_in = _slab(lap.root, lap.z0 - LEAD_IN_LEN, LEAD_IN_LEN)
	lap.lead_in.visible = not laps.has(lap.lap - 1)


func _hazard(lap: Lap, spec: Dictionary) -> void:
	var h: Node3D
	match String(spec["kind"]):
		"sweeper":
			h = Sweeper.new()
		"orbiter":
			h = Orbiter.new()
		"gate":
			h = Gate.new()
		"volley":
			h = Volley.new()
		_:
			h = Slammer.new()
	lap.root.add_child(h)
	h.setup(spec, lap.knobs)
	lap.hazards.append(h)
	hazards.append(h)


func _notes_and_checkpoints(lap: Lap, c, lap_plan: Dictionary) -> void:
	for n in lap_plan["notes"]:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.4
		sm.height = 0.8
		sm.radial_segments = 12
		sm.rings = 6
		mi.mesh = sm
		mi.material_override = Mats.note()
		mi.position = Vector3(float(n["x"]), 1.0, float(n["z"]))
		lap.root.add_child(mi)
		var entry := {"x": float(n["x"]), "z": float(n["z"]), "node": mi, "taken": false}
		lap.notes.append(entry)
		notes.append(entry)

	for cp in lap_plan["checkpoints"]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(Rules.FIELD_WIDTH, 0.06, 0.3)
		mi.mesh = bm
		mi.material_override = Mats.stone(WorldPalette.SAFE.darkened(0.45), bm.size * 0.5)
		mi.position = Vector3(0.0, 0.03, c.z_at(float(cp["t"])))
		lap.root.add_child(mi)
		var entry: Dictionary = cp.duplicate()
		entry["node"] = mi
		entry["lap"] = lap.lap
		lap.checkpoints.append(entry)
		checkpoints.append(entry)


func _bar_tiles(lap: Lap, bar: int, z0: float, z1: float) -> void:
	var entry: Dictionary = plan["bars"][bar]
	var depth := (z1 - z0) / Rules.ROWS
	var arr := []
	arr.resize(Rules.COLS * Rules.ROWS)
	var states := PackedInt32Array()
	states.resize(Rules.COLS * Rules.ROWS)
	for col in Rules.COLS:
		for row in Rules.ROWS:
			var idx := col * Rules.ROWS + row
			if entry["pits"].has([col, row]):
				arr[idx] = null
				continue
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(Rules.TILE, THICK, depth)
			mi.mesh = bm
			mi.material_override = Mats.tile(TileState.SAFE, bm.size * 0.5, _outer(col))
			mi.position = Vector3(Rules.col_x(col), -THICK * 0.5, z0 + (row + 0.5) * depth)
			lap.root.add_child(mi)
			arr[idx] = mi
	_tiles[bar] = arr
	_tile_state[bar] = states


# Which x sides of a tile in this column are the slab's outer rim.
static func _outer(col: int) -> Vector2:
	return Vector2(1.0 if col == 0 else 0.0, 1.0 if col == Rules.COLS - 1 else 0.0)


func _gate_mesh(parent: Node3D, z: float) -> void:
	for x in [-Rules.half_width() - 0.2, Rules.half_width() + 0.2]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.4, 3.2, 0.4)
		post.mesh = bm
		post.material_override = Mats.amber()
		post.position = Vector3(x, 1.6, z)
		parent.add_child(post)
		_goal_posts.append(post)
	var top := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(Rules.FIELD_WIDTH + 0.8, 0.4, 0.4)
	top.mesh = tb
	top.material_override = Mats.amber()
	top.position = Vector3(0.0, 3.4, z)
	parent.add_child(top)
	_goal_top = top


# ------------------------------------------------------------
# Queries
# ------------------------------------------------------------
# The run bar at z (0 = not on a bar: run-up, outro, or not built).
func bar_at_z(z: float) -> int:
	if _bar_z0.is_empty() or z < _bar_z0[0] or z >= _bar_z1[-1]:
		return 0
	return _first_bar - 1 + _bar_z0.bsearch(z, false)   # count of starts <= z


func _i(bar: int) -> int:
	return bar - _first_bar


# True where a player can stand: slabs, and any non-pit tile.
func floor_at(x: float, z: float) -> bool:
	if absf(x) > Rules.half_width():
		return false
	if z < runup_z0 or z >= outro_z1:
		return false
	var bar := bar_at_z(z)
	if bar == 0:
		return true   # run-up / outro slabs
	var entry: Dictionary = plan["bars"][bar]
	if entry["pits"].is_empty():
		return true
	var tile := tile_at(bar, x, z)
	return not entry["pits"].has([tile.x, tile.y])


func tile_at(bar: int, x: float, z: float) -> Vector2i:
	var col := clampi(Rules.col_at(x), 0, Rules.COLS - 1)
	var depth := (_bar_z1[_i(bar)] - _bar_z0[_i(bar)]) / Rules.ROWS
	var row := clampi(int(floor((z - _bar_z0[_i(bar)]) / depth)), 0, Rules.ROWS - 1)
	return Vector2i(col, row)


# The tile mesh under (x, z), for the death flash. null over a pit / slab.
func tile_node_at(x: float, z: float) -> Node:
	var bar := bar_at_z(z)
	if bar == 0 or not _tiles.has(bar):
		return null
	var tile := tile_at(bar, x, z)
	return _tiles[bar][tile.x * Rules.ROWS + tile.y]


# Brief 3: the goal gate's posts move outward as the player closes in
# over the last bar (u 0..1). Visual only; the goal line is field.goal_z.
func widen_goal(u: float) -> void:
	if _goal_posts.is_empty() or u == _goal_u:
		return
	_goal_u = u
	var e := u * u * (3.0 - 2.0 * u) * GOAL_WIDEN
	_goal_posts[0].position.x = -Rules.half_width() - 0.2 - e
	_goal_posts[1].position.x = Rules.half_width() + 0.2 + e
	_goal_top.scale.x = (Rules.FIELD_WIDTH + 0.8 + 2.0 * e) / (Rules.FIELD_WIDTH + 0.8)


func tile_centre_at(x: float, z: float) -> Vector3:
	var bar := bar_at_z(z)
	if bar == 0:
		return Vector3(x, 0.0, z)
	var tile := tile_at(bar, x, z)
	var depth := (_bar_z1[_i(bar)] - _bar_z0[_i(bar)]) / Rules.ROWS
	return Vector3(Rules.col_x(tile.x), 0.0, _bar_z0[_i(bar)] + (tile.y + 0.5) * depth)


# The plate state under (x, z) at hazard time t.
func tile_state_at(x: float, z: float, t: float) -> int:
	var bar := bar_at_z(z)
	if bar == 0:
		return TileState.SAFE
	var tile := tile_at(bar, x, z)
	return _state_for(bar, tile.x, tile.y, t)


# The one plate rule lives in Rules.plate_state (0/1/2 = SAFE/ARMED/LETHAL):
# armed for a whole period, lethal for the first LETHAL_BEAT_FRACTION of a
# beat after the period starts; only the warning colour before the first
# downbeat and on demo bars. Asked with the knobs of the bar's own lap.
func _state_for(bar: int, col: int, row: int, t: float) -> int:
	return Rules.plate_state(plan["bars"][bar], col, row, t, knobs_for_bar(bar))


# Repaint the tiles of the bars near the window. Only changed tiles touch
# their material, so this is cheap.
func update_tiles(t: float, z_back: float) -> void:
	for li in laps:
		laps[li].monoliths.set_window(z_back)
	if _bar_z0.is_empty():
		return
	var lo := bar_at_z(maxf(z_back - 2.0, _bar_z0[0]))
	var hi := bar_at_z(minf(z_back + Rules.window_depth(knobs) + 8.0, _bar_z1[-1] - 0.01))
	if lo == 0 and hi == 0:
		return
	if lo == 0:
		lo = _first_bar
	if hi == 0:
		hi = last_bar()
	var repainted := 0
	for bar in range(lo, hi + 1):
		if not _tiles.has(bar):
			continue          # queued, not built yet
		var arr: Array = _tiles[bar]
		var states: PackedInt32Array = _tile_state[bar]
		var bar_knobs := knobs_for_bar(bar)
		var entry: Dictionary = plan["bars"][bar]
		for col in Rules.COLS:
			for row in Rules.ROWS:
				var idx := col * Rules.ROWS + row
				var mi = arr[idx]
				if mi == null:
					continue
				var s := Rules.plate_state(entry, col, row, t, bar_knobs)
				if s != states[idx]:
					states[idx] = s
					repainted += 1
					mi.material_override = Mats.tile(s, mi.mesh.size * 0.5, _outer(col))
		_tile_state[bar] = states
	if repainted > 0 and FrameMeter.active:
		FrameMeter.note("tile repaint", repainted)


# Pose the hazards near the window (see POSE_BEHIND / POSE_AHEAD).
func update_hazards(t: float, z_back: float) -> void:
	var lo := z_back - POSE_BEHIND
	var hi := z_back + POSE_AHEAD
	for h in hazards:
		var z: float = h.position.z
		if z >= lo and z <= hi:
			h.update_state(t)


# Nearest tile near (x, z) that is lethal now or armed, for the eye.
func nearest_danger_tile(x: float, z: float, t: float) -> Variant:
	var bar := bar_at_z(z)
	if bar == 0:
		return null
	var best: Variant = null
	var best_d := 1e9
	for b in range(maxi(_first_bar, bar - 1), mini(last_bar(), bar + 1) + 1):
		var entry: Dictionary = plan["bars"][b]
		if entry["pattern"] == "none" and entry["plates"].is_empty():
			continue
		var z0 := _bar_z0[_i(b)]
		var depth := (_bar_z1[_i(b)] - z0) / Rules.ROWS
		for col in Rules.COLS:
			for row in Rules.ROWS:
				if _state_for(b, col, row, t) == TileState.SAFE:
					continue
				var p := Vector3(Rules.col_x(col), 0.0, z0 + (row + 0.5) * depth)
				var d := Vector2(p.x - x, p.z - z).length()
				if d < best_d and d < 6.0:
					best_d = d
					best = p
	return best


func mark_checkpoint(cp: Dictionary) -> void:
	cp["node"].material_override = Mats.flat(WorldPalette.SAFE.darkened(0.55))


func reset_run() -> void:
	for cp in checkpoints:
		cp["node"].material_override = Mats.stone(WorldPalette.SAFE.darkened(0.45), cp["node"].mesh.size * 0.5)
	for n in notes:
		n["taken"] = false
		n["node"].visible = true
