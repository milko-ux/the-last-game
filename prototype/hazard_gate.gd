extends "res://prototype/hazard_sweeper.gd"
# ============================================================
# GATE — a full-width magenta wall at the front of its bar with a
# 4-unit opening that jumps to a new (seeded) x on every downbeat.
# You see it a bar out and have to commit.
# ============================================================


func _pose(t: float) -> void:
	_pose_walls(HazardMath.gate_opening_x(spec, t), HazardMath.GATE_GAP)
