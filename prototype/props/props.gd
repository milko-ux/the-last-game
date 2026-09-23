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
# BUILDING is fully procedural (no colour from the model): see the
# shader's own comment.
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
	# The near copies: 6k triangles, the carvings survive as geometry.
	"building_tall_hi": [Vector3(0.62, 1.90, 0.34), 0.0],
	"building_stacked_hi": [Vector3(0.96, 1.90, 1.08), 0.0],
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

# BUILDING (2026-09-20): fully procedural, no colour from the model at
# all (the rule: no AI image textures in the game, and the vertex colours
# were a blurred copy of one). Stone/concrete from WORLD position with
# triplanar mapping, so it is equally crisp on a 12-unit and a 60-unit
# monolith and never stretches. The carved symbols and the circle are
# GEOMETRY (the _hi meshes); what makes them readable is light, so the
# shader lights each facet from its true face normal (screen-space
# derivatives of the world position: hard, chiselled edges, the same on
# web and native, no dependence on the decimated vertex normals).
# Brief 6 section 1: the facet is shaded by the world's one light
# (lit_tone in the shared head: top / lit side / shadow side), which
# replaced this shader's own light direction, its smooth dark-to-lit
# ramp and its "top 12 % lighter".
# Fog: the usual fade along z, plus fog to the sides and below, so the
# far ones and every monolith's foot dissolve into the background.
const BUILDING_SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled;
uniform vec3 colour : source_color;
// The pre-brief-6 shading, kept ONLY as the ?light=0 look (an exact A/B):
uniform vec3 old_light_dir = vec3(-0.35, 0.6, -0.72);
uniform float old_shade_dark = 0.45;
uniform float old_shade_lit = 1.3;
uniform float old_top_lighter = 0.12;
uniform float old_colour_scale = 0.77;   // the stone was 30 % darker then (palette.gd BUILDING_STONE)
uniform float grain_amount = 0.08;   // fine grain, +-8 % at 1.5 units
uniform float grain_scale = 1.5;
uniform float coarse_amount = 0.05;  // +-5 % at 5 units so big faces are not flat
uniform float coarse_scale = 5.0;
uniform float band_every = 2.5;      // formwork lines every 2.5 units of height...
uniform float band_width = 0.05;
uniform float band_dark = 0.03;
uniform vec3 side_fog = vec3(16.0, 60.0, 0.85);   // |x| start, end, most it may take
uniform vec3 low_fog = vec3(6.0, 30.0, 0.9);      // depth below the field: start, end, most
FADE_HEAD
varying vec3 world_pos;

void vertex() {
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_z = wp.z;
	world_pos = wp.xyz;
}

float triplanar(vec3 p, vec3 n, float scale) {
	vec3 w = abs(n);
	w /= (w.x + w.y + w.z);
	return grain(vec3(p.y, p.z, 0.0), scale) * w.x + grain(vec3(p.x, p.z, 1.7), scale) * w.y + grain(vec3(p.x, p.y, 3.1), scale) * w.z;
}

