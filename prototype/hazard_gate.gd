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
#
# Brief 4: drawn as clay pillars (one model, the right side mirrored)
# from each edge of the opening out to the field edge, so the pillars'
# inner faces ARE the opening: they sit at gx +- gap/2, which is the
# rules' opening to the unit. The whole wall span is still drawn (it
# all kills), as a row of pillars.
# ============================================================

const SLIDE_S := 0.12

var _target_gx := INF
var _from_gx := 0.0
var _slide_t := 1.0
var _last_t := -INF
var _pillar_w := 1.0


func _build() -> void:
	var ms := Props.size_of("gate_pillar")
	var k := HazardMath.WALL_H / ms.y
	_pillar_w = ms.x * k
	_seg_size = Vector3(_pillar_w, HazardMath.WALL_H, ms.z * k)
	_left = Node3D.new()
	_right = Node3D.new()
	add_child(_left)
	add_child(_right)
	for i in MAX_SEGS:
		_left_segs.append(_pillar(_left, -1.0, i))
		_right_segs.append(_pillar(_right, 1.0, i))


func _pillar(parent: Node3D, side: float, i: int) -> Node3D:
	var p := Props.make("gate_pillar", _seg_size, "base", Props.clay(false), 0.0, side > 0.0)
	p.position = Vector3(side * (_pillar_w * 0.5 + _pillar_w * i), 0.0, 0.0)
	parent.add_child(p)
	return p


func _pose(t: float) -> void:
	_set_hot(t)
	var gx := HazardMath.gate_opening_x(spec, t, knobs)
	if gx != _target_gx:
		# A rewind (time went backwards) snaps; a period jump slides.
		_from_gx = _visual_gx() if t >= _last_t and _target_gx != INF else gx
		_target_gx = gx
		_slide_t = 0.0
		_note("jump")
	_slide_t += get_process_delta_time()
	_last_t = t
	_pose_pillars(_visual_gx(), Rules.gate_gap(knobs))


func _visual_gx() -> float:
	var u := clampf(_slide_t / SLIDE_S, 0.0, 1.0)
	return lerpf(_from_gx, _target_gx, u * u * (3.0 - 2.0 * u))


func _pose_pillars(gx: float, gap: float) -> void:
	var hw := Rules.half_width()
	var lw := (gx - gap * 0.5) + hw
	var rw := hw - (gx + gap * 0.5)
	_left.position.x = gx - gap * 0.5
	_right.position.x = gx + gap * 0.5
	var nl := clampi(ceili(lw / _pillar_w), 0, MAX_SEGS)
	var nr := clampi(ceili(rw / _pillar_w), 0, MAX_SEGS)
	for i in MAX_SEGS:
		_left_segs[i].visible = i < nl
		_right_segs[i].visible = i < nr
