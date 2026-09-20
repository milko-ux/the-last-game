extends "res://prototype/hazard3d.gd"
# ============================================================
# SWEEPER — a full-height magenta wall across the field with a
# 3-unit gap that crosses the field once per bar (and back over
# the next), locked to the downbeats. Thread the gap.
#
# Brief 4: drawn as a train of clay loaf segments (one model,
# repeated) on each side of the gap, two rows high, rounded ends at
# the gap. The hit boxes (hazard_math.gd) are unchanged; the train
# is placed so its inner ends sit exactly on the gap's edges.
# ============================================================

const Rules := preload("res://prototype/rules.gd")
const Props := preload("res://prototype/props/props.gd")

const SEG_LEN := 2.0                  # brief 4: segments are 2 units long
const ROWS := 2                       # stacked rows: the wall is WALL_H tall, a loaf is not
const MAX_SEGS := 10                  # per side (a 9-tile field is 9 segments minus the gap)

var _left: Node3D
var _right: Node3D
var _left_segs: Array = []            # Node3D per segment, index 0 nearest the gap
var _right_segs: Array = []
var _hot := false
var _seg_size := Vector3.ZERO


func _build() -> void:
	var ms := Props.size_of("sweeper_segment")
	var k := SEG_LEN / ms.x
	_seg_size = Vector3(SEG_LEN, HazardMath.WALL_H / ROWS, ms.z * k)
	_left = Node3D.new()
	_right = Node3D.new()
	add_child(_left)
	add_child(_right)
	for i in MAX_SEGS:
		_left_segs.append(_segment(_left, -1.0, i))
		_right_segs.append(_segment(_right, 1.0, i))


func _segment(parent: Node3D, side: float, i: int) -> Node3D:
	var col := Node3D.new()
	col.position = Vector3(side * (SEG_LEN * 0.5 + SEG_LEN * i), 0.0, 0.0)
	for row in ROWS:
		# The rounded end faces the gap: mirror the segment on the right.
		var seg := Props.make("sweeper_segment", _seg_size, "base", Props.clay(false), 0.0, side > 0.0)
		seg.position.y = _seg_size.y * row
		col.add_child(seg)
	parent.add_child(col)
	return col


func _pose(t: float) -> void:
	_set_hot(t)
	_pose_walls(HazardMath.sweeper_gap_x(spec, t), Rules.sweep_gap())


# Warning colour while inert (the intro rehearsal) and on a demo; the
# real thing once armed.
func _set_hot(t: float) -> void:
	var hot: bool = BeatClock.hazards_armed_at(t) and not bool(spec.get("demo", false))
	if hot != _hot or not _hot_applied:
		_hot = hot
		_hot_applied = true
		_note("material swap")
		var mat := Props.clay(hot)
		for mi in find_children("*", "MeshInstance3D", true, false):
			mi.material_override = mat

var _hot_applied := false


# The left train runs from the gap's left edge to the field edge (and a
# little past it: whole segments only), the right train likewise.
func _pose_walls(gx: float, gap: float) -> void:
	var hw := Rules.half_width()
	var lw := (gx - gap * 0.5) + hw       # left wall length
	var rw := hw - (gx + gap * 0.5)       # right wall length
	_left.position.x = gx - gap * 0.5
	_right.position.x = gx + gap * 0.5
	var nl := clampi(ceili(lw / SEG_LEN), 0, MAX_SEGS)
	var nr := clampi(ceili(rw / SEG_LEN), 0, MAX_SEGS)
	for i in MAX_SEGS:
		_left_segs[i].visible = i < nl
		_right_segs[i].visible = i < nr
