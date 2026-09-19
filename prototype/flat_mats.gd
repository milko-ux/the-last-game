extends RefCounted
# ============================================================
# WORLD MATERIALS — unlit, flat, no glow. Every colour comes from
# WorldPalette (prototype/palette.gd, brief 2) so the meaning stays:
#   magenta = will kill you, cyan = safe surface, amber = goal.
# Materials are cached so the whole track shares a handful.
#
# DISTANCE FADE (camera v2). Godot's depth fog does nothing in the
# gl_compatibility renderer the web export uses (checked with a
# screenshot: 15+ rows in full colour), so the fade is part of the
# material instead and is identical on web and native: every world
# material lerps toward the background colour by how far its pixel is
# from the window along z. The camera rig publishes the window's back
# edge as the global shader uniform `pr_window_back` every frame.
# The player, its shadow ring and the death line never fade.
#
# Three shaders share the fade: FLAT (hazards, markers), TILE (the
# floor: stone face, cyan seams, dark sides) and MONOLITH (brief 2,
# see monoliths.gd). All are built from the same snippets below.
# ============================================================

# Units ahead of the window's back edge (a bar is 8 units): full colour
# up to FADE_AHEAD_START, background colour from FADE_AHEAD_END on, so
# everything more than about three bars ahead is near-black.
const FADE_AHEAD_START := 14.0
const FADE_AHEAD_END := 27.0
# The same behind the death line, so the used-up field does not fill
# the bottom of the screen.
const FADE_BEHIND_START := 2.0
const FADE_BEHIND_END := 10.0

# Tile seam width in world units (brief 2 section 1; 0.06 -> 0.03 on
# 2026-09-19: the seams read as a neon grid), and the bright rim along the
# slab's outer edge, on the top face and the top of the outer side faces.
const SEAM_WIDTH := 0.03
const EDGE_WIDTH := 0.1
# Brief 2b, the stone: grain, per-tile shade, occlusion at the seams.
const GRAIN := 0.06
const GRAIN_SCALE := 0.6
const TILE_VARIATION := 0.03
const AO_WIDTH := 0.12
const AO_AMOUNT := 0.18

# Shared: the fade uniforms and the fade amount for this pixel, plus the
# beat uniforms motion.gd sets once per frame (brief 3).
const FADE_HEAD := """
uniform vec3 background : source_color;
uniform vec4 fade;   // ahead start, ahead end, behind start, behind end
global uniform float pr_window_back;
global uniform float pr_rim_pulse;
global uniform float pr_seam_pulse;
global uniform float pr_armed_pulse;
global uniform float pr_rim_amber;
global uniform vec4 pr_ripple;      // z centre, half width, strength
global uniform float pr_build_front;
varying float world_z;

// Brief 2b: procedural surface. 2-octave value noise from world position,
// no texture lookups. hash -> [0,1); vnoise -> [0,1); grain -> [-1,1].
float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1, 0, 0)), f.x), mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x), mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}
float grain(vec3 p, float scale) {
	float n = vnoise(p / scale) * 0.65 + vnoise(p / scale * 2.3 + 7.1) * 0.35;
	return n * 2.0 - 1.0;
}

// A band of light travelling along the slab (rewind, checkpoint).
float ripple_here() {
	if (pr_ripple.y <= 0.0) { return 0.0; }
	return (1.0 - smoothstep(0.0, pr_ripple.y, abs(world_z - pr_ripple.x))) * pr_ripple.z;
}

float fade_amount() {
	float d = world_z - pr_window_back;
	return max(smoothstep(fade.x, fade.y, d), smoothstep(fade.z, fade.w, -d));
}
"""
# Fully faded pixels are dropped, not painted: the web renderer's 8-bit
# buffer rounds the near-black background colour to pure black, which
# showed as a black silhouette against the background.
const FADE_APPLY := """
	float f = fade_amount();
	if (f > 0.97) {
		discard;
	}
	ALBEDO = mix(ALBEDO, background, f);
"""

const FLAT_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled CULL;
uniform vec4 albedo : source_color;
uniform vec4 live : source_color;   // what an ARMED material breathes toward
uniform float armed = 0.0;          // 1 on the armed materials
FADE_HEAD

