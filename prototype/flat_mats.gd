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

# Shared: the fade uniforms and the fade amount for this pixel.
const FADE_HEAD := """
uniform vec3 background : source_color;
uniform vec4 fade;   // ahead start, ahead end, behind start, behind end
global uniform float pr_window_back;
varying float world_z;

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
FADE_HEAD

void vertex() {
	world_z = (MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	ALBEDO = albedo.rgb;
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
FADE_HEAD
varying vec3 local_pos;
varying vec3 local_normal;

void vertex() {
	world_z = (MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
	local_pos = VERTEX;
	local_normal = NORMAL;
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
	vec3 base = top ? face.rgb : side.rgb;
	ALBEDO = mix(mix(base, seam.rgb, s), edge_colour.rgb, r);
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


static func _fading(c: Color, see_through: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("wall" if see_through else "flat")
	m.set_shader_parameter("albedo", c)
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


# Dormant hazard state: still clearly magenta, clearly "not yet".
static func magenta_dim() -> Material:
	return flat(WorldPalette.LETHAL_ARMED)


# Anything safe that stands on the field: pillars, checkpoint marker.
static func cyan() -> Material:
	return flat(WorldPalette.SAFE)


# Walls (sweepers, gates): see-through so a wall between the camera and
# the player can never hide the player or the floor behind it.
static func magenta_wall() -> Material:
	return _wall("wall", WorldPalette.LETHAL_LIVE, 0.55)


# Demo (non-lethal) wall: the warning colour.
static func magenta_wall_dim() -> Material:
	return _wall("wall_dim", WorldPalette.LETHAL_ARMED, 0.6)


static func _wall(key: String, c: Color, a: float) -> Material:
	if not _cache.has(key):
		_cache[key] = _fading(Color(c.r, c.g, c.b, a), true)
	return _cache[key]


static func amber() -> Material:
	return flat(WorldPalette.GOAL)


static func amber_dim() -> Material:
	return flat(WorldPalette.GOAL.darkened(0.55))


static func white() -> Material:
	return flat(Color.WHITE)


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
		m.set_shader_parameter("half_size", half)
		m.set_shader_parameter("seam_width", SEAM_WIDTH)
		m.set_shader_parameter("edge_width", EDGE_WIDTH)
		m.set_shader_parameter("outer", outer)
		_cache[key] = _with_fade(m)
	return _cache[key]
