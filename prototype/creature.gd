extends Node3D
# ============================================================
# CREATURE — the player's visual (Phase A brief 1). Visual ONLY:
# position, jumping and the hit box stay in player3d.gd / rules.gd,
# so the bots and the fairness validator never notice it exists.
#
# The model (assets/models/creature.glb) has no skeleton, so every
# movement here is procedural: each frame ONE pose is computed in
# _process, in the brief's blending order
#   base -> breathing -> beat pulse -> lean / bob -> jump stretch /
#   spin -> look-at / alarm            (scales multiply, angles add)
# and written to this node's transform. The pivot is the feet, so
# squash, stretch and lean all happen about the floor contact.
#
# Every number Milko might tune is a constant below.
# ============================================================

# --- The model as it arrives from the GLB --------------------------------
# It comes in centred on its own middle, 1.874 units tall, eye toward +z
# (which happens to be down the field already, so the rest yaw is 0; if
# the GLB is ever re-exported facing elsewhere, this is the number).
const MODEL_REST_YAW_DEG := 0.0
const MODEL_HEIGHT := 1.874            # GLB bounds, y -0.938 .. 0.936
const MODEL_FEET_Y := -0.938
const MODEL_BODY_CENTRE_Z := 0.15      # the tail drags the bounds back; the body sits forward of 0
const HEIGHT := 3.0                    # 1.5 tiles, feet to top (the gray-box capsule was 1.6)

# --- 1. Idle breathing ----------------------------------------------------
const BREATH_AMOUNT := 0.02
const BREATH_HZ := 0.5
# --- 2. Beat pulse (every downbeat) ---------------------------------------
const PULSE_AMOUNT := 0.06
const PULSE_IN_S := 0.06
const PULSE_OUT_S := 0.18
# --- 3. Lean ----------------------------------------------------------------
const LEAN_DEG := 12.0
const LEAN_LERP := 0.2                 # per frame at 60 fps (made framerate-independent below)
# --- 4. Run bob -------------------------------------------------------------
const BOB_AMOUNT := 0.03               # of HEIGHT
const BOB_HZ := 4.0
# --- 5. Jump ----------------------------------------------------------------
const JUMP_STRETCH := 0.15
const JUMP_STRETCH_S := 0.10
const JUMP_STRETCH_RELEASE_S := 0.20
const SPIN_TURNS := 1.0                # one full turn per jump: Milko's requirement
# The camera looks down at 54 degrees, so a level spin shows mostly forehead.
# The body tips back by this much at the half-way point of the spin (when
# the eye faces the camera), which is what actually shows the eye.
const SPIN_TILT_DEG := 32.0
const LAND_SQUASH := 0.20
const LAND_IN_S := 0.08
const LAND_OUT_S := 0.20
# --- 6. Eye look-at (the baked eye is kept, so the whole body turns) ------
const LOOK_YAW_DEG := 35.0
const LOOK_PITCH_DEG := 15.0
const LOOK_LERP := 0.15
# --- 7. Alarm ---------------------------------------------------------------
const ALARM_RANGE := 3.0               # 1.5 tiles
const ALARM_SCALE := 1.05
const ALARM_LERP := 0.35
# --- 8. Death / respawn -----------------------------------------------------
const DEATH_SCALE := 1.3
const DEATH_POP_S := 0.08
const DEATH_LOOK_LERP := 0.45          # "snaps" to the camera
const RESPAWN_S := 0.15
const PARTICLES := 12
const CLAY := Color(0.62, 0.52, 0.66)
# --- 9. Goal ----------------------------------------------------------------
const GOAL_HOPS := 3
const GOAL_HOP_S := 0.32
const GOAL_HOP_HEIGHT := 1.1
const GOAL_HOLD_AT_APEX := true        # the last hop freezes at its top, facing the camera

