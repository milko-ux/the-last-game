extends Node3D
# ============================================================
# HAZARD (base) — a hazard node is a pure function of song time.
#
# update_state(t) is called every frame with BeatClock.hazard_time();
# the node asks hazard_math.gd where it is and whether it is lethal,
# and poses its meshes to match. No timers, no tweens, no own
# timeline, so a rewind of the song just re-derives everything.
# The fairness validator uses the very same math.
# ============================================================

const Mats := preload("res://prototype/flat_mats.gd")
const HazardMath := preload("res://prototype/hazard_math.gd")

var spec := {}
var knobs := {}      # the knob dictionary of the lap / level this hazard belongs to
var kind := ""
var _boxes: Array = []


func setup(s: Dictionary, k: Dictionary) -> void:
	spec = s
	knobs = k
	kind = String(s["kind"])
	position = Vector3(float(s["x"]), 0.0, float(s["z"]))
	_build()


func _build() -> void:
	pass


func _pose(_t: float) -> void:
	pass


func update_state(t: float) -> void:
	_boxes = HazardMath.boxes_at(spec, t, knobs)
	_pose(t)


# Dev only (frame_meter.gd): names what this hazard just did, so a slow
# frame can be pinned on it. One static bool test when the meter is off.
func _note(what: String) -> void:
	if FrameMeter.active:
		FrameMeter.note_at(kind + " " + what, position.z)


# Brief 6 section 2: the hazard's drop shadows, one cast_round / cast_bar
# per thing that stands on or flies over the floor. Positions are the
# posed nodes', i.e. hazard_math's for the song time.
func cast_shadows(_sh: Node) -> void:
	pass


func is_lethal() -> bool:
	return not _boxes.is_empty()


# World-space boxes that kill right now.
func boxes() -> Array:
	return _boxes


# Boxes at a future time (used by the eye: "lethal within the next beat").
func boxes_at(t: float) -> Array:
	return HazardMath.boxes_at(spec, t, knobs)


func _box_mesh(size: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = Mats.box(size)
	mi.material_override = mat
	add_child(mi)
	return mi
