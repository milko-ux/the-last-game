extends "res://prototype/hazard3d.gd"
# ============================================================
# SLAMMER — one-tile magenta bar hovering over the floor that
# drops on its beat of every bar and lifts by the next beat.
# Telegraphed: dim while hovering, bright from one beat early.
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
	# Bright from one beat before the drop until it is back up.
	var hot := false
	if BeatClock.hazards_armed_at(t):
		var bar := BeatClock.bar_at(t)
		var k := int(spec.get("beat", 0))
		for b in [bar, bar + 1]:
			if b >= 1 and b <= BeatClock.bar_count():
				var dt: float = t - BeatClock.bar_beats(b)[k]
				if dt >= -BeatClock.beat_interval and dt < BeatClock.beat_interval:
					hot = true
	if hot != _hot:
		_hot = hot
		_mesh.material_override = Mats.magenta() if hot else Mats.magenta_dim()
