extends RefCounted
# ============================================================
# PROPS (Phase A brief 4) — the clay and stone models that replace the
# hazard boxes and the monolith boxes. Visual only: every hit box,
# timing and position lives in rules.gd / hazard_math.gd and is not
# touched; the model is scaled to the box, never the reverse.
#
# The game loads the LIGHT copies in assets/models/lod/ (made by
# tools/decimate_models.py: ~2-4k triangles each, vertex colours
# sampled from the bake, no texture). The originals in assets/models/
# stay untouched.
#
# Per model: its rest yaw (they do not arrive facing the right way —
# all of these happen to face +z, eye toward +z), its pivot (base
# centre for standing things, so `position` is where the feet are),
# and its size in model units, from the GLB bounds.
#
# Materials: CLAY is lit like the creature (they are the same clay):
# armed = wine tint over the clay, live = hot magenta wash with the
# bright rim, breathing to the beat on pr_armed_pulse (brief 3), the
# white flash still works (motion.gd swaps material_override). Eye
# recesses stay dark: the tint is scaled by the clay's own luminance.
# BUILDING is unlit with the distance fade and the concrete grain on
# top of the vertex colour (at 1.5k triangles the bake alone is flat).
# ============================================================

const Mats := preload("res://prototype/flat_mats.gd")

const DIR := "res://assets/models/lod/"

# name -> [size in model units (x, y, z), rest yaw degrees]
const MODELS := {
	"gate_pillar": [Vector3(1.12, 1.90, 1.08), 0.0],
	"sweeper_segment": [Vector3(1.90, 1.13, 1.22), 0.0],
	"slammer": [Vector3(1.85, 1.90, 1.77), 0.0],
	"orbiter_pillar": [Vector3(1.28, 1.90, 1.08), 0.0],
	"volley_emitter": [Vector3(1.72, 1.90, 1.82), 0.0],
	"building_tall": [Vector3(0.62, 1.90, 0.34), 0.0],
	"building_stacked": [Vector3(0.96, 1.90, 1.08), 0.0],
}
# Every model is centred on its own middle: the base is at -size.y / 2.

const CLAY_SHADER := """
shader_type spatial;
render_mode fog_disabled, cull_back;
uniform vec4 tint : source_color;        // the armed (wine) or live (magenta) colour
uniform vec4 live : source_color;        // what an armed prop breathes toward
uniform vec4 rim_colour : source_color;
uniform float tint_amount = 0.55;
uniform float armed = 0.0;               // 1 on the armed material
uniform float rim_strength = 0.0;        // 1.0 when live
uniform float ambient = 0.35;
uniform float grain_amount = 0.04;
FADE_HEAD
varying vec3 world_pos;
varying vec3 world_n;
varying vec3 vcol;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_z = wp.z;
	world_pos = wp.xyz;
	world_n = normalize(mat3(MODEL_MATRIX) * NORMAL);
	vcol = COLOR.rgb;
}

void fragment() {
	float pulse = armed * pr_armed_pulse;
	vec3 t = mix(tint.rgb, live.rgb, pulse);
	float lum = dot(vcol, vec3(0.3, 0.59, 0.11));
	float keep_dark = smoothstep(0.04, 0.22, lum);     // the eye recess stays a recess
	vec3 c = mix(vcol, t, (tint_amount + 0.3 * pulse) * keep_dark);
	c *= 1.0 + grain(world_pos, 0.35) * grain_amount;
	vec3 v = normalize(CAMERA_POSITION_WORLD - world_pos);
	float fr = pow(1.0 - abs(dot(normalize(world_n), v)), 2.5);
	float f = fade_amount();
	if (f > 0.97) {
		discard;
	}
	ALBEDO = mix(c, background, f);
	ROUGHNESS = 0.8;
	SPECULAR = 0.35;
	EMISSION = (c * ambient + rim_colour.rgb * fr * (rim_strength + 0.5 * pulse)) * (1.0 - f);
}
"""

const BUILDING_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled;
uniform float far_lift = 0.35;      // the far, huge ones are this much lighter
uniform float grain_amount = 0.08;
uniform float grain_scale = 1.5;
uniform float foot_band = 0.3;
uniform float foot_dark = 0.25;
FADE_HEAD
varying vec3 world_pos;
varying vec3 world_n;
varying vec3 vcol;
varying float far;
varying float above_base;

void vertex() {
	// Taper: the top half narrows to INSTANCE_CUSTOM.r of its width.
	if (VERTEX.y > 0.0) {
		VERTEX.xz *= INSTANCE_CUSTOM.r;
	}
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_z = wp.z;
	world_pos = wp.xyz;
	world_n = normalize(mat3(MODEL_MATRIX) * NORMAL);
	vcol = COLOR.rgb;
	far = INSTANCE_CUSTOM.g;
	above_base = (VERTEX.y + 0.95) * length(MODEL_MATRIX[1].xyz);
}

float triplanar(vec3 p, vec3 n, float scale) {
	vec3 w = abs(n);
	w /= (w.x + w.y + w.z);
	return grain(vec3(p.y, p.z, 0.0), scale) * w.x + grain(vec3(p.x, p.z, 1.7), scale) * w.y + grain(vec3(p.x, p.y, 3.1), scale) * w.z;
}

