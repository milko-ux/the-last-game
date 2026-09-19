extends "res://prototype/hazard_sweeper.gd"
# ============================================================
# GATE — a full-width magenta wall at the front of its bar with an
# opening (Rules.gate_gap() wide) that jumps to a new seeded x at
# every period start. It rehearses that through the intro in the
# warning colour. You see it a bar out and have to commit.
#
# Brief 3: the VISUAL wall slides to the new x over SLIDE_S instead
# of teleporting. The rules (hazard_math.gate_opening_x / gate_crossed)
# still jump instantly; the slide starts the frame the rules changed,
# never before, so the mesh never shows an opening that isn't real yet.
# ============================================================

const SLIDE_S := 0.12

var _target_gx := INF
var _from_gx := 0.0
var _slide_t := 1.0
var _last_t := -INF


func _pose(t: float) -> void:
	_set_hot(t)
	var gx := HazardMath.gate_opening_x(spec, t)
	if gx != _target_gx:
		# A rewind (time went backwards) snaps; a period jump slides.
		_from_gx = _visual_gx() if t >= _last_t and _target_gx != INF else gx
		_target_gx = gx
		_slide_t = 0.0
	_slide_t += get_process_delta_time()
	_last_t = t
	_pose_walls(_visual_gx(), Rules.gate_gap())


func _visual_gx() -> float:
	var u := clampf(_slide_t / SLIDE_S, 0.0, 1.0)
	return lerpf(_from_gx, _target_gx, u * u * (3.0 - 2.0 * u))
