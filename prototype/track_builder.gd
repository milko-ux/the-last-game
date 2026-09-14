extends Node3D
# ============================================================
# TRACK BUILDER — builds the straight gray-box track from the
# beatmap. One segment per bar (8 units long, 6 wide, three
# implicit lanes), a run-up before bar 1, three plain segments
# and an amber gate after the last bar.
#
# Hazards are children of their bar's segment and are placed at
# beat offsets WITHIN the bar, so the placement generator only
# ever talks in beats.
# ============================================================

const Placement := preload("res://prototype/placement.gd")
const Mats := preload("res://prototype/flat_mats.gd")
const Slammer := preload("res://prototype/hazard_slammer.gd")
const Pulser := preload("res://prototype/hazard_pulser.gd")
const Sweeper := preload("res://prototype/hazard_sweeper.gd")

const WIDTH := 6.0
const HALF_WIDTH := 3.0
const THICK := 0.5
const GAP := 0.1          # visible seam between segments = bar boundary
const PLAIN_LEN := 8.0    # run-up / outro segment length

var hazards: Array = []
var checkpoints: Array = []   # dicts from placement + "node"
var goal_z := 0.0
var _segments := {}           # bar -> segment root


func build() -> void:
	var c := BeatClock
	if not c.loaded:
		push_error("TrackBuilder: beatmap not loaded")
		return

	# Run-up: one plain segment behind the start, then plain segments up to bar 1.
	var z := -PLAIN_LEN
	var z_bar1 := c.z_at(c.bar_start(1))
	var i := 0
	while z < z_bar1 - 0.01:
		var len := minf(PLAIN_LEN, z_bar1 - z)
		_segment(z, len, "RunUp%d" % i)
		z += len
		i += 1

	for bar in range(1, c.bar_count() + 1):
		var s := c.z_at(c.bar_start(bar))
		var e := c.z_at(c.bar_end(bar))
		_segments[bar] = _segment(s, e - s, "Bar%d" % bar)

	var end_z := c.z_at(c.bar_end(c.bar_count()))
	for k in 3:
		_segment(end_z + k * PLAIN_LEN, PLAIN_LEN, "Outro%d" % k)
	goal_z = end_z + 3 * PLAIN_LEN
	_gate(goal_z)

	var plan := Placement.build(c)
	for spec in plan["hazards"]:
		var bar: int = spec["bar"]
		var seg: Node3D = _segments[bar]
		var h: Node3D
		match String(spec["kind"]):
			"pulser":
				h = Pulser.new()
			"sweeper":
				h = Sweeper.new()
			_:
				h = Slammer.new()
		seg.add_child(h)
		h.setup(spec, c.beat_interval)
		if h is Sweeper:
			h.position.z = 0.0
			h.setup_span(c.bar_start(bar), c.bar_end(bar), float(seg.get_meta("length")) - GAP)
		else:
			h.position.z = c.z_at(float(spec["t"])) - seg.position.z
		hazards.append(h)

	for cp in plan["checkpoints"]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(WIDTH, 0.06, 0.3)
		mi.mesh = bm
		mi.material_override = Mats.amber()
		mi.position = Vector3(0.0, 0.03, c.z_at(float(cp["t"])))
		add_child(mi)
		cp["node"] = mi
		checkpoints.append(cp)


func _segment(z_start: float, length: float, seg_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = seg_name
	root.position = Vector3(0.0, 0.0, z_start + length * 0.5)
	root.set_meta("length", length)
	add_child(root)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(WIDTH, THICK, maxf(length - GAP, 0.2))
	mi.mesh = bm
	mi.material_override = Mats.cyan()
	mi.position.y = -THICK * 0.5
	root.add_child(mi)
	return root


func _gate(z: float) -> void:
	var gate := Node3D.new()
	gate.name = "Gate"
	gate.position = Vector3(0.0, 0.0, z)
	add_child(gate)
	for x in [-3.2, 3.2]:
		var post := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.4, 3.2, 0.4)
		post.mesh = bm
		post.material_override = Mats.amber()
		post.position = Vector3(x, 1.6, 0.0)
		gate.add_child(post)
	var top := MeshInstance3D.new()
	var tb := BoxMesh.new()
	tb.size = Vector3(6.8, 0.4, 0.4)
	top.mesh = tb
	top.material_override = Mats.amber()
	top.position = Vector3(0.0, 3.4, 0.0)
	gate.add_child(top)


func mark_checkpoint(i: int) -> void:
	checkpoints[i]["node"].material_override = Mats.amber_dim()


func clear_checkpoints() -> void:
	for cp in checkpoints:
		cp["node"].material_override = Mats.amber()
