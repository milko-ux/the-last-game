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
# material lerps toward the FOG by how far its pixel is from the window
# along z. The camera rig publishes the window's back edge as the global
# shader uniform `pr_window_back` every frame.
#
# THE FOG HAS A COLOUR AND A DEPTH (brief 6 section 3, Milko's version):
# the backdrop is a four-stop gradient (WorldPalette.BG_TOP / THIRD /
# MIDDLE / BOTTOM, light at the top, near-black at the bottom), and a
# faded pixel goes toward the backdrop's colour AT ITS OWN SCREEN HEIGHT
# (`fog_colour(fog_sy)`, the vertex's clip-space y), so a far floor or a
# far hazard lightens into the fog instead of turning into a black blob.
# `low_fog()` is the height fog: below the slab's underside everything
# sinks toward BG_BOTTOM with depth, which is what dissolves the
# monoliths' feet.
# The player and the death line never fade; the drop shadows (shadows.gd) fade with their floor.
#
# Three shaders share the fade: FLAT (hazards, markers), TILE (the
# floor: stone face, cyan seams, dark sides) and MONOLITH (brief 2,
# see monoliths.gd). All are built from the same snippets below.
#
# THE LIGHT (brief 6 section 1). The scene's CreatureLight is the one
# light of the world; its direction (toward the light) is the global
# uniform `pr_light_dir`, published by the scene that owns the light.
# The unshaded world shaders fake it: `lit_tone()` in the shared head
# shades a base colour by the face's normal as three tones (top / lit
# side / shadow side, WorldPalette.LIGHT_*), the shadow side pulled
# toward WorldPalette.SHADE_TINT. `pr_light_on` 0 (the ?light=0 dev
# switch) gives the old flat look for an A/B on the phone.
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
const SEAM_DARK := 0.35      # the seam groove: this much darker than the face (brief 6 section 4: was 0.12)
const EDGE_WIDTH := 0.1
# Brief 2b, the stone: grain, per-tile shade, occlusion at the seams.
const GRAIN := 0.06
const GRAIN_SCALE := 0.6
const TILE_VARIATION := 0.08  # brief 6 section 4: +-8 % per tile (was 3)
const AO_WIDTH := 0.12
const AO_AMOUNT := 0.18
# Brief 6 section 4, the floor becomes stone: a bevel band inside every
# tile edge, shaded by the light (the two edges facing it a thin lighter
# line, the two facing away a darker one) -- the cheapest thing that makes
# a flat tile read as a slab with thickness -- and a faint broad sheen
# toward the light on the face.
const BEVEL_WIDTH := 0.08
const BEVEL_AMOUNT := 0.16
const SHEEN_AMOUNT := 0.07
const SHEEN_POWER := 24.0
# The height fog (brief 6 section 3): from this far below the field to
# this far, at most this much toward BG_BOTTOM. The slab's underside is
# at -Field.THICK; the monoliths' feet at -22.
const LOW_FOG_START := 2.0
const LOW_FOG_END := 24.0
const LOW_FOG_MAX := 0.92

# The fog's colour by screen height and the clip-space helper, on their
# own so the backdrop quad and the far silhouettes (camera_rig.gd) can
# share them without the whole head. Included into FADE_HEAD.
const FOG_FUNCTIONS := """
// Brief 6 section 3: the backdrop's colour at a screen height (0 top ..
// 1 bottom), four stops. The same function paints the backdrop quad
// (camera_rig.gd), so a faded thing goes toward exactly what is behind it.
vec3 fog_colour(float sy) {
	sy = clamp(sy, 0.0, 1.0);   // a vertex above the frame must not extrapolate past the top stop (it went white)
	const vec3 top = FOG_TOP;
	const vec3 third = FOG_THIRD;
	const vec3 middle = FOG_MIDDLE;
	const vec3 bottom = FOG_BOTTOM;
	if (sy < 0.3333) { return mix(top, third, sy * 3.0); }
	if (sy < 0.5) { return mix(third, middle, (sy - 0.3333) * 6.0); }
	return mix(middle, bottom, (sy - 0.5) * 2.0);
}

// The screen height of a vertex, for fog_colour: from its clip position.
// (Checked with a screenshot, 2026-09-23: clip y is DOWN here, so the top
// of the frame is -1 -- the same sense as the backdrop quad's UV.)
float screen_y_of(vec4 clip) {
	return 0.5 + 0.5 * clip.y / max(clip.w, 0.001);
}

"""

