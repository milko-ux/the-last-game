extends Node3D
# ============================================================
# FIELD — builds and animates the wide floor from the beatmap.
#
# One slab per bar, 14 wide x 8 long, made of a 7 x 4 grid of
# tiles (2 x 2). Each tile is its own mesh so it can change colour
# on its own: cyan = safe, dark magenta = armed (lethal on the next
# beat), bright magenta = lethal now. Pits are simply missing tiles.
#
# The floor pattern is a pure function of song time, live whenever
# the bar is on screen — the floor IS the game.
# ============================================================

const Rules := preload("res://prototype/rules.gd")
const Mats := preload("res://prototype/flat_mats.gd")
const Placement := preload("res://prototype/placement.gd")
const Fairness := preload("res://prototype/fairness.gd")
const Slammer := preload("res://prototype/hazard_slammer.gd")
const Sweeper := preload("res://prototype/hazard_sweeper.gd")
const Orbiter := preload("res://prototype/hazard_orbiter.gd")
const Gate := preload("res://prototype/hazard_gate.gd")

enum TileState { SAFE, ARMED, LETHAL }

const SEAM := 0.1        # between slabs / bars
const TILE_SEAM := 0.3   # between tiles: wide enough that the grid reads from the camera
const THICK := 0.5
const PLAIN_LEN := 8.0

var plan := {}
var fairness := {"ok": true, "problems": []}
var hazards: Array = []
var notes: Array = []          # {x, z, node, taken}
var checkpoints: Array = []    # {bar, t, resume_t, x, z, node}
var goal_z := 0.0
var runup_z0 := -PLAIN_LEN
var outro_z1 := 0.0

var _bar_z0 := PackedFloat64Array()   # index bar-1
var _bar_z1 := PackedFloat64Array()
var _tiles := {}                       # bar -> Array[28] of MeshInstance3D or null (pit)
var _tile_state := {}                  # bar -> PackedInt32Array
var _cache_t := -1.0


func build() -> void:
	var c := BeatClock
	if not c.loaded:
		push_error("Field: beatmap not loaded")
		return
	plan = Placement.build(c)
	fairness = Fairness.validate(plan, c)
	if not fairness["ok"]:
		for p in fairness["problems"]:
			push_error("FAIRNESS: " + String(p))

	# Run-up: plain slabs from behind the start to bar 1.
	var z := runup_z0
	var z_bar1 := c.z_at(c.bar_start(1))
	while z < z_bar1 - 0.01:
		var len := minf(PLAIN_LEN, z_bar1 - z)
		_slab(z, len)
		z += len

	for bar in range(1, c.bar_count() + 1):
		var z0 := c.z_at(c.bar_start(bar))
		var z1 := c.z_at(c.bar_end(bar))
		_bar_z0.append(z0)
		_bar_z1.append(z1)
		_bar_tiles(bar, z0, z1)

	var end_z := c.z_at(c.bar_end(c.bar_count()))
	for k in 3:
		_slab(end_z + k * PLAIN_LEN, PLAIN_LEN)
	outro_z1 = end_z + 3 * PLAIN_LEN
	goal_z = outro_z1 - 1.0
	_gate_mesh(goal_z)

	for spec in plan["hazards"]:
		var h: Node3D
		match String(spec["kind"]):
			"sweeper":
				h = Sweeper.new()
			"orbiter":
				h = Orbiter.new()
			"gate":
				h = Gate.new()
			_:
				h = Slammer.new()
		add_child(h)
		h.setup(spec)
		hazards.append(h)

	for n in plan["notes"]:
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.4
		sm.height = 0.8
		sm.radial_segments = 12
		sm.rings = 6
		mi.mesh = sm
		mi.material_override = Mats.amber()
		mi.position = Vector3(float(n["x"]), 1.0, float(n["z"]))
		add_child(mi)
		notes.append({"x": float(n["x"]), "z": float(n["z"]), "node": mi, "taken": false})

	for cp in plan["checkpoints"]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(Rules.FIELD_WIDTH, 0.06, 0.3)
		mi.mesh = bm
		mi.material_override = Mats.amber()
		mi.position = Vector3(0.0, 0.03, c.z_at(float(cp["t"])))
		add_child(mi)
		var entry: Dictionary = cp.duplicate()
		entry["node"] = mi
		checkpoints.append(entry)


func _slab(z_start: float, length: float) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(Rules.FIELD_WIDTH, THICK, maxf(length - SEAM, 0.2))
	mi.mesh = bm
	mi.material_override = Mats.cyan()
	mi.position = Vector3(0.0, -THICK * 0.5, z_start + length * 0.5)
	add_child(mi)


