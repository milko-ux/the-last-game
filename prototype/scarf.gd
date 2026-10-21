extends MeshInstance3D
# ============================================================
# THE SCARF (2026-10-21) — the first thing a player earns: reach
# UNLOCK_M in one run and the creature wears it from then on. Milko:
# "C for the hero and keep the scarf for reaching 1 km ... show the
# character with scarf at the menu so people understand that its coming
# if they keep playing" (concept: docs/concept/hero/D_white_scarf.jpg).
# Outfits for sale come later (the roadmap's step 7); this is the slot
# they will use.
#
# Built here, no model file: a knitted band around the body just under
# the eye, a knot at the back on the side the camera sees, and two loose
# ends. One mesh, one material. A child of the creature node (creature.gd
# wear_scarf), so it takes every spin, squash and lean of the pose; in
# the creature's frame the feet are the origin, +y up, +z the eye's way.
#
# The ends stream straight back while the creature runs and hang down
# when it stands: `flutter` 0..1, set by the creature from its speed;
# the ripple runs along them in the vertex shader (COLOR.r = how far
# along an end, 0 on the band). Lit like the creature (the one light)
# and drawn over the world with it (the same depth squeeze, on_top).
# ============================================================

const UNLOCK_M := 1000

# The creature's body as creature.gd places the model (HEIGHT 2.3),
# measured slice by slice from the mesh (2026-10-21): just under the eye
# (whose centre is 1.36 up) the body is round, centred 0.095 behind the
# feet, 0.945 in radius at 1.03 up and widening 0.25 per unit of height.
# (A fitted ellipsoid put the band low and wide: a hoop round the feet.)
const BODY_Z := -0.095
const BAND_Y := 0.7              # under the eye (seen square-on its lower edge is near 0.92); over the flippers' roots, as in the concept
const BAND_HALF_H := 0.19            # chunky: at 0.13 it read as a cord
const BAND_HALF_T := 0.11
const BAND_OUT := 0.02            # sits this far out from the body
const AROUND := 28
const ACROSS := 8
const KNOT_ANGLE := deg_to_rad(-125.0)   # from +z toward -x: back, on the camera's side
const ENDS := [[0.95, 0.22, 0.0], [0.7, 0.2, 0.35]]   # length, width, fan (radians) of the two loose ends
const END_SEGS := 7

const SHADER := """
shader_type spatial;
render_mode cull_disabled, fog_disabled;
uniform vec4 wool : source_color;
uniform float on_top = 0.92;
uniform float ambient = 0.55;
uniform float flutter = 0.0;
global uniform vec3 pr_sun_tint;
varying float along;

void vertex() {
	along = COLOR.r;
	vec3 v = VERTEX;
	if (along > 0.0) {
		// Running: streaming back and rippling; standing: hanging down.
		float wave = sin(TIME * 11.0 - along * 7.0) * 0.09 * along * flutter;
		v.y += wave - (1.0 - flutter) * along * along * 0.75;
		v.z += (1.0 - flutter) * along * 0.45;
		v.x += sin(TIME * 7.0 - along * 5.0) * 0.04 * along * flutter;
	}
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(v, 1.0);
	POSITION.z = mix(POSITION.z, POSITION.w, on_top);
}

void fragment() {
	// Knit: columns of stitches around the band, each a soft V.
	float col = fract(UV.x * 34.0);
	float stitch = fract(UV.y * 5.0 + abs(col - 0.5) * 1.2);
	float knit = 0.82 + 0.18 * smoothstep(0.0, 0.35, stitch) * smoothstep(1.0, 0.65, stitch);
	knit *= 0.92 + 0.08 * smoothstep(0.1, 0.5, abs(col - 0.5) * 2.0);
	vec3 c = wool.rgb * knit;
	ALBEDO = c;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
	// The darker the time of day, the more it holds its own colour.
	float dark = clamp(1.0 - dot(pr_sun_tint, vec3(0.299, 0.587, 0.114)), 0.0, 1.0);
	EMISSION = c * (ambient + dark * 0.4);
}
"""

static var _mesh: ArrayMesh = null
static var _material: ShaderMaterial = null


func _init() -> void:
	mesh = build_mesh()
	material_override = material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func set_flutter(f: float) -> void:
	material_override.set_shader_parameter("flutter", f)


static func material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER
		_material = ShaderMaterial.new()
		_material.shader = sh
		_material.render_priority = 11           # the creature is 10
		_material.set_shader_parameter("wool", WorldPalette.SCARF)
	return _material


# Where the band runs at an angle (from +z toward -x), out from the body.
static func _band_point(a: float, dy: float, out: float) -> Vector3:
	var y := BAND_Y + dy
	var r := 0.945 + (y - 1.03) * 0.25 + out
	return Vector3(-sin(a) * r, y, cos(a) * r + BODY_Z)


static func build_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The band: a tube of elliptical section, AROUND x ACROSS quads.
	var ring := []
	for i in AROUND + 1:
		var a := TAU * float(i) / AROUND
		var row := []
		for j in ACROSS + 1:
			var t := TAU * float(j) / ACROSS
			var p := _band_point(a, sin(t) * BAND_HALF_H, BAND_OUT + BAND_HALF_T + cos(t) * BAND_HALF_T)
			var centre := _band_point(a, 0.0, BAND_OUT + BAND_HALF_T)
			row.append([p, (p - centre).normalized(), Vector2(float(i) / AROUND, float(j) / ACROSS)])
		ring.append(row)
	for i in AROUND:
		for j in ACROSS:
			_quad(st, ring[i][j], ring[i + 1][j], ring[i + 1][j + 1], ring[i][j + 1], 0.0, 0.0)
	# The loose ends: flat strips from the knot, streaming back (-z) and a
	# little down, each fanned a little.
	var knot := _band_point(KNOT_ANGLE, -0.02, BAND_OUT + BAND_HALF_T * 2.0)
	for e in ENDS:
		var length: float = e[0]
		var half_w: float = e[1] * 0.5
		var fan: float = e[2]
		var dir := Vector3(-0.35 - fan, -0.25, -1.0).normalized()
		var side := dir.cross(Vector3.UP).normalized()
		var prev := []
		for s in END_SEGS + 1:
			var u := float(s) / END_SEGS
			var c := knot + dir * length * u
			var w := half_w * (1.0 - 0.25 * u)
			var l := [c - side * w, Vector3.UP, Vector2(u, 0.0)]
			var r := [c + side * w, Vector3.UP, Vector2(u, 1.0)]
			if s > 0:
				_quad(st, prev[0], l, r, prev[1], float(s - 1) / END_SEGS, u)
			prev = [l, r]
	_mesh = st.commit()
	return _mesh


# One quad as two triangles; `a0` / `a1` are how far along a loose end
# its first and second edge are (0 on the band).
static func _quad(st: SurfaceTool, p0: Array, p1: Array, p2: Array, p3: Array, a0: float, a1: float) -> void:
	for v in [[p0, a0], [p1, a1], [p2, a1], [p0, a0], [p2, a1], [p3, a0]]:
		var pt: Array = v[0]
		st.set_color(Color(float(v[1]), 0.0, 0.0))
		st.set_normal(pt[1])
		st.set_uv(pt[2])
		st.add_vertex(pt[0])