void vertex() {
	world_z = (MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	ALBEDO = mix(albedo.rgb, live.rgb, armed * pr_armed_pulse);
FADE_APPLY
	ALPHA_LINE
}
"""

# The floor. A box per tile (or per plain slab): the top face is `face`
# with a `seam`-coloured line SEAM_WIDTH in from every edge (drawn from
# the vertex's position inside the box, not from extra geometry); the
# side faces are `side` with one seam line along their top edge, which is
# what gives the slab its rim and a pit its lit lip.
const TILE_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled;
uniform vec4 face : source_color;
uniform vec4 seam : source_color;
uniform vec4 edge_colour : source_color;
uniform vec4 side : source_color;
uniform vec3 half_size;      // the box's half extents (x, y, z)
uniform float seam_width = 0.03;
uniform float edge_width = 0.1;
uniform vec2 outer;          // 1.0 where this box's -x / +x side is the slab's outer edge
uniform vec4 live : source_color;
uniform float armed = 0.0;   // 1 on the armed tile material: the face breathes toward `live`
uniform vec4 amber : source_color;
uniform float build_depth = 0.5;    // tiles rise from this far below as they enter fade range
uniform float build_length = 1.6;   // over this many units behind the build front
uniform float grain_amount = 0.06;  // +-6 % luminance grain on the face (0 on a live plate: it washes out)
uniform float grain_scale = 0.6;
uniform float side_grain_scale = 1.2;
uniform float tile_variation = 0.03; // +-3 % per tile from a hash of its position
uniform float ao_width = 0.12;      // fake occlusion this far in from every seam...
uniform float ao_amount = 0.18;     // ...this much darker
FADE_HEAD
varying vec3 local_pos;
varying vec3 local_normal;
varying vec3 world_pos;
varying vec3 tile_origin;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_z = wp.z;
	world_pos = wp.xyz;
	tile_origin = MODEL_MATRIX[3].xyz;
	local_pos = VERTEX;
	local_normal = NORMAL;
	// Level start (brief 3 section 5): the field is built just ahead of
	// the player. Tiles beyond the build front sit sunk; they rise as the
	// front passes, row by row, since the front moves with the window.
	float up = 1.0 - smoothstep(pr_build_front - build_length, pr_build_front, world_z);
	VERTEX.y -= build_depth * up;
}

void fragment() {
	bool top = local_normal.y > 0.5;
	float edge;
	float rim = 9.0;   // distance to the slab's outer rim, if this box has one
	if (top) {
		edge = min(half_size.x - abs(local_pos.x), half_size.z - abs(local_pos.z));
		if (outer.x > 0.5) { rim = min(rim, half_size.x + local_pos.x); }
		if (outer.y > 0.5) { rim = min(rim, half_size.x - local_pos.x); }
	} else {
		edge = half_size.y - local_pos.y;   // distance below the top edge
		bool outer_face = (local_normal.x < -0.5 && outer.x > 0.5) || (local_normal.x > 0.5 && outer.y > 0.5);
		if (outer_face) { rim = edge; }
	}
	float s = 1.0 - smoothstep(seam_width - 0.01, seam_width + 0.01, edge);
	float r = 1.0 - smoothstep(edge_width - 0.015, edge_width + 0.015, rim);
	// Stone: grain in the face and sides, a per-tile shade, occlusion at the seams.
	float g = grain(world_pos, top ? grain_scale : side_grain_scale) * grain_amount;
	float v = (hash3(floor(tile_origin * 4.0)) * 2.0 - 1.0) * tile_variation;
	vec3 stone = (top ? face.rgb : side.rgb) * (1.0 + g + v);
	stone *= 1.0 - ao_amount * (1.0 - smoothstep(0.0, ao_width, edge));
	vec3 base = mix(stone, live.rgb, armed * pr_armed_pulse);
	float rip = ripple_here();
	vec3 rim_c = mix(edge_colour.rgb, amber.rgb, pr_rim_amber) * (1.0 + pr_rim_pulse + rip);
	vec3 seam_c = seam.rgb * (1.0 + pr_seam_pulse + rip * 0.6);
	ALBEDO = mix(mix(base, seam_c, s), rim_c, r);
FADE_APPLY
}
"""

static var _cache := {}
static var _shaders := {}


static func _shader(kind: String) -> Shader:
	if not _shaders.has(kind):
		var sh := Shader.new()
		match kind:
			"flat":
				sh.code = FLAT_SHADER.replace("CULL", "").replace("ALPHA_LINE", "")
			"wall":
				sh.code = FLAT_SHADER.replace("CULL", ", cull_disabled").replace("ALPHA_LINE", "ALPHA = albedo.a;")
			"tile":
				sh.code = TILE_SHADER
		sh.code = sh.code.replace("FADE_HEAD", FADE_HEAD).replace("FADE_APPLY", FADE_APPLY)
		_shaders[kind] = sh
	return _shaders[kind]


static func _with_fade(m: ShaderMaterial) -> ShaderMaterial:
	m.set_shader_parameter("background", WorldPalette.BG_BOTTOM)
	m.set_shader_parameter("fade", Quaternion(FADE_AHEAD_START, FADE_AHEAD_END, FADE_BEHIND_START, FADE_BEHIND_END))
	return m


static func _fading(c: Color, see_through: bool, armed: bool = false) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("wall" if see_through else "flat")
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("live", Color(WorldPalette.LETHAL_LIVE, c.a))
	m.set_shader_parameter("armed", 1.0 if armed else 0.0)
	return _with_fade(m)


static func flat(c: Color) -> Material:
	var key := c.to_html()
	if not _cache.has(key):
		_cache[key] = _fading(c, false)
	return _cache[key]


# ------------------------------------------------------------
# Hazards and markers
# ------------------------------------------------------------
static func magenta() -> Material:
	return flat(WorldPalette.LETHAL_LIVE)


# Dormant hazard state: still clearly magenta, clearly "not yet". It
# breathes toward LETHAL_LIVE on each beat of its rate (motion.gd).
static func magenta_dim() -> Material:
	if not _cache.has("armed"):
		_cache["armed"] = _fading(WorldPalette.LETHAL_ARMED, false, true)
	return _cache["armed"]


# Anything safe that stands on the field: pillars, checkpoint marker.
static func cyan() -> Material:
	return flat(WorldPalette.SAFE)


# Walls (sweepers, gates): see-through so a wall between the camera and
# the player can never hide the player or the floor behind it.
static func magenta_wall() -> Material:
	return _wall("wall", WorldPalette.LETHAL_LIVE, 0.55)


# Demo (non-lethal) wall: the warning colour.
static func magenta_wall_dim() -> Material:
	return _wall("wall_dim", WorldPalette.LETHAL_ARMED, 0.6, true)


static func _wall(key: String, c: Color, a: float, armed: bool = false) -> Material:
	if not _cache.has(key):
		_cache[key] = _fading(Color(c.r, c.g, c.b, a), true, armed)
	return _cache[key]


static func amber() -> Material:
	return flat(WorldPalette.GOAL)


static func amber_dim() -> Material:
	return flat(WorldPalette.GOAL.darkened(0.55))


static func white() -> Material:
	return flat(Color.WHITE)


# Pure white, no fade: the death flash on the killer (motion.gd).
static func white_flat() -> StandardMaterial3D:
	if not _cache.has("white_flat"):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color.WHITE
		_cache["white_flat"] = m
	return _cache["white_flat"]


# The player draws on top of everything: you can always see yourself.
static func player(c: Color) -> StandardMaterial3D:
	var key := "player_" + c.to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.no_depth_test = true
		m.render_priority = 10
		m.albedo_color = c
		_cache[key] = m
	return _cache[key]


# ------------------------------------------------------------
# The floor
# ------------------------------------------------------------
# One material per (box size, state, outer edges). Tiles of one bar all
# share a size, so a level still uses only a handful. `outer` says which of
# the box's x sides is the slab's outer edge (left, right) and gets the rim.
static func tile(state: int, half: Vector3, outer: Vector2 = Vector2.ZERO) -> Material:
	var key := "tile_%d_%s_%s" % [state, half, outer]
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader("tile")
		match state:
			2:   # lethal now: the face turns live and the seam lights up
				m.set_shader_parameter("face", WorldPalette.LETHAL_LIVE)
				m.set_shader_parameter("seam", WorldPalette.LETHAL_SEAM)
			1:   # armed: the face tints toward the warning colour
				m.set_shader_parameter("face", WorldPalette.LETHAL_ARMED)
				m.set_shader_parameter("seam", WorldPalette.TILE_SEAM)
			_:
				m.set_shader_parameter("face", WorldPalette.TILE)
				m.set_shader_parameter("seam", WorldPalette.TILE_SEAM)
		m.set_shader_parameter("side", WorldPalette.TILE_SIDE)
		m.set_shader_parameter("edge_colour", WorldPalette.TILE_EDGE)
		m.set_shader_parameter("live", WorldPalette.LETHAL_LIVE)
		m.set_shader_parameter("armed", 1.0 if state == 1 else 0.0)
		m.set_shader_parameter("amber", WorldPalette.GOAL)
		m.set_shader_parameter("grain_amount", 0.0 if state == 2 else GRAIN)
		m.set_shader_parameter("grain_scale", GRAIN_SCALE)
		m.set_shader_parameter("side_grain_scale", GRAIN_SCALE * 2.0)
		m.set_shader_parameter("tile_variation", TILE_VARIATION)
		m.set_shader_parameter("ao_width", AO_WIDTH)
		m.set_shader_parameter("ao_amount", AO_AMOUNT)
		m.set_shader_parameter("half_size", half)
		m.set_shader_parameter("seam_width", SEAM_WIDTH)
		m.set_shader_parameter("edge_width", EDGE_WIDTH)
		m.set_shader_parameter("outer", outer)
		_cache[key] = _with_fade(m)
	return _cache[key]