# --- Material ---------------------------------------------------------------
# Lit (the one lit thing in the scene), never distance-faded, and drawn on
# top of the world. "On top" is done by squeezing the creature's depth
# toward the camera instead of switching the depth test off: the model is
# not convex, so without a depth test its own arms and tail would draw
# through its body.
# `skin` and `base_tint` are the swap points for later outfits.
const ON_TOP := 0.92
const AMBIENT := 0.38                  # the scene has no ambient light; this keeps the shadow side clay, not black
const SHADER := """
shader_type spatial;
render_mode cull_back, fog_disabled;
uniform sampler2D skin : source_color, filter_linear_mipmap;
uniform vec4 base_tint : source_color = vec4(1.0);
uniform float on_top = 0.92;
uniform float ambient = 0.38;

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = mix(POSITION.z, POSITION.w, on_top);
}

void fragment() {
	vec3 c = texture(skin, UV).rgb * base_tint.rgb;
	ALBEDO = c;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	EMISSION = c * ambient;
}
"""

enum Mode { ALIVE, DYING, GONE, RESPAWN, GOAL }

var mode := Mode.ALIVE
var spin_angle := 0.0
var spin_tilt := 0.0

var _player: Node3D                    # player3d.gd: move_dir, on_ground
var _model: Node3D
var _burst: CPUParticles3D
var _t := 0.0
var _pulse_t := 99.0
var _lean := Vector2.ZERO              # x: roll, y: pitch (radians)
var _bob_phase := 0.0
var _speed := 0.0
var _jump_t := -1.0                    # seconds since take-off, -1 = not in a jump
var _airtime := 0.67
var _land_t := 99.0
var _was_on_ground := true
var _look := Vector2.ZERO              # x: yaw, y: pitch (radians)
var _look_target: Variant = null
var _alarm := 1.0
var _mode_t := 0.0
var _death_s := 0.35


func _ready() -> void:
	_player = get_parent()
	_model = $Model
	var s := HEIGHT / MODEL_HEIGHT
	_model.transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(MODEL_REST_YAW_DEG)).scaled(Vector3.ONE * s),
		Vector3.ZERO)
	_model.position = _model.basis * Vector3(0.0, -MODEL_FEET_Y, -MODEL_BODY_CENTRE_Z)
	_apply_material(_model)
	_build_burst()
	BeatClock.downbeat.connect(func(_bar: int) -> void: _pulse_t = 0.0)


func _apply_material(n: Node) -> void:
	if n is MeshInstance3D:
		var mi: MeshInstance3D = n
		var src := mi.mesh.surface_get_material(0) as BaseMaterial3D
		var sh := Shader.new()
		sh.code = SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.render_priority = 10
		m.set_shader_parameter("skin", src.albedo_texture if src != null else null)
		m.set_shader_parameter("on_top", ON_TOP)
		m.set_shader_parameter("ambient", AMBIENT)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_apply_material(c)


# CPU particles: twelve of them, and GPU particles are the usual thing to
# misbehave in a web export.
func _build_burst() -> void:
	_burst = CPUParticles3D.new()
	_burst.emitting = false
	_burst.one_shot = true
	_burst.amount = PARTICLES
	_burst.lifetime = 0.45
	_burst.explosiveness = 1.0
	_burst.direction = Vector3.UP
	_burst.spread = 180.0
	_burst.initial_velocity_min = 5.0
	_burst.initial_velocity_max = 9.0
	_burst.gravity = Vector3(0.0, -18.0, 0.0)
	_burst.scale_amount_min = 0.6
	_burst.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	_burst.scale_amount_curve = curve
	var ball := SphereMesh.new()
	ball.radius = 0.22
	ball.height = 0.44
	ball.radial_segments = 8
	ball.rings = 4
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = CLAY
	mat.no_depth_test = true
	mat.render_priority = 11
	ball.material = mat
	_burst.mesh = ball
	_burst.top_level = true            # stays where the creature died, unscaled by the pose
	add_child(_burst)


# ------------------------------------------------------------
# Events from player3d.gd / track_test.gd
# ------------------------------------------------------------
func on_jump(airtime: float) -> void:
	_jump_t = 0.0
	_airtime = airtime
	_land_t = 99.0


func set_look_target(target: Variant) -> void:
	_look_target = target


