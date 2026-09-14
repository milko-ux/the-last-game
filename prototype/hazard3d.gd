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
var kind := ""
var _boxes: Array = []


func setup(s: Dictionary) -> void:
	spec = s
	kind = String(s["kind"])
	position = Vector3(float(s["x"]), 0.0, float(s["z"]))
	_build()


func _build() -> void:
	pass


func _pose(_t: float) -> void:
	pass


func update_state(t: float) -> void:
	_boxes = HazardMath.boxes_at(spec, t)
	_pose(t)


func is_lethal() -> bool:
	return not _boxes.is_empty()


# World-space boxes that kill right now.
func boxes() -> Array:
	return _boxes


# Boxes at a future time (used by the eye: "lethal within the next beat").
func boxes_at(t: float) -> Array:
	return HazardMath.boxes_at(spec, t)


func _box_mesh(size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	add_child(mi)
	return mi
