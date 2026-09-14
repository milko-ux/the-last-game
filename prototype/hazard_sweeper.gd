extends "res://prototype/hazard3d.gd"
# ============================================================
# SWEEPER — a full-height magenta wall across the field with a
# 3-unit gap that crosses the field once per bar (and back over
# the next), locked to the downbeats. Thread the gap.
# ============================================================

const Rules := preload("res://prototype/rules.gd")

var _left: MeshInstance3D
var _right: MeshInstance3D


func _build() -> void:
	_left = _box_mesh(Vector3(1.0, HazardMath.WALL_H, HazardMath.WALL_D), Mats.magenta())
	_right = _box_mesh(Vector3(1.0, HazardMath.WALL_H, HazardMath.WALL_D), Mats.magenta())


func _pose(t: float) -> void:
	_pose_walls(HazardMath.sweeper_gap_x(spec, t), HazardMath.SWEEP_GAP)


func _pose_walls(gx: float, gap: float) -> void:
	var hw := Rules.half_width()
	var lw := (gx - gap * 0.5) + hw
	var rw := hw - (gx + gap * 0.5)
	_left.visible = lw > 0.01
	_left.scale.x = maxf(lw, 0.001)
	_left.position = Vector3(-hw + lw * 0.5, HazardMath.WALL_H * 0.5, 0.0)
	_right.visible = rw > 0.01
	_right.scale.x = maxf(rw, 0.001)
	_right.position = Vector3(hw - rw * 0.5, HazardMath.WALL_H * 0.5, 0.0)
