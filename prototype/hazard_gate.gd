extends "res://prototype/hazard_sweeper.gd"
# ============================================================
# GATE — a full-width magenta wall at the front of its bar with an
# opening (Rules.gate_gap() wide) that jumps to a new seeded x at
# every period start. It rehearses that through the intro in the
# warning colour. You see it a bar out and have to commit.
# ============================================================


func _pose(t: float) -> void:
	_set_hot(t)
	_pose_walls(HazardMath.gate_opening_x(spec, t), Rules.gate_gap())
