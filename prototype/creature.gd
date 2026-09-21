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

# --- Brief 5 section 1: the melt --------------------------------------
# The GLB has two leg stubs fused to the underside; real legs under them
# would read as four. They are melted in the VERTEX SHADER, not in the
# model: the GLB is untouched.
#
# The brief asked for a body ellipsoid with everything below the equator
# and outside it projected back on. That cannot work on THIS model, and
# the measurements say why: excluding the stubs, the body has NO surface
# at all below y -0.547 inside a horizontal radius of 0.6. The belly IS
# the stubs. Any ellipsoid big enough to cover them either sits above the
# body's real underside (and eats it -- tried it, it shredded the
# flippers) or passes below the stubs and barely shortens them.
#
# So instead of projecting onto the body, a CAP is closed over the stubs:
# a dome that meets the body's real underside exactly where the stubs
# end, so there is no seam to tear, and domes gently down from there.
# It is solved from three measurements, not chosen:
#   the stubs live inside horizontal radius 0.62 of (x 0.0, z 0.065)
#   the body's real underside at that radius is y -0.517
#   the new belly bottoms out at y -0.620 (the stubs reached -0.938)
# -> cap ellipsoid centre y -0.340, y radius 0.280, horizontal radius 0.80.
# A vertex inside that radius and below the cap is lifted onto it.
#
# Checked against all 26 769 vertices: 2 510 are lifted (median 0.150,
# max 0.373 units) and every one of them is inside the stub box -- not
# one body or flipper vertex moves, which is what keeps it seamless.
#
# Note for anyone re-reading the brief: this model has SIX limbs (two
# front flippers, two rear flippers, two leg stubs) and the flippers hang
# BELOW the body's equator (y -0.475..-0.031, equator y 0.027), so the
# brief's "the arms sit above the equator" does not hold here either.
# The cap never reaches them: they are all outside radius 0.62.
const MELT_XZ := Vector2(0.0, 0.065)   # the belly axis
const MELT_EDGE := 0.62                # where the cap meets the real body
const MELT_CAP_Y := -0.4174            # cap ellipsoid centre y
const MELT_CAP_RY := 0.1576
const MELT_CAP_RXZ := 0.800
const MELT_ON := true
const HEIGHT := 2.3                    # 1.15 tiles, feet to top (3.0 was too big on the phone, 2026-09-19; the gray-box capsule was 1.6)

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
# (The timed bob that used to live here, BOB_AMOUNT / BOB_HZ, is gone:
# brief 5 section 3 replaced it with a bob that comes from the feet.)
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
# --- Brief 5 section 2: the legs ---------------------------------------
# Two stubby clay legs, separate from the body. A leg is a LINE between
# two points: its foot (on the floor, in world space) and its hip (a
# fixed point on the body's underside, so it travels with every lean,
# bob and spin the body does). Each frame the capsule is put at the foot,
# aimed at the hip and stretched to reach it. The top of the leg is
# inside the body, so the joint is never visible and a leg can never come
# off. No skeleton, no animation data, two draw calls.
# The brief's starting sizes were 0.34 x 0.44 x 0.42 with the hip at the
# belly. Measured against the real gait they do not close: at full speed
# the foot ends up 0.44 from its hip (logged), so a 0.42 leg from a hip
# 0.44 up has to span 0.68 -- 1.6 rest lengths -- and the capsule visibly
# comes off the body. The leg is 0.52 and the hip 0.52 instead, which
# reaches the floor at rest and spans that gait at 1.31. Still stubby:
# 23 % of the creature's height.
const LEG_W := 0.50                    # at HEIGHT 2.3
const LEG_D := 0.56
const LEG_H := 0.62                    # rest length, floor to hip
const HIP_WIDTH := 0.60                # centre to centre
# The belly after the section-1 melt bottoms out at model y -0.620, which
# is 0.39 above the feet at this scale; the hip sits just inside it.
const HIP_Y := 0.62
const HIP_Z := -0.10                   # the belly axis, in the player's frame
const LEG_STRETCH_MIN := 0.8
# 1.8, not 1.45, and the reason is the BOB. The hip rides on the body, so
# a bob of BODY_BOB * HEIGHT = 0.20 units is 0.20 of leg spent on height
# before the foot can reach forward at all -- and brief 5B makes the bob
# bigger on purpose. At 1.45 the leg ran out mid-stance, the leash pulled
# the foot in, and the cycle restarted: 15 footfalls a second of thrash.
# Worst case now is a hip 0.82 up with the foot a quarter-stride (0.475)
# out = 0.94, against a reach of 1.12.
const LEG_STRETCH_MAX := 1.8
# Brief 5B (2026-09-21): from the GAME camera the legs did not read at
# all -- what you saw were the flippers. Nothing about them was wrong,
# they were just small, pale and tucked under the widest part of a body
# seen from above. So: thicker (0.34 -> 0.50 wide), set wider apart
# (HIP_WIDTH 0.46 -> 0.60) so they clear the body's silhouette instead of
# hiding under it, and darker -- the body texture's median is
# (0.651, 0.576, 0.651) and the legs are now 22 % below it, not 8 %.
#
# "Longer" is not free: the visible part of a leg is the gap between the
# belly and the floor, so the only way to lengthen it is to raise the
# belly. The section-1 cap was raised from -0.620 to -0.575 (0.390 ->
# 0.445 above the floor, 14 % more leg). Re-checked against all 26 769
# vertices: 2 556 lifted, every one still inside the stub box, so the
# melt is as clean as Milko accepted it.
const LEG_TINT := Color(0.508, 0.449, 0.508)