# Shared: the fade uniforms and the fade amount for this pixel, plus the
# beat uniforms motion.gd sets once per frame (brief 3).
const FADE_HEAD := """
uniform vec4 fade;   // ahead start, ahead end, behind start, behind end
global uniform float pr_window_back;
global uniform float pr_rim_pulse;
global uniform float pr_seam_pulse;
global uniform float pr_armed_pulse;
global uniform float pr_rim_amber;
global uniform vec4 pr_ripple;      // z centre, half width, strength
global uniform float pr_build_front;
global uniform vec3 pr_light_dir;   // toward the light; the CreatureLight's +z
global uniform float pr_light_on;   // 1, or 0 for the pre-brief-6 flat look
// Every varying is highp (2026-09-23, the phone's flat uncarved slabs):
// a world position at z 700+ interpolated at the fragment stage's
// default precision on iOS is a half float, 0.5 units coarse, which
// turns a world-position noise into a constant and a derivative-based
// normal into garbage. Chrome on the Mac never drops precision, which is
// why no screenshot here showed it.
varying highp float world_z;
varying highp float fog_sy;               // the pixel's screen height, 0 = top, 1 = bottom

FOG_FUNCTIONS

// Height fog: below the slab's underside, toward the dark bottom of the
// fog with depth (start, end, the most it may take).
vec3 low_fog(vec3 c, float world_y) {
	const vec3 lf = LOW_FOG;
	return mix(c, FOG_BOTTOM, smoothstep(lf.x, lf.y, -world_y) * lf.z);
}

// Brief 6 section 1: a base colour shaded by the face's normal against
// the light, as three tones (not a ramp): the top, a side facing the
// light, a side facing away -- the last pulled toward a cool blue. The
// steps are a hair wide so a facet on the boundary does not shimmer.
vec3 lit_tone(vec3 c, vec3 n) {
	const vec4 tones = LIGHT_TONES;   // top, lit side, shadow side, tint amount
	const vec3 shade = SHADE_TINT;    // (not `tint`: the clay shader has a uniform of that name)
	float up = smoothstep(0.55, 0.75, n.y);
	float lh = length(n.xz);
	float facing = lh > 0.001 ? dot(n.xz / lh, normalize(pr_light_dir.xz)) : sign(n.y);
	float lit = smoothstep(-0.12, 0.12, facing);
	vec3 side_c = mix(mix(c * tones.z, shade, tones.w), c * tones.y, lit);
	return mix(c, mix(side_c, c * tones.x, up), pr_light_on);
}

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
	ALBEDO = mix(ALBEDO, fog_colour(fog_sy), f);
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
	fog_sy = screen_y_of(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	ALBEDO = mix(albedo.rgb, live.rgb, armed * pr_armed_pulse);
FADE_APPLY
	ALPHA_LINE
}
"""

