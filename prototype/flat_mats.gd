extends RefCounted
# ============================================================
# FLAT MATERIALS — the entire Phase R look. Unlit, flat, no glow.
# Colours come from Palette so the meaning is unchanged:
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
# The player and the death line keep plain materials: they never fade.
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
# Must match the Environment background in track_test.tscn.
const BACKGROUND := Color(0.027451, 0.027451, 0.047059)

const _SHADER_BODY := """
uniform vec4 albedo : source_color;
uniform vec3 background : source_color;
uniform vec4 fade;   // ahead start, ahead end, behind start, behind end
global uniform float pr_window_back;
varying float world_z;

void vertex() {
	world_z = (MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	float d = world_z - pr_window_back;
	float f = max(smoothstep(fade.x, fade.y, d), smoothstep(fade.z, fade.w, -d));
	// Fully faded pixels are dropped, not painted: the web renderer's
	// 8-bit buffer rounds the near-black background colour to pure black,
	// which showed as a black silhouette against the background.
	if (f > 0.97) {
		discard;
	}
	ALBEDO = mix(albedo.rgb, background, f);
	ALPHA_LINE
}
"""

static var _cache := {}
static var _shaders := {}


static func _shader(see_through: bool) -> Shader:
	if not _shaders.has(see_through):
		var sh := Shader.new()
		var mode := "shader_type spatial;\nrender_mode unshaded, fog_disabled%s;\n" % (", cull_disabled" if see_through else "")
		sh.code = mode + _SHADER_BODY.replace("ALPHA_LINE", "ALPHA = albedo.a;" if see_through else "")
		_shaders[see_through] = sh
	return _shaders[see_through]


static func _fading(c: Color, see_through: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader(see_through)
	m.set_shader_parameter("albedo", c)
	m.set_shader_parameter("background", BACKGROUND)
	m.set_shader_parameter("fade", Quaternion(FADE_AHEAD_START, FADE_AHEAD_END, FADE_BEHIND_START, FADE_BEHIND_END))
	return m


static func flat(c: Color) -> Material:
	var key := c.to_html()
	if not _cache.has(key):
		_cache[key] = _fading(c, false)
	return _cache[key]


static func magenta() -> Material:
	return flat(Palette.HAZ)


# Dormant hazard state: still clearly magenta, clearly "not yet".
static func magenta_dim() -> Material:
	return flat(Palette.HAZ.darkened(0.62))


# Slightly under full cyan so the magenta stays the loudest thing on screen.
static func cyan() -> Material:
	return flat(Palette.EDGE.darkened(0.42))


# Walls (sweepers, gates): see-through so a wall between the camera and
# the player can never hide the player or the floor behind it.
static func magenta_wall() -> Material:
	return _wall("wall", Palette.HAZ, 0.55)


# Demo (non-lethal) wall: the warning colour.
static func magenta_wall_dim() -> Material:
	return _wall("wall_dim", Palette.HAZ.darkened(0.62), 0.5)


static func _wall(key: String, c: Color, a: float) -> Material:
	if not _cache.has(key):
		_cache[key] = _fading(Color(c.r, c.g, c.b, a), true)
	return _cache[key]


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


static func amber() -> Material:
	return flat(Palette.GOAL)


static func amber_dim() -> Material:
	return flat(Palette.GOAL.darkened(0.55))


static func white() -> Material:
	return flat(Color.WHITE)
