extends Node3D
# ============================================================
# CAMERA RIG — follows the WINDOW, not the player. The camera ORBITS
# the window centre: it sits on a sphere around that point (yaw, pitch,
# distance) and looks straight at it, so the window centre is always
# the centre of the screen and the field's centre line runs through
# the middle of the frame. High, back and to one side, so the whole
# field width and about two bars ahead are in frame and the field
# is seen OBLIQUELY, as in docs/concept/field_monolith.png (addendum
# 4 section 1): the near edge runs diagonally across the lower part
# of the screen, not horizontally.
#
# z is time, so the rig never lags.
#
# DOWNBEAT PUNCH AND NOD: OFF since 2026-09-20 (PUNCH here, NOD_DEG in
# motion.gd). Both used to jump to full strength in ONE frame on every
# downbeat, which is the frame the walls move and the volleys fire:
# measured with tools/frame_probe.gd, the whole picture moved 18.7 px
# (at 1200 px wide; ~37 px on a phone) in a single frame on 22 of 22
# downbeats and on no other frame. That is the "screen jumps when the
# hazards move" report. To bring them back set PUNCH to 0.02 and
# NOD_DEG to 1.5: they now ease in over BEAT_ATTACK_S instead of
# stepping. The death kick is separate and fires only on a death.
# ============================================================

const Rules := preload("res://prototype/rules.gd")

# The reference angle (addendum 4 section 1). Yaw is measured from the
# field axis, positive = the camera sits to the viewer's RIGHT of the
# axis (world -x). Both constants are meant to be flipped for the
# morning playtest: CAMERA_YAW_DEG = 0.0 gives the old straight view.
const CAMERA_YAW_DEG := 24.0
const CAMERA_PITCH_DEG := 54.0
# Camera v2: wider and further back than v1 (26 / FOV 48, near-right
# corner off screen). 32 felt far on the phone; 28 from 2026-09-17, 26 with
# the shorter window from 2026-09-20. At 28 by
# projection at 2400x1080 the window's corners land at x 686-1608,
# y 238-1064 (the near-right corner is only just on screen): the field
# covers about 40 % of the screen width, which leaves room for the world background that gets added around it.
# What lies beyond the window dissolves into the background: see the
# distance fade in flat_mats.gd (depth fog does not work on web).
# The distance follows the level's window: 26 at 2.2 bars, 28 at 2.5 bars
# (2 units per 0.3 bar), so the same share of field is on screen.
const CAMERA_DISTANCE_AT_2_2 := 26.0
const CAMERA_DISTANCE_PER_BAR := 6.667
static var CAMERA_DISTANCE := 26.0
const FOV := 55.0
# false: joystick up = down the field regardless of the yaw (world-
# relative). true: joystick up = away from the camera.
const INPUT_CAMERA_RELATIVE := false

const PUNCH := 0.0            # was 0.02; see the header
const BEAT_ATTACK_S := 0.08   # the punch and the nod ease in over this, never a one-frame step
const SHAKE_S := 0.35
const SHAKE_AMOUNT := 0.15

var _punch_age := 99.0
var _shake_t := 0.0
var window_back := 0.0
# The window's depth in units: a knob of the lap / level being played,
# handed over by the run scene (configure()), never read from a global.
var _window_depth := Rules.WINDOW_BARS_DEFAULT * Rules.BAR_LENGTH
# Brief 3: the death kick (a directional, decaying shake plus an outward
# FOV punch) and the downbeat nod, read from the scene's Motion node.
var motion: Node = null
var _kick_t := 0.0
var _kick_s := 0.25
var _kick_amount := 0.0
var _kick_fov := 0.0
var _kick_dir := Vector3.ZERO

@onready var cam: Camera3D = $Camera3D


# Brief 2 section 4: the background is a vertical gradient drawn on an
# unlit quad that rides on the camera far behind everything (the cheapest
# thing that looks the same on the web renderer and native). Brief 6
# section 3: four stops (WorldPalette.BG_TOP / THIRD / MIDDLE / BOTTOM),
# painted by the SAME fog_colour() every world material fades toward, so
# a faded thing goes toward exactly what is behind it. Nothing else back
# there but the far silhouettes.
const Mats := preload("res://prototype/flat_mats.gd")
const BACKDROP_DISTANCE := 600.0
# Brief 2b section 5: the gradient carries two layers of slow noise (fog
# with weather in it) in a world-ish space that scrolls with the window.
const BACKDROP_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, fog_disabled, cull_disabled;
uniform vec2 quad_size;
uniform float big_scale = 40.0;
uniform float big_contrast = 0.06;
uniform float big_speed = 0.05;
uniform float small_scale = 12.0;
uniform float small_contrast = 0.03;
uniform float small_speed = 0.12;
global uniform float pr_window_back;
FOG_FUNCTIONS