# --- Brief 5 section 3: the step cycle ---------------------------------
# The cycle is driven by DISTANCE TRAVELLED, never by a timer. A planted
# foot does not move at all while it is planted, so the creature cannot
# slide; and standing still cannot run the cycle, because standing still
# covers no distance. (It also means a hit-stop needs no special case:
# a frozen world moves the player nowhere, so the legs hold by
# themselves.)
# The stride comes from how fast the creature is REALLY travelling, not
# from how far the stick is pushed. Sizing it off the input was the cause
# of the feet being at full stretch all the time in the real game: the
# carry line and the level's player_speed knob move the player faster
# than a constant walk, the cycle could not keep up at a fixed stride,
# and every foot ended up on the leash. Cadence is what gives instead --
# a small creature moving faster takes quicker steps, not impossibly long
# ones -- and the stride is capped at what the leg can actually cover.
const CADENCE_HZ := 2.8                # cycles a second = 5.6 footfalls
const STRIDE_MIN := 0.6                # units per step at a crawl
# The longest stride the leg can cover with room for the leash to work:
# the foot sits a quarter of a stride either side of a hip 0.62 up, so at
# 1.9 that is sqrt(0.475^2 + 0.62^2) = 0.78 against a reach of 0.90.
const STRIDE_MAX := 1.9
const GSPEED_TAU := 0.18               # smoothing on the measured speed
const STEP_HEIGHT := 0.28              # arc at mid-swing
const FOOT_PITCH_DEG := 20.0           # heel off first, toe down last
const IDLE_SPEED := 0.3                # of full speed
const IDLE_SETTLE_S := 0.15
const FOOT_HOME_TOL := 0.35            # further than this and it steps home
const BODY_BOB := 0.085                # of HEIGHT, lowest at each footfall
const BODY_ROLL_DEG := 4.0             # toward the stance leg
const FOOT_SQUASH := 0.065             # on each footfall, multiplied with the beat
const TURN_CUT_DEG := 90.0             # a sharper turn than this plants early
const SETTLE_STEP_S := 0.18            # the one corrective step home, see _settle_feet
const RECOVER_STEP_S := 0.09           # the leash's step: a flick, not a stride
# THE LEASH (2026-09-21, after Milko's phone test). "Zero drift during
# stance" was true and measured the wrong thing: nothing said how far a
# planted foot was allowed to be from its hip, so at speed and after a
# jump a foot could sit most of a body length behind the creature,
# visibly off the body, and catch up late. The invariant now is the one
# that matters and it is checked every frame:
#
#     distance(foot, hip) <= LEG_H * LEG_STRETCH_MAX, always
#
# A planted foot that reaches LEASH_STEP of that takes its next step NOW
# instead of waiting for its turn in the cycle; if it somehow still ends
# up outside, it is pulled in on the spot rather than left hanging.
const REACH := LEG_H * LEG_STRETCH_MAX
# Of REACH, the point at which a planted foot must step NOW. It has to
# sit ABOVE the normal gait or it fires inside it: a foot plants a
# quarter of a stride ahead (0.35) of a hip 0.52 up, which is already
# 0.63 from the hip, and the same at lift-off. At 0.82 (= 0.62) every
# single plant re-triggered a step and the stance count tripled. 0.92
# (= 0.69) leaves the walk alone and still catches a real stranding well
# before the leg runs out at 0.754.
const LEASH_STEP := 0.92
# A move bigger than this in ONE frame is not a stride, it is the player
# being put somewhere: a rewind, a checkpoint, the carry line catching
# up. 2.0 was far too generous -- the creature really travels 5.9 units a
# second, which is 0.10 a frame at 60 and 0.20 at 30, so a yank of a
# whole unit sailed under it and was walked off as if it were a step,
# leaving the foot a unit behind. That is what Milko saw. 0.5 is still
# four times any honest frame.
const TELEPORT_UNITS := 0.5
const JUMP_TUCK := 0.25                # of LEG_H, how far the feet tuck up
const JUMP_TUCK_LERP := 0.25
const LAND_SPLAY := 0.15               # feet splay outward during the squash