void fragment() {
	float f = fade_amount();
	if (f > 0.97) {
		discard;
	}
	// The facet's own normal, turned toward the camera.
	vec3 n = normalize(cross(dFdx(world_pos), dFdy(world_pos)));
	if (dot(n, CAMERA_POSITION_WORLD - world_pos) < 0.0) {
		n = -n;
	}
	vec3 c = lit_tone(colour, n);
	if (pr_light_on < 0.5) {
		float lit = dot(n, normalize(old_light_dir)) * 0.5 + 0.5;
		c = colour * old_colour_scale * mix(old_shade_dark, old_shade_lit, lit) * (1.0 + old_top_lighter * smoothstep(0.7, 0.95, n.y));
	}
	float g = triplanar(world_pos, n, grain_scale) * grain_amount + triplanar(world_pos, n, coarse_scale) * coarse_amount;
	float band = 1.0 - smoothstep(band_width * 0.5, band_width, abs(fract(world_pos.y / band_every) - 0.5) * band_every);
	c *= (1.0 + g) * (1.0 - band_dark * band * (1.0 - smoothstep(0.7, 0.95, n.y)));
	float side = smoothstep(side_fog.x, side_fog.y, abs(world_pos.x)) * side_fog.z;
	float low = smoothstep(low_fog.x, low_fog.y, -world_pos.y) * low_fog.z;
	ALBEDO = mix(c, background, max(f, max(side, low)));
}
"""

static var _scenes := {}
static var _mats := {}
static var _shaders := {}
static var _low := {}


static func _shader(kind: String) -> Shader:
	if not _shaders.has(kind):
		var sh := Shader.new()
		sh.code = (CLAY_SHADER if kind == "clay" else BUILDING_SHADER).replace("FADE_HEAD", Mats.fade_head()).replace("FADE_APPLY", Mats.FADE_APPLY)
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


static func building(far: bool = false) -> Material:
	var key := "building_far" if far else "building"
	if not _mats.has(key):
		var m := ShaderMaterial.new()
		m.shader = _shader("building")
		m.set_shader_parameter("colour", WorldPalette.BUILDING_STONE_FAR if far else WorldPalette.BUILDING_STONE)
		m.set_shader_parameter("background", WorldPalette.BG_BOTTOM)
		m.set_shader_parameter("fade", Quaternion(Mats.FADE_AHEAD_START, Mats.FADE_AHEAD_END, Mats.FADE_BEHIND_START, Mats.FADE_BEHIND_END))
		_mats[key] = m
	return _mats[key]


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


# ============================================================
# CHEAP COPIES (2026-09-21, GPU step 1b)
# ============================================================
# A gate is a row of up to 37 pillars and every one of them was the full
# 4 000-triangle model: 148 000 triangles of the 220 000 in frame at bar
# 11, and the phone is GPU-bound (28.7 ms a frame with the CPU using
# 2.5). Only the two pillars beside the opening are read as shapes -- the
# rest are a wall.
#
# Godot's own mesh LOD cannot do this here: generate_lods=true is on in
# the .import, but mesh LOD does not run in the Compatibility renderer,
# which is what the web build uses. So the cheap copy is built here, at
# load, FROM THE REAL MESH -- not modelled by hand and not guessed:
#
#   for each of `rings` heights, take the model's own vertices near that
#   height and find, for each of `sides` directions, how far the shape
#   reaches that way (the support distance). Intersecting neighbouring
#   directions gives one convex ring that hugs the real cross-section;
#   stacking the rings gives the real silhouette, faceted.
#
# The vertex colours come from the same vertices (the bake's colour is
# what the clay shader reads), so it keeps the model's own colouring and
# needs no new material -- nothing to add to prewarm.gd.
#
# 8 sides x 7 rings = 108 triangles against about 4 000. If the art is
# ever replaced this needs no attention: it is measured, not written down.
static func low_mesh(name: String, sides: int = 8, rings: int = 7) -> Mesh:
	var key := "%s_%d_%d" % [name, sides, rings]
	if _low.has(key):
		return _low[key]
	var src := mesh_of(name)
	if src == null or src.get_surface_count() == 0:
		_low[key] = null
		return null
	var arrays := src.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var cols: PackedColorArray = arrays[Mesh.ARRAY_COLOR] if arrays[Mesh.ARRAY_COLOR] != null else PackedColorArray()
	if verts.is_empty():
		_low[key] = null
		return null

	var y_lo := INF
	var y_hi := -INF
	for v in verts:
		y_lo = minf(y_lo, v.y)
		y_hi = maxf(y_hi, v.y)
	var span := maxf(y_hi - y_lo, 0.0001)

	# The directions the support is measured along.
	var dirs: Array[Vector2] = []
	for i in sides:
		var a := TAU * float(i) / float(sides)
		dirs.append(Vector2(cos(a), sin(a)))

	# ring -> polygon in xz, and the colour of the model around it.
	var ring_poly: Array = []
	var ring_col: Array = []
	for r in rings:
		var y := y_lo + span * float(r) / float(rings - 1)
		var window := span / float(rings - 1)
		var sup := PackedFloat32Array()
		sup.resize(sides)
		for i in sides:
			sup[i] = -INF
		var csum := Color(0, 0, 0, 0)
		var cn := 0
		for j in verts.size():
			var v := verts[j]
			if absf(v.y - y) > window:
				continue
			var xz := Vector2(v.x, v.z)
			for i in sides:
				sup[i] = maxf(sup[i], xz.dot(dirs[i]))
			if j < cols.size():
				csum += cols[j]
				cn += 1
		# A ring with nothing near it (a gap in the model): borrow the
		# one below rather than collapsing to a point.
		var empty := false
		for i in sides:
			if sup[i] == -INF:
				empty = true
		if empty and r > 0:
			ring_poly.append(ring_poly[r - 1].duplicate())
			ring_col.append(ring_col[r - 1])
			continue
		elif empty:
			for i in sides:
				sup[i] = 0.001
		var poly: Array[Vector3] = []
		for i in sides:
			var d0: Vector2 = dirs[i]
			var d1: Vector2 = dirs[(i + 1) % sides]
			# The corner where the two supporting lines meet.
			var det := d0.x * d1.y - d0.y * d1.x
			var p: Vector2
			if absf(det) < 0.0001:
				p = d0 * sup[i]
			else:
				p = Vector2((sup[i] * d1.y - sup[(i + 1) % sides] * d0.y) / det,
					(d0.x * sup[(i + 1) % sides] - d1.x * sup[i]) / det)
			poly.append(Vector3(p.x, y, p.y))
		ring_poly.append(poly)
		ring_col.append((csum / float(cn)) if cn > 0 else Color(1, 1, 1))

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Sides. Each triangle gets its own vertices, so generate_normals()
	# leaves the facets hard -- the same chiselled read as the model.
	for r in rings - 1:
		var lo: Array = ring_poly[r]
		var hi: Array = ring_poly[r + 1]
		var c_lo: Color = ring_col[r]
		var c_hi: Color = ring_col[r + 1]
		for i in sides:
			var j := (i + 1) % sides
			_tri(st, lo[i], lo[j], hi[j], c_lo, c_lo, c_hi)
			_tri(st, lo[i], hi[j], hi[i], c_lo, c_hi, c_hi)
	# Caps, as fans.
	var bot: Array = ring_poly[0]
	var top: Array = ring_poly[rings - 1]
	for i in range(1, sides - 1):
		_tri(st, bot[0], bot[i + 1], bot[i], ring_col[0], ring_col[0], ring_col[0])
		_tri(st, top[0], top[i], top[i + 1], ring_col[rings - 1], ring_col[rings - 1], ring_col[rings - 1])
	st.generate_normals()
	var m := st.commit()
	_low[key] = m
	return m


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, ca: Color, cb: Color, cc: Color) -> void:
	st.set_color(ca)
	st.add_vertex(a)
	st.set_color(cb)
	st.add_vertex(b)
	st.set_color(cc)
	st.add_vertex(c)


# make(), but with the cheap copy of the model. Same box, same pivot,
# same material, same node name (so tools/shot.gd's BUDGET lines still
# group it with the real ones).
static func make_low(name: String, size: Vector3, pivot: String, mat: Material, yaw_deg: float = 0.0, mirror_x: bool = false) -> Node3D:
	var mesh := low_mesh(name)
	if mesh == null:
		return make(name, size, pivot, mat, yaw_deg, mirror_x)
	var root := Node3D.new()
	root.name = name
	var mi := MeshInstance3D.new()
	# The MESH carries the name, not just the root: Godot renames a
	# colliding sibling to @Node3D@N, so a row of pillars keeps the name
	# on the first one only -- and tools/shot.gd's BUDGET walk (which
	# starts at the MeshInstance3D) then files the rest under "other".
	mi.name = name + "_low"
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var msize: Vector3 = size_of(name)
	var sc := Vector3(size.x / msize.x, size.y / msize.y, size.z / msize.z)
	if mirror_x:
		sc.x = -sc.x
	var b := Basis(Vector3.UP, deg_to_rad(MODELS[name][1] + yaw_deg)).scaled_local(sc)
	var pivot_y := -msize.y * 0.5 if pivot == "base" else msize.y * 0.5
	mi.transform = Transform3D(b, -(b * Vector3(0.0, pivot_y, 0.0)))
	root.add_child(mi)
	return root
