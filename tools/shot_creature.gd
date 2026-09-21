extends SceneTree
# ============================================================
# BODY SHOTS for Phase A brief 5 section 1 — the creature's body alone,
# with the game's own creature shader, from the front, the side and
# below, so the melt of the baked leg stubs can be judged.
#
#   godot --path . --resolution 900x900 --rendering-method gl_compatibility \
#         -s tools/shot_creature.gd -- out=docs/screenshots/m-body melt=1
#
# melt=0 renders the same three views with the melt off (the A/B).
# ============================================================

const Creature := preload("res://prototype/creature.gd")

var out := "docs/screenshots/m-body"
var melt := 1.0
var _shots := 0
var _wait := 0
var _cam: Camera3D
var _views := []


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() == 2 and kv[0] == "out":
			out = kv[1]
		elif kv.size() == 2 and kv[0] == "melt":
			melt = float(kv[1])
	var root := get_root()
	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.07, 0.07, 0.09)
	env.environment = e
	world.add_child(env)

	# Two lights: a key from the camera's upper left and a weak fill from
	# below, so the underside is readable in the "below" shot.
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35.0, -35.0, 0.0)
	key.light_energy = 1.6
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(55.0, 150.0, 0.0)
	fill.light_energy = 0.7
	world.add_child(fill)

	var model: Node3D = load("res://assets/models/creature.glb").instantiate()
	world.add_child(model)
	_apply(model)

	_cam = Camera3D.new()
	_cam.fov = 40.0
	world.add_child(_cam)

	# name, position, look-from-up
	var d := 3.6
	_views = [
		["front", Vector3(0.0, 0.0, d), Vector3.UP],
		["side", Vector3(d, 0.0, 0.0), Vector3.UP],
		["below", Vector3(0.0, -d, 0.01), Vector3.BACK],
	]
	_place(0)


func _apply(n: Node) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
		var sh := Shader.new()
		sh.code = Creature.SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("skin", src.albedo_texture if src != null else null)
		m.set_shader_parameter("on_top", 0.0)          # a normal depth test here
		m.set_shader_parameter("ambient", Creature.AMBIENT)
		m.set_shader_parameter("melt", melt)
		m.set_shader_parameter("melt_xz", Creature.MELT_XZ)
		m.set_shader_parameter("melt_edge", Creature.MELT_EDGE)
		m.set_shader_parameter("melt_cap_y", Creature.MELT_CAP_Y)
		m.set_shader_parameter("melt_cap_ry", Creature.MELT_CAP_RY)
		m.set_shader_parameter("melt_cap_rxz", Creature.MELT_CAP_RXZ)
		mi.material_override = m
	for c in n.get_children():
		_apply(c)


func _place(i: int) -> void:
	_cam.position = _views[i][1]
	_cam.look_at(Vector3.ZERO, _views[i][2])
	_wait = 0


func _process(_d: float) -> bool:
	_wait += 1
	if _wait < 6:
		return false
	var img := get_root().get_viewport().get_texture().get_image()
	var path := "%s-%s.png" % [out, _views[_shots][0]]
	print("SHOT %s err=%d melt=%.0f" % [path, img.save_png(path), melt])
	_shots += 1
	if _shots >= _views.size():
		return true
	_place(_shots)
	return false
