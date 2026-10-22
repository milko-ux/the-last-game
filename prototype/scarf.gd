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
# ROUND 2 (2026-10-22, Milko: "it only looks okay, we need it looking
# great"). Round 1 read as a garden hose round the feet: a thin even
# tube, its stitches a zigzag along it, the ends flat strips seen edge-on
# and pointing behind the body. Now, as in the concept: a stuffed, lumpy
# band, higher at the back (the side the run camera sees) and lower at
# the front (under the eye), a bulge where it is knotted; chunky stitches
# whose columns run ALONG the band, as a real knitted scarf's do; wool
# fuzz on the edges that face away; one long wide end and a shorter one,
# streaming out to the camera's side (not at it: foreshortened to a stub)
# with their faces turned to it, lifted by the wind, and
# a fringe of tassels at the tips.
#
# The ends stream back while the creature runs and hang down when it
# stands: `flutter` 0..1, set by the creature from its speed; the ripple
# runs along them in the vertex shader (COLOR.r = how far along an end,
# 0 on the band; COLOR.g = how tucked against the body, for the shading).
# Lit like the creature (the one light) and drawn over the world with it
# (the same depth squeeze, on_top).
# ============================================================

const UNLOCK_M := 1000

# The creature's body as creature.gd places the model (HEIGHT 2.3),
# measured slice by slice from the mesh (2026-10-21): just under the eye
# (whose centre is 1.36 up) the body is round, centred 0.095 behind the
# feet, 0.945 in radius at 1.03 up and widening 0.25 per unit of height.
# (A fitted ellipsoid put the band low and wide: a hoop round the feet.)
const BODY_Z := -0.095
const BAND_Y := 0.72             # the centre at the front: under the eye (seen square-on its lower edge is near 0.92)
const BAND_RISE := 0.12          # the centre this much higher at the back, where the run camera looks
const BAND_HALF_H := 0.21
const BAND_HALF_T := 0.16        # stuffed: at 0.11 it read as a hose
const BAND_OUT := 0.0            # sits this far out from the body
const AROUND := 40
const ACROSS := 10
const KNOT_ANGLE := deg_to_rad(-125.0)   # from +z toward -x: back, on the camera's side
const KNOT_SPREAD := 0.4         # radians: how wide the knot's bulge is
# Stitches: rows along the band (each ~0.13 long), columns across it.
const ROWS_AROUND := 44.0
const COLS_ACROSS := 8.0
const STITCH := 0.13             # one row's length on the ends too
const COL_W := 0.15              # one column's width on the ends too
# The loose ends: length, width, fan (radians, outward), droop.
const ENDS := [[1.2, 0.46, 0.0, 0.0], [0.85, 0.38, 0.45, 0.12]]
const END_SEGS := 9
const END_FACE := deg_to_rad(55.0)   # the width turned this far up from flat: its face shows from above and from the side
const TASSELS := 5
const TASSEL_LEN := 0.16

