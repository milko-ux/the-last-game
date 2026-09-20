extends Node3D
# ============================================================
# PREWARM — draws every material the level can show ONCE, behind the
# "TAP TO START" screen, so none of them is drawn for the first time
# in the middle of a run.
#
# Why: the web renderer compiles a shader the first time something
# using it is actually drawn, and that compile blocks the frame. It was
# measured (tools/frame_probe.gd, cold shader cache, 2026-09-20): about
# 100 ms each at the first note pickup (the particle burst), the first
# checkpoint (the first flat-shader material) and the first time a new
# kind of hazard scrolled into view; the first death adds the white
# killer flash and the creature's burst. On a phone these are longer.
#
# How: a rack of the REAL meshes with the REAL materials (the same
# mesh + material pair is what the GPU driver keys its pipeline on),
# scaled to a thousandth at the point the camera looks at: inside the
# view, so they are drawn, and far below a pixel, so nothing is seen.
# The two particle bursts are warmed with invisible copies of the real
# emitters. The rack frees itself after FRAMES frames.
# ============================================================

const Mats := preload("res://prototype/flat_mats.gd")
const Props := preload("res://prototype/props/props.gd")

const FRAMES := 8
const TINY := 0.001
const HAZARD_MODELS := ["gate_pillar", "sweeper_segment", "slammer", "orbiter_pillar", "volley_emitter"]
const BUILDING_MODELS := ["building_tall", "building_stacked", "building_tall_hi", "building_stacked_hi"]

var _frames := 0


func build(bursts: Array) -> void:
	scale = Vector3.ONE * TINY
	var white := Mats.white_flat()
	var half := Vector3.ONE
	var box := BoxMesh.new()
	for m in [Mats.tile(0, half), Mats.tile(1, half), Mats.tile(2, half), Mats.cyan(),
			Mats.flat(WorldPalette.SAFE.darkened(0.55)), Mats.amber_dim(), Mats.magenta(), Mats.magenta_dim(),
			Mats.magenta_wall(), Mats.magenta_wall_dim(), Mats.amber(), white]:
		_mesh(box, m)
	var ball := SphereMesh.new()
	for m in [Mats.orb(true), Mats.orb(false), Mats.note(), white]:
		_mesh(ball, m)
	# The clay props: armed, live, safe, and the white flash, on each model
	# (and mirrored, as the right-hand gate pillars and sweeper segments are).
	for model in HAZARD_MODELS:
		for m in [Props.clay(false), Props.clay(true), Props.clay_safe(), white]:
			add_child(Props.make(model, Props.size_of(model), "base", m))
		add_child(Props.make(model, Props.size_of(model), "base", Props.clay(false), 0.0, true))
	# The buildings: both detail levels, the near and the far material.
	for model in BUILDING_MODELS:
		_mesh(Props.mesh_of(model), Props.building(false))
		_mesh(Props.mesh_of(model), Props.building(true))
	# The particle bursts: copies of the real emitters, particles too small to see.
	for b in bursts:
		var e: CPUParticles3D = b.duplicate()
		e.top_level = false
		e.position = Vector3.ZERO
		e.scale_amount_min = TINY
		e.scale_amount_max = TINY
		e.scale_amount_curve = null
		e.one_shot = false
		add_child(e)
		e.emitting = true


func _mesh(mesh: Mesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _process(_delta: float) -> void:
	_frames += 1
	if _frames >= FRAMES:
		queue_free()
