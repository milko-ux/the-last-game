extends "res://prototype/hazard3d.gd"
# ============================================================
# VOLLEY — "something thrown at you" (addendum 3). A magenta orb
# fired from one edge of the field along one tile-row, crossing the
# full width in exactly one period. The period before: a thin dark
# line along the row and a muzzle block at the edge it comes from.
# Lethal only on contact with the orb; low enough to jump.
# ============================================================

const Rules := preload("res://prototype/rules.gd")

var _orb: MeshInstance3D
var _line: MeshInstance3D
var _muzzle: MeshInstance3D


func _build() -> void:
	var demo := bool(spec.get("demo", false))
	_orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = HazardMath.VOLLEY_R
	sm.height = HazardMath.VOLLEY_R * 2.0
	sm.radial_segments = 14
	sm.rings = 7
	_orb.mesh = sm
	_orb.material_override = Mats.magenta_dim() if demo else Mats.magenta()
	_orb.visible = false
	add_child(_orb)

	_line = _box_mesh(Vector3(Rules.FIELD_WIDTH, 0.04, 0.16), Mats.magenta_dim())
	_line.position = Vector3(0.0, 0.02, 0.0)
	_line.visible = false

	var d := float(spec.get("dir", 1))
	_muzzle = _box_mesh(Vector3(0.8, 1.2, 1.4), Mats.magenta_dim())
	_muzzle.position = Vector3(-d * (Rules.half_width() + 0.6), 0.6, 0.0)


func _pose(t: float) -> void:
	var warn := HazardMath.volley_warning(spec, t)
	_line.visible = warn
	_muzzle.visible = warn or HazardMath.volley_orb_x(spec, t) != null
	var vx: Variant = HazardMath.volley_orb_x(spec, t)
	_orb.visible = vx != null
	if vx != null:
		_orb.position = Vector3(float(vx) - float(spec["x"]), HazardMath.VOLLEY_R, 0.0)
