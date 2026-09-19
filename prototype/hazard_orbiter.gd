extends "res://prototype/hazard3d.gd"
# ============================================================
# ORBITER — a cyan pillar (safe to touch, no collision) with one
# magenta orb circling it at radius 3, one revolution per bar,
# phase locked to the downbeat.
# ============================================================

var _orb: MeshInstance3D


func _build() -> void:
	var pillar := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = HazardMath.PILLAR_R
	cm.bottom_radius = HazardMath.PILLAR_R
	cm.height = 3.0
	cm.radial_segments = 12
	pillar.mesh = cm
	pillar.material_override = Mats.stone(WorldPalette.SAFE.darkened(0.55), Vector3(HazardMath.PILLAR_R, 1.5, HazardMath.PILLAR_R))   # safe: the floor's stone
	pillar.position.y = 1.5
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
