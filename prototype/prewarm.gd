extends Node3D
# ============================================================
# PREWARM — draws every material the level can show ONCE before the
# run, so none of them is drawn for the first time in the middle of it.
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
# emitters.
#
# NEVER BLOCKS (2026-09-20, after the phone froze on it): the rack is
# filled ONE ITEM PER FRAME. The run scene keeps the world hidden and
# shows a progress bar while it calls step() each frame, then reveals
# the world piece by piece (each piece: one more frame), so no single
# frame carries more than one new shader and the screen stays alive.
# ============================================================

const Mats := preload("res://prototype/flat_mats.gd")
const Props := preload("res://prototype/props/props.gd")

const TINY := 0.001
const HAZARD_MODELS := ["gate_pillar", "sweeper_segment", "slammer", "orbiter_pillar", "volley_emitter"]
const BUILDING_MODELS := ["building_tall", "building_stacked", "building_tall_hi", "building_stacked_hi"]

var _queue: Array[Callable] = []
var _total := 0


# Lists the work; nothing is created or drawn yet.
func prepare(bursts: Array) -> void:
	scale = Vector3.ONE * TINY
	var white := Mats.white_flat()
	var half := Vector3.ONE
	var box := BoxMesh.new()
	for m in [Mats.tile(0, half), Mats.tile(1, half), Mats.tile(2, half), Mats.cyan(),
			Mats.flat(WorldPalette.SAFE.darkened(0.55)), Mats.amber_dim(), Mats.magenta(), Mats.magenta_dim(),
			Mats.magenta_wall(), Mats.magenta_wall_dim(), Mats.amber(), Mats.player(WorldPalette.GOAL), white]:
		_queue.append(_mesh.bind(box, m))
	var ball := SphereMesh.new()
	for m in [Mats.orb(true), Mats.orb(false), Mats.note(), Mats.shield(), white]:
		_queue.append(_mesh.bind(ball, m))
	# The clay props: armed, live, safe, and the white flash, on each model
	# (and mirrored, as the right-hand gate pillars and sweeper segments are).
	for model in HAZARD_MODELS:
		for m in [Props.clay(false), Props.clay(true), Props.clay_safe(), white]:
			_queue.append(_prop.bind(model, m, false))
		_queue.append(_prop.bind(model, Props.clay(false), true))
	# The buildings: both detail levels, the near and the far material.
	for model in BUILDING_MODELS:
		_queue.append(_building.bind(model, false))
		_queue.append(_building.bind(model, true))
	warm_bursts(bursts)


# The particle bursts on their own: copies of the real emitters, with the
# particles too small to see. The main menu (prototype/menu.gd) wants
# only this part — the creature hops there, and the landing's dust puff
# is a material like any other, so it has to be drawn once before the
# first hop lands on it. The menu has no use for the rest of the rack.
func warm_bursts(bursts: Array) -> void:
	scale = Vector3.ONE * TINY
	for b in bursts:
		_queue.append(_burst.bind(b))
	_total = _queue.size()


# Adds the next item to the rack (it is drawn this frame). Returns the
# progress 0..1; 1.0 = everything is on the rack.
func step() -> float:
	if not _queue.is_empty():
		_queue.pop_front().call()
	return 1.0 - float(_queue.size()) / float(maxi(_total, 1))


func item_count() -> int:
	return _total


func _mesh(mesh: Mesh, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _prop(model: String, mat: Material, mirror: bool) -> void:
	add_child(Props.make(model, Props.size_of(model), "base", mat, 0.0, mirror))


func _building(model: String, far: bool) -> void:
	_mesh(Props.mesh_of(model), Props.building(far))


func _burst(source: CPUParticles3D) -> void:
	var e: CPUParticles3D = source.duplicate()
	e.top_level = false
	e.position = Vector3.ZERO
	e.scale_amount_min = TINY
	e.scale_amount_max = TINY
	e.scale_amount_curve = null
	e.one_shot = false
	add_child(e)
	e.emitting = true
