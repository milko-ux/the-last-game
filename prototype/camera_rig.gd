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
# THE LOW CAMERA (step 3 brief 2 section 5, Milko's pick on the phone
# 2026-10-21): 42 degrees down through a 44-degree lens from 1.25 x as
# far, so the field keeps its size while more sky shows and the mesas
# stand upright. Until then 54 degrees, FOV 55, 26 / 6.667 below.
const CAMERA_PITCH_DEG := 42.0
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
const CAMERA_DISTANCE_AT_2_2 := 32.5
const CAMERA_DISTANCE_PER_BAR := 8.333
static var CAMERA_DISTANCE := 32.5
const FOV := 44.0
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


# THE BACKDROP: a painting on an unlit quad that rides on the camera far
# behind everything (the cheapest thing that looks the same on the web
# renderer and native). Step 3 brief 2 section 1 (the canyon, 2026-10-21):
# painted in SCREEN space, like a film's backdrop -- the camera never
# turns during a run, it only travels, and what is infinitely far does
# not move when you travel. Top to bottom:
#
#   the sky      SKY_TOP to SKY_HORIZON, the sun's disc and halo
#   far mesas    two layers of flat-topped silhouettes on the horizon
#   the clouds   a sea of them below the horizon, in perspective (a
#                plane far below the runway), drifting toward the camera
#                as the run travels: the one part with depth
#
# All of it laid ON the fog's gradient (fog_colour, the same function
# every world material fades toward), so a far thing fades toward the
# haze behind it. The horizon sits high (the camera looks steeply down,
# so a true horizon would be above the frame; nobody can tell). The
# sun's place matches the world's light (pr_light_dir comes from the
# screen-left, behind the camera, so the sun is up on the left).
# Brief 2 section 4 / brief 6 section 3 were a four-stop grey gradient
# with two layers of drifting noise.
const Mats := preload("res://prototype/flat_mats.gd")
const BACKDROP_DISTANCE := 600.0
static var backdrop: ShaderMaterial = null     # the last one built (one scene at a time): time_of_day.gd paints it
const BACKDROP_SHADER := """
shader_type spatial;
render_mode unshaded, depth_draw_never, fog_disabled, cull_disabled;
uniform float horizon = 0.2;              // screen height of the horizon, 0 top .. 1 bottom
uniform vec2 sun_pos = vec2(0.16, 0.085); // the sun's centre on screen
uniform float sun_radius = 0.032;         // in screen heights
uniform vec3 sky_top : source_color;
uniform vec3 sky_horizon : source_color;
uniform vec3 sun : source_color;
uniform vec3 sun_glow : source_color;
uniform vec3 cliff_far : source_color;
uniform vec3 cliff_near : source_color;
uniform vec3 cloud_lit : source_color;
uniform vec3 cloud_shade : source_color;
uniform float cloud_depth = 5.0;          // the cloud plane: screen height below the horizon -> distance
uniform float cloud_scale = 0.22;         // noise cells per unit of that distance
uniform float cloud_drift = 0.045;        // of the run's travel: the clouds lie far below, they pass slowly
uniform float night = 0.0;                // the time of day (time_of_day.gd): 1 = stars out, the sun is the moon
global uniform float pr_window_back;
FOG_FUNCTIONS

// highp throughout: the drift reaches thousands of units in a long run,
// and the phone's fragment stage defaults to half floats.
float hash2(highp vec2 p) {
	p = fract(p * vec2(0.3183099, 0.3678794) + vec2(0.1, 0.7));
	p *= 23.0;
	return fract(p.x * p.y * (p.x + p.y));
}
float vnoise2(highp vec2 p) {
	highp vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1, 0)), f.x), mix(hash2(i + vec2(0, 1)), hash2(i + vec2(1, 1)), f.x), f.y);
}
float fbm(highp vec2 p) {
	return vnoise2(p) * 0.55 + vnoise2(p * 2.07 + 13.1) * 0.3 + vnoise2(p * 4.3 + 7.7) * 0.15;
}
// A mesa skyline: plateaus with steep sides, height 0..1 along x.
float mesas(float x, float seed) {
	float n = vnoise2(vec2(x, seed));
	float top = 0.55 + 0.45 * vnoise2(vec2(x * 0.37, seed + 5.0));
	return smoothstep(0.46, 0.49, n) * top;
}

void fragment() {
	vec2 s = SCREEN_UV;
	float aspect = VIEWPORT_SIZE.x / VIEWPORT_SIZE.y;
	vec3 haze = fog_colour(s.y);
	// The sky, the sun's halo and its disc.
	float t = clamp(s.y / horizon, 0.0, 1.0);
	vec3 c = mix(sky_top, sky_horizon, t * t);
	// Stars at night, twinkling, thinning toward the horizon.
	vec2 g = vec2(s.x * aspect, s.y) * 150.0;
	float sh = hash2(floor(g));
	float star = step(0.986, sh) * (1.0 - smoothstep(0.08, 0.3, length(fract(g) - 0.5)));
	c += vec3(star * (0.65 + 0.35 * sin(TIME * 2.3 + sh * 60.0)) * night * (1.0 - t * t));
	float r = length(vec2((s.x - sun_pos.x) * aspect, s.y - sun_pos.y));
	float halo = (exp(-r * 6.0) * 0.5 + exp(-r * 18.0) * 0.4) * (1.0 - 0.45 * night);
	c = mix(c, sun_glow, clamp(halo, 0.0, 1.0));
	float rad = sun_radius * (1.0 - 0.25 * night);   // the moon a little smaller
	c = mix(c, sun, 1.0 - smoothstep(rad * 0.85, rad, r));
	// Two layers of far mesas standing on the horizon, the far one paler.
	float x = s.x * aspect;
	float far_top = horizon - 0.012 - 0.05 * mesas(x * 5.0, 1.0);
	float near_top = horizon - 0.004 - 0.085 * mesas(x * 3.2 + 4.0, 9.0);
	if (s.y > far_top) {
		c = mix(cliff_far, haze, 0.25 + 0.5 * smoothstep(far_top, horizon, s.y));
	}
	if (s.y > near_top) {
		c = mix(cliff_near, haze, 0.15 + 0.6 * smoothstep(near_top, horizon + 0.01, s.y));
	}
	// The cloud sea: a plane far below, seen in perspective. Puffs: the
	// noise's height is the cloud's thickness, lit on the side toward the
	// sun, the gaps between them deep lilac (looking down into the drop).
	float d = s.y - horizon;
	if (d > 0.0) {
		highp float z = cloud_depth / (d + 0.05);
		highp vec2 p = vec2((s.x - 0.5) * aspect * z * 0.5, (z + pr_window_back * cloud_drift / cloud_scale) * 0.4) * cloud_scale;
		float n = fbm(p);
		float toward_sun = fbm(p + vec2(0.18, 0.1));
		float cover = smoothstep(0.42, 0.56, n);
		float lit = clamp((n - 0.42) * 3.0 + (n - toward_sun) * 7.0, 0.0, 1.0);
		vec3 cloud = mix(cloud_shade, cloud_lit, lit);
		vec3 gaps = cloud_shade * 0.8;
		vec3 sea = mix(gaps, cloud, cover);
		// Toward the horizon the clouds thin into haze.
		c = mix(sea, haze, 1.0 - smoothstep(0.0, 0.3, d));
	}
	// The sun's light in the air, over everything below it too.
	c = mix(c, sun_glow, clamp(exp(-r * 3.0) * 0.18 * (1.0 - 0.5 * night), 0.0, 1.0));
	ALBEDO = c;
}
"""


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
	var p := {"sky_top": WorldPalette.SKY_TOP, "sky_horizon": WorldPalette.SKY_HORIZON, "sun": WorldPalette.SUN,
		"sun_glow": WorldPalette.SUN_GLOW, "cliff_far": WorldPalette.CLIFF_FAR, "cliff_near": WorldPalette.CLIFF_NEAR,
		"cloud_lit": WorldPalette.CLOUD_LIT, "cloud_shade": WorldPalette.CLOUD_SHADE}
	for k in p:
		m.set_shader_parameter(k, p[k])
	quad.material_override = m
	backdrop = m
	quad.position = Vector3(0.0, 0.0, -BACKDROP_DISTANCE)
	quad.extra_cull_margin = 16384.0
	cam.add_child(quad)



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
