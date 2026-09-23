extends "res://prototype/hazard3d.gd"
# ============================================================
# SLAMMER — one-tile magenta bar hovering over the floor that
# drops at the start of its firing periods (every other period)
# and lifts by the next beat. Telegraphed: bright for the whole
# period before the drop, dim otherwise.
# Low when down, so a jump clears it. A `low`-band accent.
# ============================================================

const Props := preload("res://prototype/props/props.gd")

var _mesh: Node3D
var _hot := false


# Brief 4: the plump clay block, scaled uniformly to the hit box's width
# (1.9); its flat underside sits exactly on the box's bottom plane. The
# block is taller than the 0.6-unit box — the extra is above, where
# nothing can be, so the lethal face is where it looks.
func _build() -> void:
	var ms := Props.size_of("slammer")
	var k := HazardMath.SLAM_W / ms.x
	_mesh = Props.make("slammer", ms * k, "base", Props.clay(false))
	_mesh.position.y = HazardMath.SLAM_HOVER
	add_child(_mesh)


func _pose(t: float) -> void:
	var bottom := HazardMath.slammer_bottom(spec, t, knobs)
	_mesh.position.y = bottom
	# Bright for the whole period before the drop until it is back up.
	var hot: bool = HazardMath.slammer_hot(spec, t, knobs) and BeatClock.hazards_armed_at(t) \
		and not bool(spec.get("demo", false))
	if hot != _hot:
		_hot = hot
		_note("material swap")
		for mi in _mesh.find_children("*", "MeshInstance3D", true, false):
			mi.material_override = Props.clay(hot)


# Its footprint, from wherever its underside is: tight and dark when it
# is down, wide and faint when it hovers (brief 6 section 2).
func cast_shadows(sh: Node) -> void:
	sh.cast_bar(_mesh.global_position, 0.0, HazardMath.SLAM_W * 0.5, HazardMath.SLAM_D * 0.5, HazardMath.SLAM_H)