const GOAL_HOPS := 3
const GOAL_HOP_S := 0.32
const GOAL_HOP_HEIGHT := 1.1
const GOAL_HOLD_AT_APEX := true        # the last hop freezes at its top, facing the camera

# --- Shadow blob ------------------------------------------------------------
# A soft dark shadow on the floor under the creature, the size of the hit
# box's footprint (Rules.PLAYER_HALF_W, which since 2026-09-19 is the
# body's own footprint). Never fades, stays on the floor during a jump,
# drawn with a normal depth test (RING_ON_TOP 0 = off: it sits just above
# the floor and under the body). Set RING_ON_TOP to 0.95 to draw it over
# everything again.
const RING_ON_TOP := 0.0
const RING_ALPHA := 0.6
const RING_SOFTNESS := 0.45            # fraction of the radius over which it fades out
const RING_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;
uniform vec4 fill : source_color = vec4(0.0, 0.0, 0.0, 0.6);
uniform float softness = 0.45;
uniform float on_top = 0.0;

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = mix(POSITION.z, POSITION.w, on_top);
}

void fragment() {
	float r = length(UV - 0.5) * 2.0;
	float a = 1.0 - smoothstep(1.0 - softness, 1.0, r);
	ALBEDO = fill.rgb;
	ALPHA = fill.a * a * a;
}
"""

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
uniform float clay_grain = 0.04;     // brief 2b section 6: the same fine grain the world got
uniform float specular = 0.4;
// Brief 5 section 1: melt the baked leg stubs into the underside, so the
// real legs are not a second pair. Any vertex BELOW the body's equator
// and OUTSIDE the fitted body ellipsoid is pushed back onto that
// ellipsoid's surface. The GLB is untouched; this is the vertex stage.
// The arms and the tail hang below the equator too and are kept out of
// it by their own ranges (see MELT_* in the script for the measurements).
uniform float melt = 1.0;            // 0 = off, for an A/B
uniform vec2 melt_xz = vec2(0.0, 0.065);
uniform float melt_edge = 0.62;
uniform float melt_cap_y = -0.340;
uniform float melt_cap_ry = 0.280;
uniform float melt_cap_rxz = 0.800;
varying vec3 model_pos;

float chash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float cnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(chash(i), chash(i + vec3(1, 0, 0)), f.x), mix(chash(i + vec3(0, 1, 0)), chash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(chash(i + vec3(0, 0, 1)), chash(i + vec3(1, 0, 1)), f.x), mix(chash(i + vec3(0, 1, 1)), chash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	vec3 v = VERTEX;
	if (melt > 0.5) {
		vec2 o = vec2(v.x - melt_xz.x, v.z - melt_xz.y);
		float rho2 = dot(o, o) / (melt_cap_rxz * melt_cap_rxz);
		float edge2 = (melt_edge * melt_edge) / (melt_cap_rxz * melt_cap_rxz);
		if (rho2 < edge2) {
			float cap = melt_cap_y - melt_cap_ry * sqrt(max(0.0, 1.0 - rho2));
			if (v.y < cap) {
				v.y = cap;
				// The dome it landed on, so the shading has no seam.
				NORMAL = normalize(vec3(o.x / (melt_cap_rxz * melt_cap_rxz),
					(v.y - melt_cap_y) / (melt_cap_ry * melt_cap_ry),
					o.y / (melt_cap_rxz * melt_cap_rxz)));
			}
		}
	}
	model_pos = v;
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(v, 1.0);
	POSITION.z = mix(POSITION.z, POSITION.w, on_top);
}

void fragment() {
	vec3 c = texture(skin, UV).rgb * base_tint.rgb;
	c *= 1.0 + (cnoise(model_pos * 14.0) * 2.0 - 1.0) * clay_grain;
	ALBEDO = c;
	ROUGHNESS = 0.8;
	SPECULAR = specular;
	EMISSION = c * ambient;
}
"""

const Rules := preload("res://prototype/rules.gd")

enum Mode { ALIVE, DYING, GONE, RESPAWN, GOAL }

var mode := Mode.ALIVE
var spin_angle := 0.0
var spin_tilt := 0.0

var _player: Node3D                    # player3d.gd: move_dir, on_ground
var _model: Node3D
var _burst: CPUParticles3D
var _ring: MeshInstance3D
var _t := 0.0
var _pulse_t := 99.0
var _lean := Vector2.ZERO              # x: roll, y: pitch (radians)
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

