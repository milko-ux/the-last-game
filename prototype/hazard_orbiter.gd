extends "res://prototype/hazard3d.gd"
# ============================================================
# ORBITER — a cyan pillar (safe to touch, no collision) with one
# magenta orb circling it at radius 3, one revolution per bar,
# phase locked to the downbeat.
# ============================================================

var _orb: MeshInstance3D


const Props := preload("res://prototype/props/props.gd")
# Brief 4: the squat clay pillar; its groove ring sits 55 % up the model
# (measured on the GLB), so the pillar is scaled until the groove is at
# the orb's orbit height. The pillar is safe and never lethal.
const GROOVE_AT := 0.55


func _build() -> void:
	var ms := Props.size_of("orbiter_pillar")
	var k := HazardMath.ORB_Y / (ms.y * GROOVE_AT)
	var pillar := Props.make("orbiter_pillar", ms * k, "base", Props.clay_safe())
	add_child(pillar)

	_orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = HazardMath.ORB_R
	sm.height = HazardMath.ORB_R * 2.0
	sm.radial_segments = 12
	sm.rings = 6
	_orb.mesh = sm
	_orb.material_override = Mats.orb(not bool(spec.get("demo", false)))
	add_child(_orb)


func _pose(t: float) -> void:
	_orb.global_position = HazardMath.orbiter_orb_pos(spec, t)


# The pillar on the floor, the orb from its orbit height (brief 6 section 2).
func cast_shadows(sh: Node) -> void:
	sh.cast_round(global_position, 0.0, HazardMath.PILLAR_R, HazardMath.ORB_Y / GROOVE_AT)
	sh.cast_round(_orb.global_position, 0.0, HazardMath.ORB_R, HazardMath.ORB_R * 2.0)