float hash2(vec2 p) {
	p = fract(p * vec2(0.3183099, 0.3678794) + vec2(0.1, 0.7));
	p *= 23.0;
	return fract(p.x * p.y * (p.x + p.y));
}
float vnoise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	// UV -> a "world-ish" plane in units, scrolling at 20 % of the window.
	vec2 p = (UV - 0.5) * quad_size * 0.25 + vec2(0.0, pr_window_back * 0.2);
	float big = vnoise2(p / big_scale + vec2(TIME * big_speed / big_scale, 0.0)) * 2.0 - 1.0;
	float small = vnoise2(p / small_scale + vec2(0.0, TIME * small_speed / small_scale)) * 2.0 - 1.0;
	ALBEDO = fog_colour(UV.y) * (1.0 + big * big_contrast + small * small_contrast);
}
"""

# The far silhouettes: a little darker than the fog at their screen
# height, like the concept's furthest towers.
const FAR_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled;
uniform float tone = 0.93;
varying highp float fog_sy;
FOG_FUNCTIONS

void vertex() {
	fog_sy = screen_y_of(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	ALBEDO = fog_colour(fog_sy) * tone;
}
"""

# Huge faint monolith silhouettes far behind the field, on the rig with
# a 20 % parallax (they move at a fifth of the scroll), FAR_TONE of the
# fog behind them. Distance, size and tone are the knobs.
const FAR_SILHOUETTES := [
	[Vector3(-70.0, -30.0, 40.0), Vector3(22.0, 90.0, 18.0)],
	[Vector3(62.0, -35.0, 70.0), Vector3(30.0, 110.0, 24.0)],
	[Vector3(-40.0, -40.0, 110.0), Vector3(18.0, 75.0, 16.0)],
]
const FAR_TONE := 0.93
var _far: Node3D


func _ready() -> void:
	cam.fov = FOV
	_build_backdrop()
	BeatClock.downbeat.connect(_on_downbeat)
	set_window(0.0)


func _build_backdrop() -> void:
	var quad := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	# Big enough to cover the view at that distance for any aspect ratio.
	var h := 2.2 * BACKDROP_DISTANCE * tan(deg_to_rad(FOV * 0.6))
	mesh.size = Vector2(h * 3.0, h)
	quad.mesh = mesh
	var sh := Shader.new()
	sh.code = BACKDROP_SHADER.replace("FOG_FUNCTIONS", Mats.fog_functions())
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = -100
	m.set_shader_parameter("quad_size", mesh.size)
	quad.material_override = m
	quad.position = Vector3(0.0, 0.0, -BACKDROP_DISTANCE)
	quad.extra_cull_margin = 16384.0
	cam.add_child(quad)

	_far = Node3D.new()
	add_child(_far)
	var far_sh := Shader.new()
	far_sh.code = FAR_SHADER.replace("FOG_FUNCTIONS", Mats.fog_functions())
	var far_mat := ShaderMaterial.new()
	far_mat.shader = far_sh
	far_mat.set_shader_parameter("tone", FAR_TONE)
	for spec in FAR_SILHOUETTES:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = spec[1]
		mi.mesh = bm
		mi.material_override = far_mat
		mi.position = spec[0] + Vector3(0.0, spec[1].y * 0.5, 0.0)
		_far.add_child(mi)


# Called by the run scene with the knobs of what is being played: the
# camera distance follows the window (26 at 2.2 bars, 28 at 2.5).
func configure(k: Dictionary) -> void:
	set_window_depth(Rules.window_depth(k))


# The window's depth in units, any value: the endless run eases it between
# two laps whose bands differ (2.5 -> 2.2 bars, distance 28 -> 26) over the
# new lap's first two bars, so neither the window nor the camera snaps.
func set_window_depth(depth: float) -> void:
	_window_depth = depth
	CAMERA_DISTANCE = CAMERA_DISTANCE_AT_2_2 + (depth / Rules.BAR_LENGTH - 2.2) * CAMERA_DISTANCE_PER_BAR
	set_window(window_back)