# Hot glass (brief 2b section 3): walls, gates, sweepers, slammers, the
# goal gate. A translucent body, a fresnel rim toward `rim_colour` that
# reads as a bright outline at phone size, an inner glow brighter at the
# base, and a slow heat shimmer inside the body (never on the rim). The
# armed state breathes toward `live` on pr_armed_pulse (brief 3), which
# now also drives the rim strength.
const GLASS_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_draw_opaque;
uniform vec4 albedo : source_color;
uniform vec4 live : source_color;
uniform vec4 rim_colour : source_color;
uniform float armed = 0.0;
uniform float rim_strength = 0.6;
uniform float glow_range = 0.3;       // base-to-top inner glow, this much brighter at the floor
uniform float shimmer_speed = 0.15;   // units / s of vertical drift
uniform float shimmer_contrast = 0.04;
uniform float half_height = 1.5;
FADE_HEAD
varying highp vec3 world_pos;
varying highp vec3 world_n;
varying highp float local_y;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_z = wp.z;
	world_pos = wp.xyz;
	world_n = normalize(mat3(MODEL_MATRIX) * NORMAL);
	local_y = VERTEX.y;
	fog_sy = screen_y_of(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	float pulse = armed * pr_armed_pulse;
	vec4 body = mix(albedo, live, pulse);
	// Inner glow: brighter at the base.
	float base_t = clamp(0.5 - local_y / (2.0 * half_height), 0.0, 1.0);
	vec3 c = body.rgb * (1.0 + glow_range * base_t);
	// Heat shimmer: 1-octave noise drifting upward inside the body.
	float sh = vnoise(vec3(world_pos.x * 0.8, world_pos.y * 0.8 - TIME * shimmer_speed, world_pos.z * 0.8)) * 2.0 - 1.0;
	c *= 1.0 + shimmer_contrast * sh;
	// Fresnel rim: edges facing away from the camera brighten toward the rim colour.
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	float fr = pow(1.0 - abs(dot(normalize(world_n), v)), 2.5);
	float strength = (rim_strength + 0.4 * pulse) * fr;
	ALBEDO = mix(c, rim_colour.rgb, clamp(strength, 0.0, 1.0));
	ALPHA = clamp(body.a + strength * 0.5, 0.0, 1.0);
FADE_APPLY
}
"""

# Gloss (brief 2b sections 3-4): orbiter and volley orbs, and the notes.
# LIT, like the creature's eye: a dark body, a sharp specular highlight
# from the scene's directional light, a soft rim, and a faint inner glow.
const GLOSS_SHADER := """
shader_type spatial;
render_mode fog_disabled, specular_schlick_ggx;
uniform vec4 albedo : source_color;
uniform vec4 rim_colour : source_color;
uniform float roughness = 0.22;
uniform float inner_glow = 0.25;
uniform float rim_amount = 0.5;
FADE_HEAD
varying highp vec3 world_pos;
varying highp vec3 world_n;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_z = wp.z;
	world_pos = wp.xyz;
	world_n = normalize(mat3(MODEL_MATRIX) * NORMAL);
	fog_sy = screen_y_of(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	float fr = pow(1.0 - abs(dot(normalize(world_n), v)), 3.0);
	float f = fade_amount();
	if (f > 0.97) {
		discard;
	}
	ALBEDO = mix(albedo.rgb, fog_colour(fog_sy), f);
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	EMISSION = (albedo.rgb * inner_glow + rim_colour.rgb * fr * rim_amount) * (1.0 - f);
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
uniform vec4 slab_side : source_color;   // the body's stone: side faces, pit walls (brief 6 section 4)
uniform float bevel_width = 0.08;
uniform float bevel_amount = 0.16;
uniform float sheen_amount = 0.07;
uniform float sheen_power = 24.0;
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
varying highp vec3 local_pos;
varying highp vec3 local_normal;
varying highp vec3 world_n;
varying highp vec3 world_pos;
varying highp vec3 tile_origin;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_z = wp.z;
	world_pos = wp.xyz;
	tile_origin = MODEL_MATRIX[3].xyz;
	local_pos = VERTEX;
	local_normal = NORMAL;
	world_n = normalize(mat3(MODEL_MATRIX) * NORMAL);
	// Level start (brief 3 section 5): the field is built just ahead of
	// the player. Tiles beyond the build front sit sunk; they rise as the
	// front passes, row by row, since the front moves with the window.
	float up = 1.0 - smoothstep(pr_build_front - build_length, pr_build_front, world_z);
	VERTEX.y -= build_depth * up;
	fog_sy = screen_y_of(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
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
	// The top is the face; the sides and pit walls are the slab's own dark
	// stone; both in the light's tones (brief 6 sections 1 and 4).
	vec3 n = normalize(world_n);
	float g = grain(world_pos, top ? grain_scale : side_grain_scale) * grain_amount;
	float v = (hash3(floor(tile_origin * 4.0)) * 2.0 - 1.0) * tile_variation;
	vec3 stone = lit_tone(top ? face.rgb : slab_side.rgb, n) * (1.0 + g + v);
	stone *= 1.0 - ao_amount * (1.0 - smoothstep(0.0, ao_width, edge));
	if (top) {
		// The bevel: a band inside each edge, lighter where the edge faces
		// the light, darker where it faces away; and the sheen.
		vec2 lxz = normalize(pr_light_dir.xz);
		float bw = bevel_width;
		float bev = (1.0 - smoothstep(bw * 0.6, bw, half_size.x - local_pos.x)) * sign(lxz.x)
			+ (1.0 - smoothstep(bw * 0.6, bw, half_size.x + local_pos.x)) * sign(-lxz.x)
			+ (1.0 - smoothstep(bw * 0.6, bw, half_size.z - local_pos.z)) * sign(lxz.y)
			+ (1.0 - smoothstep(bw * 0.6, bw, half_size.z + local_pos.z)) * sign(-lxz.y);
		vec3 vdir = normalize(CAMERA_POSITION_WORLD - world_pos);
		vec3 hv = normalize(normalize(pr_light_dir) + vdir);
		float sheen = pow(max(dot(n, hv), 0.0), sheen_power) * sheen_amount;
		stone *= 1.0 + (bevel_amount * clamp(bev, -1.0, 1.0) + sheen) * pr_light_on;
	}
	vec3 base = mix(stone, live.rgb, armed * pr_armed_pulse);
	float rip = ripple_here();
	vec3 rim_c = mix(edge_colour.rgb, amber.rgb, pr_rim_amber) * (1.0 + pr_rim_pulse + rip);
	vec3 seam_c = seam.rgb * (1.0 + pr_seam_pulse + rip * 0.6);
	ALBEDO = low_fog(mix(mix(base, seam_c, s), rim_c, r), world_pos.y);
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
			"glass":
				sh.code = GLASS_SHADER
			"gloss":
				sh.code = GLOSS_SHADER
		sh.code = sh.code.replace("FADE_HEAD", fade_head()).replace("FADE_APPLY", FADE_APPLY)
		_shaders[kind] = sh
	return _shaders[kind]


# The shared head with the palette's light tones written in (brief 6):
# the numbers live in palette.gd, the shader text here, and this is the
# one place they meet. props.gd builds its shaders through it too.
static func fog_functions() -> String:
	return FOG_FUNCTIONS.replace("FOG_TOP", _vec3(WorldPalette.BG_TOP)).replace("FOG_THIRD", _vec3(WorldPalette.BG_THIRD)) \
		.replace("FOG_MIDDLE", _vec3(WorldPalette.BG_MIDDLE)).replace("FOG_BOTTOM", _vec3(WorldPalette.BG_BOTTOM))


static func fade_head() -> String:
	var t := WorldPalette.SHADE_TINT
	return FADE_HEAD.replace("FOG_FUNCTIONS", fog_functions()).replace("LIGHT_TONES", "vec4(%.3f, %.3f, %.3f, %.3f)" % [
			WorldPalette.LIGHT_TOP, WorldPalette.LIGHT_SIDE, WorldPalette.LIGHT_SHADE, WorldPalette.SHADE_TINT_AMOUNT]) \
		.replace("SHADE_TINT", "vec3(%.4f, %.4f, %.4f)" % [t.r, t.g, t.b]) \
		.replace("FOG_TOP", _vec3(WorldPalette.BG_TOP)).replace("FOG_THIRD", _vec3(WorldPalette.BG_THIRD)) \
		.replace("FOG_MIDDLE", _vec3(WorldPalette.BG_MIDDLE)).replace("FOG_BOTTOM", _vec3(WorldPalette.BG_BOTTOM)) \
		.replace("LOW_FOG", "vec3(%.1f, %.1f, %.2f)" % [LOW_FOG_START, LOW_FOG_END, LOW_FOG_MAX])


static func _vec3(c: Color) -> String:
	return "vec3(%.4f, %.4f, %.4f)" % [c.r, c.g, c.b]


static func _with_fade(m: ShaderMaterial) -> ShaderMaterial:
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
# Hazards and markers (brief 2b: hot glass for the boxes, gloss for the orbs)
# ------------------------------------------------------------
# Hot glass. `live` = lethal now (70 % body, rim 1.0); otherwise armed
# (55 %, rim 0.6, breathing toward live on the beat). `half_height` sets
# where the base glow sits.
static func glass(live: bool, half_height: float, key_extra: String = "") -> Material:
	var key := "glass_%s_%.2f%s" % [live, half_height, key_extra]
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader("glass")
		var c := WorldPalette.LETHAL_LIVE if live else WorldPalette.LETHAL_ARMED
		m.set_shader_parameter("albedo", Color(c, 0.70 if live else 0.55))
		m.set_shader_parameter("live", Color(WorldPalette.LETHAL_LIVE, 0.70))
		m.set_shader_parameter("rim_colour", WorldPalette.LETHAL_SEAM)
		m.set_shader_parameter("armed", 0.0 if live else 1.0)
		m.set_shader_parameter("rim_strength", 1.0 if live else 0.6)
		m.set_shader_parameter("half_height", half_height)
		_cache[key] = _with_fade(m)
	return _cache[key]


# The goal gate: hot glass in GOAL, rim 1.0, no breathing.
static func goal_glass() -> Material:
	if not _cache.has("goal_glass"):
		var m := ShaderMaterial.new()
		m.shader = _shader("glass")
		m.set_shader_parameter("albedo", Color(WorldPalette.GOAL, 0.70))
		m.set_shader_parameter("live", Color(WorldPalette.GOAL, 0.70))
		m.set_shader_parameter("rim_colour", Color(1.0, 0.92, 0.75))
		m.set_shader_parameter("armed", 0.0)
		m.set_shader_parameter("rim_strength", 1.0)
		m.set_shader_parameter("half_height", 1.6)
		_cache["goal_glass"] = _with_fade(m)
	return _cache["goal_glass"]


# The shield (Phase E section 5): a thin glass bubble around the creature,
# the hot-glass shader in SAFE cyan — nearly clear body, bright rim.
static func shield() -> Material:
	if not _cache.has("shield"):
		var m := ShaderMaterial.new()
		m.shader = _shader("glass")
		m.set_shader_parameter("albedo", Color(WorldPalette.SAFE, 0.10))
		m.set_shader_parameter("live", Color(WorldPalette.SAFE, 0.10))
		m.set_shader_parameter("rim_colour", WorldPalette.SAFE.lightened(0.35))
		m.set_shader_parameter("armed", 0.0)
		m.set_shader_parameter("rim_strength", 0.9)
		m.set_shader_parameter("glow_range", 0.0)
		m.set_shader_parameter("shimmer_contrast", 0.0)
		m.set_shader_parameter("half_height", 1.6)
		m.render_priority = 12          # over the creature, which draws on top of the world
		_cache["shield"] = _with_fade(m)
	return _cache["shield"]


# Gloss: orbs (magenta) and notes (amber), lit by the creature's light.
static func gloss(c: Color, rim: Color, key: String) -> Material:
	var k := "gloss_" + key
	if not _cache.has(k):
		var m := ShaderMaterial.new()
		m.shader = _shader("gloss")
		m.set_shader_parameter("albedo", c)
		m.set_shader_parameter("rim_colour", rim)
		_cache[k] = _with_fade(m)
	return _cache[k]


static func orb(live: bool) -> Material:
	return gloss(WorldPalette.LETHAL_LIVE.darkened(0.35) if live else WorldPalette.LETHAL_ARMED,
		WorldPalette.LETHAL_SEAM, "orb_live" if live else "orb_armed")


static func note() -> Material:
	return gloss(WorldPalette.GOAL.darkened(0.15), Color(1.0, 0.9, 0.6), "note")


# Boxes that kill: slammers and the volley's muzzle. Glass.
static func magenta() -> Material:
	return glass(true, 1.0)


static func magenta_dim() -> Material:
	return glass(false, 1.0)


# Anything safe that stands on the field (pillars, checkpoint marker):
# stone in the SAFE tint with the slab edge's bright rim on every edge.
static func cyan() -> Material:
	return stone(WorldPalette.SAFE.darkened(0.55), Vector3(0.5, 1.5, 0.5))


static func stone(c: Color, half: Vector3) -> Material:
	var key := "stone_%s_%s" % [c.to_html(), half]
	if not _cache.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader("tile")
		m.set_shader_parameter("face", c)
		m.set_shader_parameter("seam", WorldPalette.TILE_EDGE)
		m.set_shader_parameter("edge_colour", WorldPalette.TILE_EDGE)
		m.set_shader_parameter("slab_side", c)
		m.set_shader_parameter("bevel_amount", 0.0)
		m.set_shader_parameter("sheen_amount", 0.0)
		m.set_shader_parameter("half_size", half)
		m.set_shader_parameter("seam_width", EDGE_WIDTH * 0.6)
		m.set_shader_parameter("edge_width", EDGE_WIDTH * 0.6)
		m.set_shader_parameter("outer", Vector2.ONE)
		m.set_shader_parameter("live", c)
		m.set_shader_parameter("armed", 0.0)
		m.set_shader_parameter("amber", WorldPalette.GOAL)
		m.set_shader_parameter("grain_amount", GRAIN)
		m.set_shader_parameter("grain_scale", GRAIN_SCALE)
		m.set_shader_parameter("side_grain_scale", GRAIN_SCALE)
		m.set_shader_parameter("tile_variation", 0.0)
		m.set_shader_parameter("ao_width", AO_WIDTH)
		m.set_shader_parameter("ao_amount", AO_AMOUNT)
		m.set_shader_parameter("build_depth", 0.0)
		_cache[key] = _with_fade(m)
	return _cache[key]


# Walls (sweepers, gates): hot glass, see-through so a wall between the
# camera and the player can never hide the player or the floor behind it.
static func magenta_wall() -> Material:
	return glass(true, 1.5, "_wall")


# Demo / armed wall: the warning colour, breathing.
static func magenta_wall_dim() -> Material:
	return glass(false, 1.5, "_wall")


static func amber() -> Material:
	return goal_glass()


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
		# Seams are a shallow groove, SEAM_DARK darker than the face, never
		# coloured (2026-09-20): the slab's bright rim is the only line on
		# the field.
		var face_c := WorldPalette.TILE
		match state:
			2:   # lethal now: the face turns live (the grain washes out)
				face_c = WorldPalette.LETHAL_LIVE
			1:   # armed: the face tints toward the warning colour
				face_c = WorldPalette.LETHAL_ARMED
		m.set_shader_parameter("face", face_c)
		m.set_shader_parameter("seam", face_c.darkened(SEAM_DARK))
		m.set_shader_parameter("edge_colour", WorldPalette.TILE_EDGE)
		m.set_shader_parameter("slab_side", WorldPalette.SLAB_SIDE)
		m.set_shader_parameter("bevel_width", BEVEL_WIDTH)
		m.set_shader_parameter("bevel_amount", BEVEL_AMOUNT)
		m.set_shader_parameter("sheen_amount", SHEEN_AMOUNT)
		m.set_shader_parameter("sheen_power", SHEEN_POWER)
		m.set_shader_parameter("live", WorldPalette.LETHAL_LIVE)
		m.set_shader_parameter("armed", 1.0 if state == 1 else 0.0)
		m.set_shader_parameter("amber", WorldPalette.GOAL)
		# Brief 6 section 4: a live plate keeps its grain and bevel -- stone
		# under the magenta, never a flat rectangle (it used to drop the grain).
		m.set_shader_parameter("grain_amount", GRAIN)
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
