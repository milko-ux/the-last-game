extends "res://prototype/hazard3d.gd"
# ============================================================
# SLAMMER — one-tile magenta bar hovering over the floor that
# drops at the start of its firing periods (every other period)
# and lifts by the next beat. Telegraphed: bright for the whole
# period before the drop, dim otherwise.
# Low when down, so a jump clears it. A `low`-band accent.
# ============================================================

var _mesh: MeshInstance3D
var _hot := false


func _build() -> void:
	_mesh = _box_mesh(Vector3(HazardMath.SLAM_W, HazardMath.SLAM_H, HazardMath.SLAM_D), Mats.magenta_dim())
	_mesh.position.y = HazardMath.SLAM_HOVER + HazardMath.SLAM_H * 0.5


func _pose(t: float) -> void:
	var bottom := HazardMath.slammer_bottom(spec, t)
	_mesh.position.y = bottom + HazardMath.SLAM_H * 0.5
	# Bright for the whole period before the drop until it is back up.
	var hot: bool = HazardMath.slammer_hot(spec, t) and BeatClock.hazards_armed_at(t) \
		and not bool(spec.get("demo", false))
	if hot != _hot:
		_hot = hot
		_mesh.material_override = Mats.magenta() if hot else Mats.magenta_dim()