void fragment() {
	vec3 c = vcol * (1.0 + far_lift * far);
	c *= 1.0 + triplanar(world_pos, world_n, grain_scale) * grain_amount;
	c *= 1.0 - foot_dark * (1.0 - smoothstep(0.0, foot_band, above_base));
	ALBEDO = c;
FADE_APPLY
}
"""

static var _scenes := {}
static var _mats := {}
static var _shaders := {}


static func _shader(kind: String) -> Shader:
	if not _shaders.has(kind):
		var sh := Shader.new()
		sh.code = (CLAY_SHADER if kind == "clay" else BUILDING_SHADER).replace("FADE_HEAD", Mats.FADE_HEAD).replace("FADE_APPLY", Mats.FADE_APPLY)
		_shaders[kind] = sh
	return _shaders[kind]


# Clay in the armed or live state.
static func clay(live: bool) -> Material:
	var key := "clay_live" if live else "clay_armed"
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader("clay")
		m.set_shader_parameter("tint", WorldPalette.LETHAL_LIVE if live else WorldPalette.LETHAL_ARMED)
		m.set_shader_parameter("live", WorldPalette.LETHAL_LIVE)
		m.set_shader_parameter("rim_colour", WorldPalette.LETHAL_SEAM)
		m.set_shader_parameter("tint_amount", 0.75 if live else 0.55)
		m.set_shader_parameter("armed", 0.0 if live else 1.0)
		m.set_shader_parameter("rim_strength", 1.0 if live else 0.0)
		m.set_shader_parameter("background", WorldPalette.BG_BOTTOM)
		m.set_shader_parameter("fade", Quaternion(Mats.FADE_AHEAD_START, Mats.FADE_AHEAD_END, Mats.FADE_BEHIND_START, Mats.FADE_BEHIND_END))
		_mats[key] = m
	return _mats[key]


# Safe clay (the orbiter's pillar): the bake's own colour, no tint, no rim.
static func clay_safe() -> Material:
	if not _mats.has("clay_safe"):
		var m := ShaderMaterial.new()
		m.shader = _shader("clay")
		m.set_shader_parameter("tint", WorldPalette.SAFE)
		m.set_shader_parameter("live", WorldPalette.SAFE)
		m.set_shader_parameter("rim_colour", WorldPalette.SAFE)
		m.set_shader_parameter("tint_amount", 0.0)
		m.set_shader_parameter("armed", 0.0)
		m.set_shader_parameter("rim_strength", 0.25)
		m.set_shader_parameter("background", WorldPalette.BG_BOTTOM)
		m.set_shader_parameter("fade", Quaternion(Mats.FADE_AHEAD_START, Mats.FADE_AHEAD_END, Mats.FADE_BEHIND_START, Mats.FADE_BEHIND_END))
		_mats["clay_safe"] = m
	return _mats["clay_safe"]


static func building() -> Material:
	if not _mats.has("building"):
		var m := ShaderMaterial.new()
		m.shader = _shader("building")
		m.set_shader_parameter("background", WorldPalette.BG_BOTTOM)
		m.set_shader_parameter("fade", Quaternion(Mats.FADE_AHEAD_START, Mats.FADE_AHEAD_END, Mats.FADE_BEHIND_START, Mats.FADE_BEHIND_END))
		_mats["building"] = m
	return _mats["building"]


static func size_of(name: String) -> Vector3:
	return MODELS[name][0]


# The model's mesh (the one MeshInstance3D in the light GLB).
static func mesh_of(name: String) -> Mesh:
	var inst := instance(name)
	var mi := _first_mesh(inst)
	var mesh: Mesh = mi.mesh if mi != null else null
	inst.free()
	return mesh


static func instance(name: String) -> Node3D:
	if not _scenes.has(name):
		_scenes[name] = load(DIR + name + ".glb")
	return _scenes[name].instantiate()


static func _first_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _first_mesh(c)
		if r != null:
			return r
	return null


# A placed model: `size` is the world-space box it must fill (per axis;
# use the same number three times for a uniform fit), pivot at the base
# centre ("base") or the top centre ("top"), facing +z after `yaw` on
# top of the model's rest yaw, `mirror_x` flips it. Returns a Node3D
# whose position is the pivot; the MeshInstance3D inside carries `mat`.
static func make(name: String, size: Vector3, pivot: String, mat: Material, yaw_deg: float = 0.0, mirror_x: bool = false) -> Node3D:
	var root := Node3D.new()
	root.name = name
	var model := instance(name)
	var msize: Vector3 = size_of(name)
	var s := Vector3(size.x / msize.x, size.y / msize.y, size.z / msize.z)
	if mirror_x:
		s.x = -s.x
	var b := Basis(Vector3.UP, deg_to_rad(MODELS[name][1] + yaw_deg)).scaled_local(s)
	var pivot_y := -msize.y * 0.5 if pivot == "base" else msize.y * 0.5
	model.transform = Transform3D(b, -(b * Vector3(0.0, pivot_y, 0.0)))
	var mi := _first_mesh(model)
	if mi != null:
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(model)
	return root
