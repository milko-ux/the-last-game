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
const Props := preload("res://prototype/props/props.gd")

var _line: MeshInstance3D
var _muzzle: Node3D
var _had_orb := false
var _squash_t := 99.0
const SQUASH := 0.15
const SQUASH_IN_S := 0.1
const SQUASH_OUT_S := 0.2


func _build() -> void:
	var demo := bool(spec.get("demo", false))
	_orb = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = HazardMath.VOLLEY_R
	sm.height = HazardMath.VOLLEY_R * 2.0
	sm.radial_segments = 14
	sm.rings = 7
	_orb.mesh = sm
	_orb.material_override = Mats.orb(not demo)
	_orb.visible = false
	add_child(_orb)

	_line = _box_mesh(Vector3(Rules.FIELD_WIDTH, 0.04, 0.16), Mats.magenta_dim())
	_line.position = Vector3(0.0, 0.02, 0.0)
	_line.visible = false

	# Brief 4: the half-buried clay egg at the field edge, its open eye
	# looking across the field (the model's eye faces +z; +90 deg turns
	# it to +x). Fitted to the old muzzle box's height (1.4).
	var d := float(spec.get("dir", 1))
	var ms := Props.size_of("volley_emitter")
	var k := 1.4 / ms.y
	_muzzle = Props.make("volley_emitter", ms * k, "base", Props.clay(false), 90.0 * d)
	_muzzle.position = Vector3(-d * (Rules.half_width() + 0.6), -0.3, 0.0)
	add_child(_muzzle)


func _pose(t: float) -> void:
	var warn := HazardMath.volley_warning(spec, t, knobs)
	var vx: Variant = HazardMath.volley_orb_x(spec, t, knobs)
	_orb.visible = vx != null
	# On fire: the emitter squashes 15 % and springs back (brief 4).
	if vx != null and not _had_orb:
		_squash_t = 0.0
		_note("fire")
	if warn != _line.visible:
		_note("warning line")
	_line.visible = warn
	_had_orb = vx != null
	_squash_t += get_process_delta_time()
	var sq := 0.0
	if _squash_t < SQUASH_IN_S:
		sq = _squash_t / SQUASH_IN_S
	elif _squash_t < SQUASH_IN_S + SQUASH_OUT_S:
		var u := (_squash_t - SQUASH_IN_S) / SQUASH_OUT_S
		sq = cos(u * PI * 1.5) * (1.0 - u)
	_muzzle.scale = Vector3(1.0 + sq * SQUASH * 0.5, 1.0 - sq * SQUASH, 1.0 + sq * SQUASH * 0.5)
	if vx != null:
		_orb.position = Vector3(float(vx) - float(spec["x"]), HazardMath.VOLLEY_R, 0.0)