# --- legs (brief 5) ---
var _legs: Array[MeshInstance3D] = []  # 0 = left (-x), 1 = right (+x)
var _foot: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]   # world, on the floor
var _foot_from: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _foot_to: Array[Vector3] = [Vector3.ZERO, Vector3.ZERO]
var _down := [true, true]              # planted this frame
var _stride := 0.0                     # 0..1, the whole cycle
var _last_lp := [0.0, 0.5]
var _ground := Vector3.ZERO            # last frame's feet position, world
var _has_ground := false
var _idle_t := 0.0
var _settling := -1                    # which foot is stepping home, -1 = none
var _settle_u := 0.0
var _settle_dur := SETTLE_STEP_S
var _foot_t := [99.0, 99.0]            # seconds since this foot last landed
var _face := Vector2(0.0, 1.0)         # the direction the feet point
var _gspeed := 0.0                     # measured ground speed, units/s, smoothed
var _stride_len := 0.0                 # this frame's stride, shared with the recovery step

var _dust_p: CPUParticles3D = null
var _max_reach_seen := 0.0             # the leash, measured where the leg is DRAWN
var _max_reach_planted := 0.0          # ... and the half of it that matters
var _max_raw := 0.0                    # what it WOULD have been without the clamp
var _ported := false                   # this frame the feet were teleported home

signal footfall(side: int, strength: float)


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
	_build_ring()
	_build_legs()
	_build_dust()
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
		m.set_shader_parameter("melt", 1.0 if MELT_ON else 0.0)
		m.set_shader_parameter("melt_xz", MELT_XZ)
		m.set_shader_parameter("melt_edge", MELT_EDGE)
		m.set_shader_parameter("melt_cap_y", MELT_CAP_Y)
		m.set_shader_parameter("melt_cap_ry", MELT_CAP_RY)
		m.set_shader_parameter("melt_cap_rxz", MELT_CAP_RXZ)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for c in n.get_children():
		_apply_material(c)


func _build_ring() -> void:
	_ring = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * (2.0 * Rules.PLAYER_HALF_W)
	quad.orientation = PlaneMesh.FACE_Y
	_ring.mesh = quad
	var sh := Shader.new()
	sh.code = RING_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	m.render_priority = 9
	m.set_shader_parameter("fill", Color(0.0, 0.0, 0.0, RING_ALPHA))
	m.set_shader_parameter("softness", RING_SOFTNESS)
	m.set_shader_parameter("on_top", RING_ON_TOP)
	_ring.material_override = m
	_ring.top_level = true             # not scaled, tilted or lifted with the body
	add_child(_ring)


