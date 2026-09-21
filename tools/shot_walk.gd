extends SceneTree
# ============================================================
# WALK RIG for Phase A brief 5 — the creature on a bare floor with a
# stand-in player that moves it at a chosen speed, so the step cycle can
# be looked at and MEASURED without a level, hazards, deaths or loading
# in the way. The creature is visual-only, so this rig exercises all of
# it; what it cannot show is the game camera, which tools/shot.gd does.
#
#   godot --path . --resolution 900x900 --rendering-method gl_compatibility \
#         -s tools/shot_walk.gd -- out=/tmp/w frames=8 dir=forward
#
#   dir=forward | strafe | turn | still | stopping   what the rig does
#   frames=8      stills across ONE stride, sampled by PHASE not by time
#   slide=1       measure each foot's world drift while planted; no shots
#   jump=1        leave the floor and shoot the tuck
#   cam=side | front | back
# ============================================================

var out := "/tmp/walk"
var frames := 8
var dir := "forward"
var cam_kind := "side"
var slide := false
var jump := false
var speed := 1.0
var at := -1.0                     # at=SEC: one shot at that moment instead

var _rig: Node3D = null            # the stand-in player
var _creature: Node3D = null
var _cam: Camera3D = null
var _t := 0.0
var _taken := 0
var _next_phase := 0.0
var _warm := 1.0                   # a second of walking before anything is read

var _plant := [Vector3.ZERO, Vector3.ZERO]
var _planted := [false, false]
var _max_drift := 0.0
var _stances := 0
var _max_hip := 0.0             # the leash number: worst foot-to-hip distance
var _max_hip_planted := 0.0
var _jumps := 0
var _vy := 0.0


# What creature.gd reads off its parent: move_dir, y, on_ground.
class RigPlayer extends Node3D:
	var move_dir := Vector2.ZERO
	var y := 0.0
	var on_ground := true
	var creature: Node3D = null


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"out": out = kv[1]
			"frames": frames = int(kv[1])
			"dir": dir = kv[1]
			"cam": cam_kind = kv[1]
			"slide": slide = kv[1] == "1"
			"jump": jump = kv[1] == "1"
			"speed": speed = float(kv[1])
			"at": at = float(kv[1])
	var root := get_root()
	var world := Node3D.new()
	root.add_child(world)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.06, 0.08, 0.10)
	env.environment = e
	world.add_child(env)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-42.0, -38.0, 0.0)
	key.light_energy = 1.7
	world.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(20.0, 150.0, 0.0)
	fill.light_energy = 0.5
	world.add_child(fill)

	# A floor, so a planted foot can be seen to be planted.
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(200.0, 200.0)
	floor_mi.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.10, 0.16, 0.18)
	floor_mi.material_override = fm
	world.add_child(floor_mi)

	_rig = RigPlayer.new()
	world.add_child(_rig)
	_creature = load("res://prototype/creature.tscn").instantiate()
	_rig.add_child(_creature)
	_rig.creature = _creature

	_cam = Camera3D.new()
	_cam.fov = 26.0
	world.add_child(_cam)
	_cam.make_current()


func _process(delta: float) -> bool:
	_t += delta
	_drive(delta)
	_aim()
	if _t < _warm:
		_creature.reset_reach_seen()
		return false
	if slide:
		return _measure()
	if at > 0.0:
		if _t < at:
			return false
		return _shoot("%s.png" % out)
	if jump:
		if _t > _warm + 1.15:
			return _shoot("%s-%02d.png" % [out, _taken + 1])
		return false
	# Sample by PHASE, so the sheet really is one stride end to end.
	var ph: float = _creature.stride_phase()
	if _taken == 0 and _next_phase == 0.0:
		_next_phase = ph
	if _phase_reached(ph):
		_next_phase = fposmod(_next_phase + 1.0 / float(frames), 1.0)
		if _shoot("%s-%02d.png" % [out, _taken + 1]):
			return true
	return false


func _phase_reached(ph: float) -> bool:
	return fposmod(ph - _next_phase, 1.0) < 0.5 / float(frames)