func _bar_tiles(bar: int, z0: float, z1: float) -> void:
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
			bm.size = Vector3(Rules.TILE - TILE_SEAM, THICK, depth - TILE_SEAM)
			mi.mesh = bm
			mi.material_override = Mats.cyan()
			mi.position = Vector3(Rules.col_x(col), -THICK * 0.5, z0 + (row + 0.5) * depth)
			add_child(mi)
			arr[idx] = mi
	_tiles[bar] = arr
	_tile_state[bar] = states


func _gate_mesh(z: float) -> void:
	for x in [-Rules.half_width() - 0.2, Rules.half_width() + 0.2]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.4, 3.2, 0.4)
		post.mesh = bm
		post.material_override = Mats.amber()
		post.position = Vector3(x, 1.6, z)
		add_child(post)
	var top := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(Rules.FIELD_WIDTH + 0.8, 0.4, 0.4)
	top.mesh = tb
	top.material_override = Mats.amber()
	top.position = Vector3(0.0, 3.4, z)
	add_child(top)


# ------------------------------------------------------------
# Queries
# ------------------------------------------------------------
func bar_at_z(z: float) -> int:
	if _bar_z0.is_empty() or z < _bar_z0[0] or z >= _bar_z1[-1]:
		return 0
	return _bar_z0.bsearch(z, false)   # count of starts <= z == 1-based bar


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
	var depth := (_bar_z1[bar - 1] - _bar_z0[bar - 1]) / Rules.ROWS
	var row := clampi(int(floor((z - _bar_z0[bar - 1]) / depth)), 0, Rules.ROWS - 1)
	return Vector2i(col, row)


# The plate state under (x, z) at hazard time t.
func tile_state_at(x: float, z: float, t: float) -> int:
	var bar := bar_at_z(z)
	if bar == 0:
		return TileState.SAFE
	var tile := tile_at(bar, x, z)
	return _state_for(bar, tile.x, tile.y, t)


func _state_for(bar: int, col: int, row: int, t: float) -> int:
	if not BeatClock.hazards_armed_at(t):
		return TileState.SAFE
	var pattern := String(plan["bars"][bar]["pattern"])
	if pattern == "none":
		return TileState.SAFE
	var k := BeatClock.beat_in_bar_at(t)
	var phase := BeatClock.beat_phase_at(t)
	if Rules.pattern_lethal(pattern, col, row, k) and phase < Rules.LETHAL_BEAT_FRACTION:
		return TileState.LETHAL
	if phase >= 1.0 - Rules.LETHAL_BEAT_FRACTION and Rules.pattern_lethal(pattern, col, row, (k + 1) % 4):
		return TileState.ARMED
	return TileState.SAFE


# Repaint the tiles of the bars near the window. Only changed tiles touch
# their material, so this is cheap.
func update_tiles(t: float, z_back: float) -> void:
	if _bar_z0.is_empty():
		return
	var lo := bar_at_z(maxf(z_back - 2.0, _bar_z0[0] if not _bar_z0.is_empty() else 0.0))
	var hi := bar_at_z(minf(z_back + Rules.WINDOW_DEPTH + 8.0, _bar_z1[-1] - 0.01))
	if lo == 0 and hi == 0:
		return
	if lo == 0:
		lo = 1
	if hi == 0:
		hi = BeatClock.bar_count()
	for bar in range(lo, hi + 1):
		var arr: Array = _tiles[bar]
		var states: PackedInt32Array = _tile_state[bar]
		for col in Rules.COLS:
			for row in Rules.ROWS:
				var idx := col * Rules.ROWS + row
				var mi = arr[idx]
				if mi == null:
					continue
				var s := _state_for(bar, col, row, t)
				if s != states[idx]:
					states[idx] = s
					match s:
						TileState.LETHAL:
							mi.material_override = Mats.magenta()
						TileState.ARMED:
							mi.material_override = Mats.magenta_dim()
						_:
							mi.material_override = Mats.cyan()
		_tile_state[bar] = states


# Nearest tile near (x, z) that is lethal now or armed, for the eye.
func nearest_danger_tile(x: float, z: float, t: float) -> Variant:
	var bar := bar_at_z(z)
	if bar == 0:
		return null
	var best: Variant = null
	var best_d := 1e9
	for b in range(maxi(1, bar - 1), mini(BeatClock.bar_count(), bar + 1) + 1):
		var entry: Dictionary = plan["bars"][b]
		if entry["pattern"] == "none":
			continue
		var z0 := _bar_z0[b - 1]
		var depth := (_bar_z1[b - 1] - z0) / Rules.ROWS
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


func mark_checkpoint(i: int) -> void:
	checkpoints[i]["node"].material_override = Mats.amber_dim()


func reset_run() -> void:
	for cp in checkpoints:
		cp["node"].material_override = Mats.amber()
	for n in notes:
		n["taken"] = false
		n["node"].visible = true
