extends "res://prototype/hazard3d.gd"
# ============================================================
# SWEEPER — two magenta walls filling one whole bar of track with
# a one-lane gap between them. The gap travels from one edge lane
# to the other across exactly one bar, so the player rides the
# gap. Position is driven from bar progress, never a tween.
# ============================================================

const H := 3.0
const GAP := 2.0
const HALF_TRACK := 3.0

var depth := 8.0
var _left: MeshInstance3D
var _right: MeshInstance3D
var _gap_x := 0.0
var _bar_start := 0.0
var _bar_end := 1.0


func setup_span(bar_start: float, bar_end: float, seg_depth: float) -> void:
	_bar_start = bar_start
	_bar_end = bar_end
	depth = seg_depth


func _build() -> void:
	position.x = 0.0
	_left = _box_mesh(Vector3(1.0, H, 1.0), Mats.magenta())
	_right = _box_mesh(Vector3(1.0, H, 1.0), Mats.magenta())
	_lethal = true


func update_state(t: float) -> void:
	var p := clampf((t - _bar_start) / (_bar_end - _bar_start), 0.0, 1.0)
	_gap_x = lerpf(-2.0 * dir, 2.0 * dir, p)
	var lw := (_gap_x - GAP * 0.5) + HALF_TRACK
	var rw := HALF_TRACK - (_gap_x + GAP * 0.5)
	_left.scale = Vector3(maxf(lw, 0.001), 1.0, depth)
	_left.position = Vector3(-HALF_TRACK + lw * 0.5, H * 0.5, 0.0)
	_left.visible = lw > 0.01
	_right.scale = Vector3(maxf(rw, 0.001), 1.0, depth)
	_right.position = Vector3(HALF_TRACK - rw * 0.5, H * 0.5, 0.0)
	_right.visible = rw > 0.01


func boxes() -> Array:
	var gp := global_position
	var lw := (_gap_x - GAP * 0.5) + HALF_TRACK
	var rw := HALF_TRACK - (_gap_x + GAP * 0.5)
	var out := []
	if lw > 0.01:
		out.append(AABB(Vector3(gp.x - HALF_TRACK, gp.y, gp.z - depth * 0.5), Vector3(lw, H, depth)))
	if rw > 0.01:
		out.append(AABB(Vector3(gp.x + HALF_TRACK - rw, gp.y, gp.z - depth * 0.5), Vector3(rw, H, depth)))
	return out