func _on_downbeat(_bar: int) -> void:
	_punch_age = 0.0


# 0 -> 1 over BEAT_ATTACK_S, then back to 0 by `decay_s`: a beat accent
# that moves the picture instead of teleporting it.
static func beat_envelope(age: float, decay_s: float) -> float:
	if age >= decay_s:
		return 0.0
	return smoothstep(0.0, BEAT_ATTACK_S, age) * (1.0 - age / decay_s)


func shake() -> void:
	_shake_t = SHAKE_S


# Death kick: `away` is the direction from the killer to the player on
# the ground plane; the shake is biased that way.
func kick(duration: float, amount: float, fov_punch: float, away: Vector3) -> void:
	_kick_t = duration
	_kick_s = duration
	_kick_amount = amount
	_kick_fov = fov_punch
	_kick_dir = away


# Brief 6 section 1: the scene's one light is the light of the world.
# Its direction (toward the light, a DirectionalLight3D's +z) is the
# global shader uniform every world shader reads (flat_mats.gd,
# lit_tone). Published once, by the scene that owns the light: it does
# not move. The run and the menu each own a copy of the same light, and
# both publish it through here, so the two scenes agree. Lives with the
# rig because the rig already publishes the view's other global
# (pr_window_back, below).
static var light_dir := Vector3(0.36, 0.8, -0.48)   # toward the light; what was last published

static func publish_light(light: Node3D) -> void:
	light_dir = light.global_transform.basis.z.normalized()
	RenderingServer.global_shader_parameter_set("pr_light_dir", light_dir)


func set_window(z_back: float) -> void:
	window_back = z_back
	position = Vector3(0.0, 0.0, z_back + _window_depth * 0.5)
	if _far != null:
		_far.position.z = -0.8 * z_back   # so the silhouettes advance at 20 % of the scroll
	# The distance fade in flat_mats.gd is measured from the window.
	RenderingServer.global_shader_parameter_set("pr_window_back", z_back)


# The camera's offset from the look-at point for the reference angle.
static func camera_offset() -> Vector3:
	var yaw := deg_to_rad(CAMERA_YAW_DEG)
	var pitch := deg_to_rad(CAMERA_PITCH_DEG)
	var flat := CAMERA_DISTANCE * cos(pitch)
	return Vector3(-flat * sin(yaw), CAMERA_DISTANCE * sin(pitch), -flat * cos(yaw))


# (screen-right, forward) as the joystick gives it -> the same pair in
# the world frame the player uses (screen-right = world -x when the
# camera looks straight down +z). Only used when INPUT_CAMERA_RELATIVE.
static func screen_to_world_dir(v: Vector2) -> Vector2:
	var yaw := deg_to_rad(CAMERA_YAW_DEG)
	# Camera forward on the ground plane, and its right-hand vector.
	var f := Vector2(sin(yaw), cos(yaw))          # (x, z)
	var r := Vector2(-f.y, f.x)                   # screen-right in world (x, z)
	var w := r * v.x + f * v.y                    # world (x, z)
	return Vector2(-w.x, w.y)                     # player: x = screen-right * -1, y = +z


func _process(delta: float) -> void:
	_punch_age += delta
	var punch := beat_envelope(_punch_age, BeatClock.beat_interval)
	var kick_u := 0.0
	if _kick_t > 0.0:
		_kick_t -= delta
		kick_u = maxf(_kick_t, 0.0) / _kick_s
	cam.fov = FOV * (1.0 + PUNCH * punch + _kick_fov * kick_u)

	var off := Vector3.ZERO
	if _shake_t > 0.0:
		_shake_t -= delta
		var s := SHAKE_AMOUNT * (_shake_t / SHAKE_S)
		off = Vector3(randf_range(-s, s), randf_range(-s, s), 0.0)
	if kick_u > 0.0:
		var k := _kick_amount * kick_u
		off += _kick_dir * k * 0.6 + Vector3(randf_range(-k, k), randf_range(-k, k) * 0.5, randf_range(-k, k)) * 0.6
	cam.position = camera_offset() + off
	cam.look_at(global_position, Vector3.UP)
	if motion != null:
		# The nod: a forward tilt on the downbeat, decaying over the bar.
		cam.rotate_object_local(Vector3.RIGHT, -motion.nod())