# ------------------------------------------------------------
# Brief 5 section 3 — the step cycle
# ------------------------------------------------------------
# Called first thing in _process, before the pose: the pose's bob, roll
# and footfall squash come out of where the feet are.
func _step_cycle(delta: float) -> void:
	_ported = false
	var here := global_position
	if not _has_ground:
		_ground = here
		_has_ground = true
		_feet_home()
		_ported = true
	var moved := Vector3(here.x - _ground.x, 0.0, here.z - _ground.z)
	var d := moved.length()
	# A teleport is not a stride (section 4): reset_to, a rewind, or the
	# carry line yanking the player. A leg must never swim across the
	# field to catch up.
	if d > TELEPORT_UNITS:
		_ground = here
		_feet_home()
		_ported = true
		_stride = 0.0
		_last_lp = [0.0, 0.5]
		return
	_ground = here

	var airborne := not _on_ground()
	if airborne or mode != Mode.ALIVE:
		_tuck_feet(delta)
		_leash()
		return

	# The direction the feet point, and how fast we are going.
	var speed := 0.0
	if _player != null:
		speed = _player.move_dir.limit_length(1.0).length()
	if d > 0.0001:
		var want := Vector2(moved.x, moved.z).normalized()
		# A sharp turn cuts the swinging foot's arc short and plants it.
		if _face.dot(want) < cos(deg_to_rad(TURN_CUT_DEG)):
			_plant_swinging_foot()
		_face = want
	if speed > IDLE_SPEED:
		_idle_t = 0.0
	else:
		_idle_t += delta

	# Distance, not time. No movement, no phase.
	if delta > 0.0:
		_gspeed = lerpf(_gspeed, d / delta, clampf(delta / GSPEED_TAU, 0.0, 1.0))
	# The stride is also capped by how much leg is left after the hip's
	# CURRENT height has been paid for -- which the bob changes every
	# frame. Without this the cycle asks for a stride the leg cannot
	# cover at the top of a bob, and the leash has to clean up after it.
	var hip_h := maxf((_hip(0).y + _hip(1).y) * 0.5 - _floor_y(), 0.01)
	var room := sqrt(maxf(REACH * REACH * 0.85 - hip_h * hip_h, 0.01))
	var stride_len := clampf(_gspeed / CADENCE_HZ, STRIDE_MIN, minf(STRIDE_MAX, 4.0 * room))
	_stride_len = stride_len
	_stride = fposmod(_stride + d / maxf(stride_len, 0.0001), 1.0)

	# The one corrective step home runs on TIME, not on distance: the
	# creature has stopped, so there is no distance left to drive it, and
	# a foot frozen mid-air on the way home is worse than no step at all.

	# Standing still: the cycle is PARKED, not merely stalled. Leaving the
	# stride loop running on a frozen phase kept dragging the swinging
	# foot back onto its arc, which undid the corrective step the moment
	# it finished -- the two fought each other for ever.
	if _idle_t > IDLE_SETTLE_S and speed <= IDLE_SPEED:
		if _settling >= 0:
			_advance_settle(_settling, delta)
		else:
			_settle_feet()
		_leash()
		return

	# The leash. A planted foot that has run out of leg steps NOW rather
	# than waiting for its half of the cycle. The old test here allowed
	# LEG_H * 2.0 = 1.04 units -- well past the 0.75 the leg can actually
	# span -- measured only horizontally, and TELEPORTED the foot instead
	# of stepping it. That was the foot Milko saw left behind.
	# ANTICIPATED, not reacted to: the body will have moved by the time
	# this is drawn, and at 5.85 units/s in the real game that is a tenth
	# of a unit -- enough on its own to put a foot past the leash. Adding
	# where the hip is going is what keeps the planted foot inside it
	# rather than riding the limit every frame.
	var lead := _gspeed * delta
	for i in 2:
		if _down[i] and _foot[i].distance_to(_hip(i)) + lead > REACH * LEASH_STEP:
			_step_now(i, stride_len)
	for i in 2:
		_foot_t[i] += delta
		# One foot may be in a corrective step, on its own clock. The
		# other one must carry on REGARDLESS -- this used to return out of
		# the whole cycle, which left the other foot frozen in the world
		# while the body walked away from it. Over a clean bot run that
		# reached 9.9 units: the foot Milko watched get left behind.
		if _settling == i:
			_advance_settle(i, delta)
			continue
		var lp := fposmod(_stride + (0.5 if i == 1 else 0.0), 1.0)
		var was: float = _last_lp[i]
		_last_lp[i] = lp
		if lp < 0.5:
			# STANCE. The foot does not move. This is the no-slide
			# guarantee, and it is a guarantee because nothing here
			# writes to _foot[i].
			if was >= 0.5:
				_land_foot(i, speed)
			_down[i] = true
		else:
			# SWING: from where it lifted to its next plant point, in an
			# arc. The target is re-aimed every frame, so a direction
			# change mid-step still lands correctly.
			if was < 0.5:
				_foot_from[i] = _foot[i]
				_down[i] = false
			_foot_to[i] = _plant_point(i, stride_len)
			var u := (lp - 0.5) * 2.0
			var p := _foot_from[i].lerp(_foot_to[i], u)
			p.y += sin(PI * u) * STEP_HEIGHT
			_foot[i] = p
			_down[i] = false
	_leash()



# Where this foot should land. The brief says half a stride ahead of the
# hip; that is out by a factor of two and would put the foot always in
# front and never behind. A foot is planted for half the cycle, and the
# body covers half a stride in that time, so to sit symmetrically about
# its hip it has to land a QUARTER of a stride ahead and leave a quarter
# behind. That is also what keeps the leg within its stretch limit.
func _plant_point(i: int, stride_len: float) -> Vector3:
	var hip := _hip(i)
	var ahead := Vector3(_face.x, 0.0, _face.y) * stride_len * 0.25
	var p := hip + ahead
	p.y = _floor_y()
	return p


func _land_foot(i: int, strength: float) -> void:
	_foot[i] = _foot_to[i]
	_foot[i].y = _floor_y()
	_foot_t[i] = 0.0
	_down[i] = true
	footfall.emit(i, strength)
	_dust(_foot[i], DUST_STEP if strength > 0.5 else 0)


# One step of the time-driven corrective step (the leash's flick, and the
# tidy-up when stopping). Only ever one foot at a time.
func _advance_settle(i: int, delta: float) -> void:
	_settle_u += delta / maxf(_settle_dur, 0.001)
	# Re-aim at the hip every frame. The body keeps moving while the foot
	# is on its way, so a target fixed when the step began lands where the
	# hip USED to be -- and the foot arrives already behind, which starts
	# the next recovery, and the next.
	if _settle_dur <= RECOVER_STEP_S + 0.001:
		_foot_to[i] = _plant_point(i, _stride_len if _stride_len > 0.0 else STRIDE_MIN)
	if _settle_u >= 1.0:
		_foot[i] = _foot_to[i]
		_foot[i].y = _floor_y()
		_down[i] = true
		_foot_t[i] = 0.0
		_settling = -1
		footfall.emit(i, 0.35)
	else:
		var q := _foot_from[i].lerp(_foot_to[i], _ease_in_out(_settle_u))
		q.y += sin(PI * _settle_u) * STEP_HEIGHT * 0.5
		_foot[i] = q
		_down[i] = false