func play_death(freeze_s: float) -> void:
	mode = Mode.DYING
	_mode_t = 0.0
	_death_s = maxf(freeze_s, DEATH_POP_S + 0.05)
	_jump_t = -1.0


func play_respawn() -> void:
	mode = Mode.RESPAWN
	_mode_t = 0.0
	_jump_t = -1.0
	_land_t = 99.0
	_look = Vector2.ZERO
	_lean = Vector2.ZERO
	_alarm = 1.0
	spin_angle = 0.0
	spin_tilt = 0.0
	_was_on_ground = true
	_model.visible = true


func play_goal() -> void:
	mode = Mode.GOAL
	_mode_t = 0.0
	_jump_t = -1.0


# ------------------------------------------------------------
# The pose
# ------------------------------------------------------------
func _process(delta: float) -> void:
	_t += delta
	_pulse_t += delta
	_land_t += delta
	_mode_t += delta
	var k60 := delta * 60.0

	var scale_y := 1.0
	var scale_xz := 1.0
	var uniform := 1.0
	var lift := 0.0

	# 1. breathing
	scale_y *= 1.0 + BREATH_AMOUNT * sin(TAU * BREATH_HZ * _t)

	# 2. beat pulse
	var p := _punch(_pulse_t, PULSE_IN_S, PULSE_OUT_S) * PULSE_AMOUNT
	scale_y *= 1.0 - p
	scale_xz *= 1.0 + p * 0.5

	# 3. lean, 4. bob
	var v := Vector2.ZERO
	if mode == Mode.ALIVE and _player != null:
		v = _player.move_dir.limit_length(1.0)
	_speed = v.length()
	var lean_to := Vector2(v.x, v.y) * deg_to_rad(LEAN_DEG)
	_lean = _lean.lerp(lean_to, _rate(LEAN_LERP, k60))
	if _speed > 0.01 and _on_ground():
		_bob_phase += delta * BOB_HZ * TAU
		lift += absf(sin(_bob_phase * 0.5)) * BOB_AMOUNT * HEIGHT * _speed
	else:
		_bob_phase = 0.0

	# 5. jump: stretch, the full turn, the landing squash
	if mode == Mode.ALIVE:
		var grounded := _on_ground()
		if _jump_t >= 0.0:
			_jump_t += delta
			var st := _punch(_jump_t, JUMP_STRETCH_S, JUMP_STRETCH_RELEASE_S) * JUMP_STRETCH
			scale_y *= 1.0 + st
			scale_xz *= 1.0 - st * 0.4
			var u := clampf(_jump_t / _airtime, 0.0, 1.0)
			spin_angle = TAU * SPIN_TURNS * _ease_in_out(u)
			spin_tilt = -deg_to_rad(SPIN_TILT_DEG) * pow(sin(PI * _ease_in_out(u)), 2.0)
		if grounded and not _was_on_ground:
			_land_t = 0.0
			_jump_t = -1.0
			spin_angle = 0.0
			spin_tilt = 0.0
		_was_on_ground = grounded
		var ls := _punch(_land_t, LAND_IN_S, LAND_OUT_S) * LAND_SQUASH
		scale_y *= 1.0 - ls
		scale_xz *= 1.0 + ls * 0.5

	# 6. look-at, 7. alarm
	var look_to := Vector2.ZERO
	var brace := false
	var look_rate := LOOK_LERP
	if mode == Mode.ALIVE and _look_target != null:
		var d: Vector3 = _look_target - global_position
		look_to.x = clampf(atan2(d.x, d.z), -deg_to_rad(LOOK_YAW_DEG), deg_to_rad(LOOK_YAW_DEG))
		look_to.y = clampf(-atan2(d.y - HEIGHT * 0.55, Vector2(d.x, d.z).length()),
			-deg_to_rad(LOOK_PITCH_DEG), deg_to_rad(LOOK_PITCH_DEG))
		brace = Vector2(d.x, d.z).length() <= ALARM_RANGE
	elif mode == Mode.DYING or mode == Mode.GOAL:
		look_to = _toward_camera()
		look_rate = DEATH_LOOK_LERP
	_look.x = lerp_angle(_look.x, look_to.x, _rate(look_rate, k60))
	_look.y = lerpf(_look.y, look_to.y, _rate(look_rate, k60))
	_alarm = lerpf(_alarm, ALARM_SCALE if brace else 1.0, _rate(ALARM_LERP, k60))
	uniform *= _alarm

	# 8. death / respawn, 9. goal
	match mode:
		Mode.DYING:
			var grow_s := _death_s - DEATH_POP_S
			if _mode_t < grow_s:
				uniform *= lerpf(1.0, DEATH_SCALE, _mode_t / grow_s)
			else:
				uniform *= DEATH_SCALE * maxf(0.0, 1.0 - (_mode_t - grow_s) / DEATH_POP_S)
				if not _burst.emitting and _model.visible:
					_burst.global_position = global_position + Vector3(0.0, HEIGHT * 0.5, 0.0)
					_burst.restart()
				if _mode_t >= _death_s:
					mode = Mode.GONE
					_model.visible = false
		Mode.GONE:
			uniform = 0.0
		Mode.RESPAWN:
			uniform *= _ease_in_out(clampf(_mode_t / RESPAWN_S, 0.0, 1.0))
			if _mode_t >= RESPAWN_S:
				mode = Mode.ALIVE
		Mode.GOAL:
			var hop := int(_mode_t / GOAL_HOP_S)
			var u := fmod(_mode_t, GOAL_HOP_S) / GOAL_HOP_S
			if hop >= GOAL_HOPS - 1 and GOAL_HOLD_AT_APEX:
				u = minf(_mode_t / GOAL_HOP_S - float(GOAL_HOPS - 1), 0.5)
			elif hop >= GOAL_HOPS:
				u = 0.0
			lift += 4.0 * u * (1.0 - u) * GOAL_HOP_HEIGHT
			var st := _punch(u * GOAL_HOP_S, JUMP_STRETCH_S, JUMP_STRETCH_RELEASE_S) * JUMP_STRETCH
			scale_y *= 1.0 + st
			scale_xz *= 1.0 - st * 0.4

	# Compose: world-frame lean, then the body's own yaw (spin + look), then
	# its own look pitch, then the scales. Feet stay the pivot.
	var b := Basis(Vector3.RIGHT, _lean.y) * Basis(Vector3.BACK, _lean.x)
	b = b * Basis(Vector3.UP, spin_angle + _look.x) * Basis(Vector3.RIGHT, _look.y + spin_tilt)
	b = b.scaled_local(Vector3(scale_xz, scale_y, scale_xz) * maxf(uniform, 0.001))
	transform = Transform3D(b, Vector3(0.0, lift, 0.0))