func _shoot(path: String) -> bool:
	var img := get_root().get_viewport().get_texture().get_image()
	img.save_png(path)
	_taken += 1
	print("WALK %s  t=%.2f  phase=%.3f  down=%s,%s" % [path, _t,
		_creature.stride_phase(), _creature.foot_planted(0), _creature.foot_planted(1)])
	return _taken >= frames


# The stand-in player moves over the floor exactly as player3d does, at
# the ground speed measured in the real game at full input.
const GROUND_SPEED := 3.9


func _drive(delta: float) -> void:
	var d := Vector2.ZERO
	match dir:
		"still":
			d = Vector2.ZERO
		"strafe":
			d = Vector2(1.0, 0.0)
		"turn":
			d = Vector2(sin(_t * TAU / 2.5), cos(_t * TAU / 2.5))
		"stopping":
			d = Vector2(0.0, 1.0) if _t < _warm + 1.2 else Vector2.ZERO
		_:
			d = Vector2(0.0, 1.0)
	d *= speed
	_rig.move_dir = d
	# player3d: move_dir.x is screen-right, and world +x is screen-left.
	_rig.position.x += -d.x * GROUND_SPEED * delta
	_rig.position.z += d.y * GROUND_SPEED * delta
	if jump and _t > _warm + 1.0 and _rig.on_ground:
		_vy = 6.5
		_rig.on_ground = false
		_jumps += 1
		_creature.on_jump(1.3)
	if not _rig.on_ground:
		_vy -= 18.0 * delta
		_rig.y += _vy * delta
		if _rig.y <= 0.0:
			_rig.y = 0.0
			_rig.on_ground = true
	_rig.position.y = _rig.y


func _aim() -> void:
	var p: Vector3 = _rig.global_position
	if cam_kind == "game":
		# The game's own camera angle and lens (camera_rig.gd), at the
		# distance the player is really seen from, so "does it read at
		# phone size" can be answered without the live scene.
		_cam.fov = 55.0
		var yaw := deg_to_rad(24.0)
		var pitch := deg_to_rad(54.0)
		var dist := 26.0
		var dir3 := Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
		_cam.global_position = Vector3(p.x, 0.0, p.z) + dir3 * dist
		_cam.look_at(Vector3(p.x, 1.0, p.z), Vector3.UP)
		return
	var off := Vector3(8.5, 1.3, 0.0)
	if cam_kind == "front":
		off = Vector3(0.0, 1.3, 8.5)
	elif cam_kind == "back":
		off = Vector3(0.0, 1.3, -8.5)
	_cam.global_position = Vector3(p.x, 0.0, p.z) + off
	_cam.look_at(Vector3(p.x, 0.95, p.z), Vector3.UP)


# The brief's no-slide number: while a foot is planted its world position
# must not change at all. Report the largest change seen.
func _measure() -> bool:
	for i in 2:
		var down: bool = _creature.foot_planted(i)
		var pos: Vector3 = _creature.foot_pos(i)
		# The leash, checked EVERY frame -- the number the zero-drift test
		# was missing: a foot can be perfectly still and still be half a
		# body behind where the leg could reach.
		var to_hip: float = (pos - _creature.hip_pos(i)).length()
		_max_hip = maxf(_max_hip, to_hip)
		if down:
			_max_hip_planted = maxf(_max_hip_planted, to_hip)
		if down and not _planted[i]:
			_plant[i] = pos
			_stances += 1
		elif down:
			_max_drift = maxf(_max_drift, (pos - _plant[i]).length())
		_planted[i] = down
	if _t > _warm + 8.0:
		var reach: float = _creature.reach()
		print("SLIDE dir=%s%s speed=%.2f stances=%d jumps=%d" % [
			dir, " +jump" if jump else "", speed, _stances, _jumps])
		print("  MAX FOOT DRIFT DURING STANCE   = %.6f units" % _max_drift)
		var drawn: float = _creature.max_reach_seen()
		print("  MAX FOOT-TO-HIP AS DRAWN       = %.4f units   reach %.4f   %s" % [
			drawn, reach, "OK" if drawn <= reach + 0.0005 else "OVER THE LEASH"])
		print("  ... of which PLANTED           = %.4f units" % _creature.max_reach_planted())
		return true
	return false