# Put this foot into its swing immediately, wherever the cycle is, and
# move the cycle to match so the other foot keeps its half.
# The leash's step is a FLICK, not a stride. Giving it half a cycle (the
# normal swing) meant the body travelled another unit while the foot was
# still on its way, so the leash fired again and the foot spent its life
# being dragged at the limit. It runs on the settle's own clock, which is
# time-driven, so it finishes whatever the body is doing.
func _step_now(i: int, stride_len: float) -> void:
	_foot_from[i] = _foot[i]
	_foot_to[i] = _plant_point(i, stride_len)
	_down[i] = false
	_settling = i
	_settle_u = 0.0
	_settle_dur = RECOVER_STEP_S
	_stride = fposmod(0.5 - (0.5 if i == 1 else 0.0), 1.0)
	_last_lp = [fposmod(_stride, 1.0), fposmod(_stride + 0.5, 1.0)]


# The last word on the invariant: after everything else has had its say,
# no foot is further from its hip than the leg can span. A foot that has
# to be pulled in was not really standing on anything, so it is no longer
# called planted -- which keeps "a planted foot never moves" true.
func _leash() -> void:
	for i in 2:
		var hip := _hip(i)
		var seg := _foot[i] - hip
		var d := seg.length()
		if not _ported:
			_max_raw = maxf(_max_raw, d)
		if d > REACH * 1.5:
			_ported = true
			# Not a stride that went wrong -- the foot is nowhere near the
			# creature. It happens on the first frame of a scene, before
			# anything has moved and the pose is still being set up.
			# Stretching the leg to the limit and leaving it there is the
			# wrong answer; both feet just come home.
			_feet_home()
			return
		if d > REACH and d > 0.0001:
			_foot[i] = hip + seg * (REACH / d)
			_foot[i].y = maxf(_foot[i].y, _floor_y())
			_down[i] = false


# A turn sharper than TURN_CUT_DEG: whichever foot is in the air stops
# where it is and plants; the cycle restarts from that plant.
func _plant_swinging_foot() -> void:
	for i in 2:
		if not _down[i]:
			_foot[i].y = _floor_y()
			_down[i] = true
			_foot_t[i] = 0.0
			footfall.emit(i, 0.5)
			_stride = fposmod(0.5 if i == 1 else 0.0, 1.0)
			_last_lp = [fposmod(_stride, 1.0), fposmod(_stride + 0.5, 1.0)]
			return


# Stopping: the feet end up side by side under the hips. A foot that is
# already close enough just stays; one that is too far takes ONE small
# step home. It never slides there.
func _settle_feet() -> void:
	for i in 2:
		var home := _hip(i)
		home.y = _floor_y()
		# A foot caught in mid-swing when the creature stopped has to come
		# home too. Skipping it (because it is "not planted yet") left it
		# hanging in the air for ever: the swing that would have finished
		# it is driven by distance, and there is no distance any more.
		if not _down[i] or _foot[i].distance_to(home) > FOOT_HOME_TOL:
			_foot_from[i] = _foot[i]
			_foot_to[i] = home
			_down[i] = false
			_settling = i
			_settle_u = 0.0
			_settle_dur = SETTLE_STEP_S
			return


# Brief 5 section 4 — in the air both feet tuck up under the body and
# travel with it, so they turn with the spin instead of being left on the
# floor. Landing is handled by the cycle: the feet are already home.
func _tuck_feet(delta: float) -> void:
	for i in 2:
		var hip := _hip(i)
		var target := hip - global_transform.basis.y.normalized() * (LEG_H * (1.0 - JUMP_TUCK))
		_foot[i] = _foot[i].lerp(target, _rate(JUMP_TUCK_LERP, delta * 60.0))
		_down[i] = false
		_foot_t[i] += delta


# What the pose asks the feet for (brief 5 section 3, "body follows the
# feet"): lowest at each footfall, highest mid-stance.
func _feet_lift() -> float:
	return absf(sin(TAU * _stride)) * BODY_BOB * HEIGHT


func _feet_roll() -> float:
	return sin(TAU * _stride) * deg_to_rad(BODY_ROLL_DEG)


func _feet_squash() -> float:
	var f := 0.0
	for i in 2:
		f = maxf(f, _punch(_foot_t[i], 0.04, 0.16))
	return f * FOOT_SQUASH