const SHADER := """
shader_type spatial;
render_mode cull_disabled, fog_disabled;
uniform vec4 wool : source_color;
uniform float on_top = 0.92;
uniform float ambient = 0.55;
uniform float flutter = 0.0;
global uniform vec3 pr_sun_tint;
varying float along;
varying float tuck;

void vertex() {
	along = COLOR.r;
	tuck = COLOR.g;
	vec3 v = VERTEX;
	if (along > 0.0) {
		// Running: streaming out, lifted by the wind and rippling;
		// standing: hanging down the back.
		float wave = sin(TIME * 11.0 - along * 7.0) * 0.12 * along * flutter;
		v.y += wave + flutter * along * 0.3 - (1.0 - flutter) * along * along * 0.9;
		v.z += (1.0 - flutter) * along * 0.45;
		v.x += sin(TIME * 7.0 - along * 5.0) * 0.06 * along * flutter - (1.0 - flutter) * along * 0.65;
	}
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(v, 1.0);
	POSITION.z = mix(POSITION.z, POSITION.w, on_top);
}

void fragment() {
	// Chunky knit: UV.x counts rows along the scarf, UV.y columns across
	// it. Each column is a stack of V's: two rounded loops leaning in,
	// a groove down its middle and between columns.
	float cx = fract(UV.y);
	float ax = abs(cx - 0.5) * 2.0;
	float ph = fract(UV.x + ax * 0.6);
	float loop_ = sin(ph * 3.14159);
	float arm = smoothstep(0.0, 0.3, ax) * smoothstep(1.0, 0.78, ax);
	float knit = mix(0.7, 1.0, loop_ * arm);
	knit *= 0.94 + 0.06 * sin((ph * 2.0 + ax) * 18.85);   // the ply of the yarn
	vec3 c = wool.rgb * knit * mix(1.0, 0.8, tuck);
	// Wool fuzz: edges turned away from the eye catch the light.
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	c = mix(c, wool.rgb * 1.35, rim * 0.45 * (1.0 - tuck));
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


# How close an angle is to the knot: 1 on it, 0 a spread away.
static func _knot(a: float) -> float:
	var d := wrapf(a - KNOT_ANGLE, -PI, PI)
	return exp(-(d * d) / (KNOT_SPREAD * KNOT_SPREAD))


# The band's centre height at an angle: low at the front, high at the back.
static func _band_y(a: float) -> float:
	return BAND_Y + BAND_RISE * (1.0 - cos(a)) * 0.5


# How stuffed the band is at an angle: lumpy, and fat at the knot.
static func _band_t(a: float) -> float:
	return BAND_HALF_T * (1.0 + 0.1 * sin(3.0 * a + 0.7) + 0.06 * sin(8.0 * a + 2.1) + 0.55 * _knot(a))


# Where the band runs at an angle (from +z toward -x), out from the body.
static func _band_point(a: float, dy: float, out: float) -> Vector3:
	var y := _band_y(a) + dy
	var r := 0.945 + (y - 1.03) * 0.25 + out
	return Vector3(-sin(a) * r, y, cos(a) * r + BODY_Z)


static func build_mesh() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# The band: a tube around the body, AROUND x ACROSS quads; its section
	# is stuffed (lumpy, fat at the knot) and taller at the knot.
	var ring := []
	for i in AROUND + 1:
		var a := TAU * float(i) / AROUND
		var half_t := _band_t(a)
		var half_h := BAND_HALF_H * (1.0 + 0.25 * _knot(a))
		var centre := _band_point(a, 0.0, BAND_OUT + half_t)
		var row := []
		for j in ACROSS + 1:
			var t := TAU * float(j) / ACROSS
			var p := _band_point(a, sin(t) * half_h, BAND_OUT + half_t + cos(t) * half_t)
			var tuck := smoothstep(-0.2, -0.9, cos(t))   # the side against the body
			row.append([p, (p - centre).normalized(), Vector2(float(i) / AROUND * ROWS_AROUND, float(j) / ACROSS * COLS_ACROSS), tuck])
		ring.append(row)
	for i in AROUND:
		for j in ACROSS:
			_quad(st, ring[i][j], ring[i + 1][j], ring[i + 1][j + 1], ring[i][j + 1], 0.0, 0.0)
	# The loose ends: wide strips from the knot, streaming back and out to
	# the camera's side, the width turned up so the face shows; tapering a
	# little, with a fringe of tassels at the tip.
	var knot := _band_point(KNOT_ANGLE, 0.0, BAND_OUT + _band_t(KNOT_ANGLE) * 2.0)
	for e in ENDS:
		var length: float = e[0]
		var half_w: float = e[1] * 0.5
		var dir := Vector3(0.9, -0.1 - float(e[3]), -0.85).normalized().rotated(Vector3.UP, -float(e[2]))
		var flat := dir.cross(Vector3.UP).normalized()
		var side := (flat * cos(END_FACE) + Vector3.UP * sin(END_FACE)).normalized()
		var n := dir.cross(side).normalized()
		if n.y < 0.0:
			n = -n
		var cols: float = float(e[1]) / COL_W
		var prev := []
		var tip_l := Vector3.ZERO
		var tip_r := Vector3.ZERO
		for s in END_SEGS + 1:
			var u := float(s) / END_SEGS
			var c := knot + dir * length * u
			var w := half_w * (1.0 - 0.2 * u) * (0.55 + 0.45 * minf(u * 4.0, 1.0))   # gathered at the knot
			var rows := u * length / STITCH
			var l := [c - side * w, n, Vector2(rows, 0.0), 0.0]
			var r := [c + side * w, n, Vector2(rows, cols), 0.0]
			if s > 0:
				_quad(st, prev[0], l, r, prev[1], float(s - 1) / END_SEGS, u)
			prev = [l, r]
			tip_l = l[0]
			tip_r = r[0]
		# The fringe: TASSELS thin strips off the tip, each a little longer
		# or shorter, so the edge is not a ruler line.
		for k in TASSELS:
			var f0 := (float(k) + 0.15) / TASSELS
			var f1 := (float(k) + 0.85) / TASSELS
			var a0 := tip_l.lerp(tip_r, f0)
			var a1 := tip_l.lerp(tip_r, f1)
			var reach := dir * TASSEL_LEN * (0.8 + 0.4 * fposmod(float(k) * 0.618, 1.0))
			var along_tip := 1.0 + TASSEL_LEN / length
			var rows0 := length / STITCH
			_quad(st, [a0, n, Vector2(rows0, 0.0), 0.0], [a0 + reach, n, Vector2(rows0 + 1.0, 0.0), 0.0],
				[a1 + reach, n, Vector2(rows0 + 1.0, 0.5), 0.0], [a1, n, Vector2(rows0, 0.5), 0.0], 1.0, along_tip)
	_mesh = st.commit()
	return _mesh


# One quad as two triangles; `a0` / `a1` are how far along a loose end
# its first and second edge are (0 on the band). A point is
# [position, normal, uv, tuck].
static func _quad(st: SurfaceTool, p0: Array, p1: Array, p2: Array, p3: Array, a0: float, a1: float) -> void:
	for v in [[p0, a0], [p1, a1], [p2, a1], [p0, a0], [p2, a1], [p3, a0]]:
		var pt: Array = v[0]
		st.set_color(Color(float(v[1]), float(pt[3]), 0.0))
		st.set_normal(pt[1])
		st.set_uv(pt[2])
		st.add_vertex(pt[0])