# (yaw, pitch) that turn the eye to the active camera.
func _toward_camera() -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2.ZERO
	var d := cam.global_position - (global_position + Vector3(0.0, HEIGHT * 0.55, 0.0))
	return Vector2(atan2(d.x, d.z), -atan2(d.y, Vector2(d.x, d.z).length()) * 0.6)


# How much the eye points at the camera right now, 1 = straight at it.
func facing_camera() -> float:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return 0.0
	var to_cam := cam.global_position - global_position
	to_cam.y = 0.0
	var fwd := global_transform.basis.z
	fwd.y = 0.0
	return fwd.normalized().dot(to_cam.normalized())


func _on_ground() -> bool:
	return _player == null or _player.on_ground


# 0 -> 1 over `attack`, then back to 0 over `release` with a small
# overshoot below zero (the "spring back").
static func _punch(t: float, attack: float, release: float) -> float:
	if t < 0.0 or t >= attack + release:
		return 0.0
	if t < attack:
		return t / attack
	var u := (t - attack) / release
	return cos(u * PI * 1.5) * (1.0 - u)


static func _ease_in_out(u: float) -> float:
	return u * u * (3.0 - 2.0 * u)


# A per-frame lerp factor quoted at 60 fps -> the same feel at any fps.
static func _rate(per_frame: float, k60: float) -> float:
	return 1.0 - pow(1.0 - per_frame, k60)