# Brief 5 section 5 — footfall dust. ONE shared emitter, restarted at the
# foot that just landed. CPU particles, like the death burst: GPU
# particles are the usual thing to misbehave in a web export.
#
# Budget: DUST_AMOUNT is the emitter's size, so the most dust that can
# exist at once is 8, plus the death burst's 12 = 20 particles, well
# inside the 200 the brief allows.
const DUST_AMOUNT := 8
const DUST_STEP := 3                   # per footfall, above half speed
const DUST_LAND := 8                   # on a landing
const DUST_COLOUR := Color(0.55, 0.55, 0.58)


func _build_dust() -> void:
	_dust_p = CPUParticles3D.new()
	_dust_p.emitting = false
	_dust_p.one_shot = true
	_dust_p.amount = DUST_AMOUNT
	_dust_p.lifetime = 0.35
	_dust_p.explosiveness = 1.0
	_dust_p.direction = Vector3.UP
	_dust_p.spread = 70.0
	_dust_p.initial_velocity_min = 0.6
	_dust_p.initial_velocity_max = 1.6
	_dust_p.gravity = Vector3(0.0, -4.0, 0.0)
	_dust_p.scale_amount_min = 0.25
	_dust_p.scale_amount_max = 0.5
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	_dust_p.scale_amount_curve = curve
	var ball := SphereMesh.new()
	ball.radius = 0.1
	ball.height = 0.2
	ball.radial_segments = 6
	ball.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = DUST_COLOUR
	ball.material = mat
	_dust_p.mesh = ball
	_dust_p.top_level = true
	add_child(_dust_p)


func _dust(at: Vector3, count: int) -> void:
	if _dust_p == null or count <= 0 or mode != Mode.ALIVE:
		return
	_dust_p.amount = count
	_dust_p.global_position = at
	_dust_p.restart()


# The dust emitter, for prewarm.gd (every material must be drawn once
# before the run starts, or its first use is a hitch).
func dust() -> CPUParticles3D:
	return _dust_p


# --- read by tools/shot_walk.gd, and by nothing in the game ---
func stride_phase() -> float:
	return _stride


func foot_planted(i: int) -> bool:
	return _down[i]


func foot_pos(i: int) -> Vector3:
	return _foot[i]


func hip_pos(i: int) -> Vector3:
	return _hip(i)


func reach() -> float:
	return REACH


func max_reach_seen() -> float:
	return _max_reach_seen


func ground_speed() -> float:
	return _gspeed


func max_reach_planted() -> float:
	return _max_reach_planted


func max_raw() -> float:
	return _max_raw


func reset_reach_seen() -> void:
	_max_reach_seen = 0.0
	_max_reach_planted = 0.0
	_max_raw = 0.0


# Brief 5 section 2. Capsules in the creature's own shader, with the melt
# off (they are not the body) and the same "drawn on top" depth squeeze,
# so they never z-fight with the belly they are tucked into.
func _build_legs() -> void:
	var mesh := CapsuleMesh.new()
	mesh.radius = LEG_W * 0.5
	mesh.height = LEG_H
	mesh.radial_segments = 10
	mesh.rings = 4
	var img := Image.create_empty(1, 1, false, Image.FORMAT_RGB8)
	img.fill(Color.WHITE)
	var white := ImageTexture.create_from_image(img)
	for i in 2:
		var leg := MeshInstance3D.new()
		leg.mesh = mesh
		var sh := Shader.new()
		sh.code = SHADER
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("skin", white)
		m.set_shader_parameter("base_tint", LEG_TINT)
		m.set_shader_parameter("on_top", ON_TOP)
		m.set_shader_parameter("ambient", AMBIENT)
		m.set_shader_parameter("melt", 0.0)
		leg.material_override = m
		leg.top_level = true           # the feet live in the world, not on the body
		add_child(leg)
		_legs.append(leg)
	_feet_home()


# Both feet directly under their hips, on the floor. Used at birth and
# every time the player teleports (section 4).
func _feet_home() -> void:
	_settling = -1
	for i in 2:
		_foot[i] = _hip(i)
		_foot[i].y = _floor_y()


func _floor_y() -> float:
	return global_position.y - (_player.y if _player != null else 0.0)


# The hip: a fixed point on the body's underside, carried by whatever the
# body is doing this frame (lean, bob, spin, squash).
func _hip(i: int) -> Vector3:
	var side := -1.0 if i == 0 else 1.0
	return global_transform * Vector3(side * HIP_WIDTH * 0.5, HIP_Y, HIP_Z)


# A leg is the segment foot -> hip: put the capsule at the midpoint, aim
# it along the segment, stretch it to reach (clamped), and keep its own
# width. Never faded, never scaled by the body's squash except through
# the hip moving.
func _place_legs(uniform: float) -> void:
	for i in 2:
		var leg := _legs[i]
		if leg == null:
			continue
		if mode == Mode.GONE or uniform <= 0.001:
			leg.visible = false
			continue
		leg.visible = true
		var hip := _hip(i)
		var foot: Vector3 = _foot[i]
		# The acceptance number, taken here and nowhere else: this is the
		# hip and the foot the capsule is actually drawn between. Measured
		# from outside, it is always a frame stale -- the body moves after
		# the creature has posed itself -- which reads as a false failure.
		var to_hip := foot.distance_to(hip)
		# A frame on which the creature was PUT somewhere is not a frame
		# of walking: the body moves before the feet hear about it, and
		# measuring it says 9.9 units about a 1.1-unit leg.
		if _ported:
			continue
		_max_reach_seen = maxf(_max_reach_seen, to_hip)
		if _down[i]:
			_max_reach_planted = maxf(_max_reach_planted, to_hip)
		# Brief 5 section 4: the feet splay outward through the landing
		# squash, then come back as the squash releases.
		var splay := _punch(_land_t, LAND_IN_S, LAND_OUT_S) * LAND_SPLAY
		if splay > 0.0:
			var out_dir := global_transform.basis.x.normalized() * (-1.0 if i == 0 else 1.0)
			foot += out_dir * LEG_H * splay
		var seg := hip - foot
		var len_now := seg.length()
		if len_now < 0.0001:
			seg = Vector3.UP * LEG_H
			len_now = LEG_H
		var stretch := clampf(len_now / LEG_H, LEG_STRETCH_MIN, LEG_STRETCH_MAX)
		var up := seg / len_now
		# Any basis whose Y is the leg direction; the capsule is round in
		# x/z, so the remaining spin only matters for the depth squash.
		var ref := Vector3.BACK if absf(up.z) < 0.9 else Vector3.RIGHT
		var right := ref.cross(up).normalized()
		var fwd := up.cross(right)
		var b := Basis(right, up, fwd)
		b = b.scaled_local(Vector3(1.0, stretch, LEG_D / LEG_W) * uniform)
		leg.global_transform = Transform3D(b, foot + up * (LEG_H * stretch * 0.5))


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


# The death emitter, for prewarm.gd.
func burst() -> CPUParticles3D:
	return _burst


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
	# Brief 5 section 4: a respawn is a teleport. Both feet come home
	# rather than swimming across the field after the body.
	_feet_home()
	_stride = 0.0
	_last_lp = [0.0, 0.5]
	_look = Vector2.ZERO
	_lean = Vector2.ZERO
	_alarm = 1.0
	spin_angle = 0.0
	spin_tilt = 0.0
	_was_on_ground = true
	_model.visible = true


# Checkpoint (brief 3): a quick glance at the camera and back, GLANCE_S long.
const GLANCE_S := 0.6
var _glance_t := 99.0


func play_glance() -> void:
	_glance_t = 0.0


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
	# The body follows the feet (brief 5 section 3). The old timed bob is
	# gone: a bob on a timer is exactly what "it floats" looked like.
	if _on_ground() and mode == Mode.ALIVE:
		lift += _feet_lift()
		_lean.x += _feet_roll()
		var fs := _feet_squash()
		scale_y *= 1.0 - fs
		scale_xz *= 1.0 + fs * 0.5

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
			# Landing re-plants both feet UNDER THE BODY. They used to
			# resume from wherever the cycle left them before take-off,
			# which is the other half of the foot-left-behind report.
			_feet_home()
			_stride = 0.0
			_last_lp = [0.0, 0.5]
			_foot_t = [0.0, 0.0]
			_dust(_foot[0].lerp(_foot[1], 0.5), DUST_LAND)
			footfall.emit(-1, 1.0)
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
	_glance_t += delta
	if _glance_t < GLANCE_S and mode == Mode.ALIVE:
		var g := sin(PI * _glance_t / GLANCE_S)
		look_to = _toward_camera() * g + look_to * (1.0 - g)
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
	if _player != null:
		var feet: Vector3 = _player.global_position
		_ring.global_position = Vector3(feet.x, minf(feet.y, 0.0) + 0.02, feet.z)
		_ring.visible = mode != Mode.GONE
	# THE STEP CYCLE RUNS HERE, after the pose, not before it. It used to
	# go first because its bob and roll are inputs to the pose -- which
	# meant every hip it read was from LAST frame's transform, while the
	# legs were drawn against this one. A foot planted a healthy 0.70 from
	# its hip measured 1.78 by the time it was drawn. The pose now uses
	# the previous frame's bob (a frame of lag on a wobble, invisible) and
	# everything that touches a foot sees the same hip.
	_step_cycle(delta)
	# The legs last: the hips are read off the pose that was just set.
	_place_legs(maxf(uniform, 0.0))


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
