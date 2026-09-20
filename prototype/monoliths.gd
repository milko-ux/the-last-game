extends Node3D
# ============================================================
# MONOLITHS — brutalist slabs around the field (brief 2 section 3).
# Silhouettes only: one BoxMesh drawn many times through a MultiMesh,
# so the whole level's monoliths are ONE draw call. Placed
# deterministically per bar from a seeded generator, so the same level
# looks the same on every device. They sit in the world (z is time,
# like everything else) and take the same distance fade as the field,
# so the ones ahead dissolve into the background exactly like it does.
#
# Per instance: the transform (position, yaw, tilt, width/depth/height)
# and a custom colour whose r = taper (top face scale 0.7-1.0, applied
# in the shader to the vertices above the middle) and g = 1 for the far,
# huge ones (MONOLITH_FAR).
# ============================================================

const Mats := preload("res://prototype/flat_mats.gd")
const Rules := preload("res://prototype/rules.gd")
const Props := preload("res://prototype/props/props.gd")

# Brief 4: the boxes became the two building models (tall 60 %, stacked
# 40 %; the far, huge ones are always the tall one), one MultiMesh per
# model = two draw calls for the level. Same seeded placement, scale,
# tilt and taper as before; the unit box became a 1.9-tall model, so
# the instance scale divides by the model's size.
const TALL_SHARE := 0.6
const CHUNK_BARS := 4
var _chunks: Array = []

# Placement (all in world units; a bar is 8 long, the field 18 wide).
const PER_SIDE_MIN := 1
const PER_SIDE_MAX := 3
const GAP_MIN := 3.0             # from the field edge
const GAP_MAX := 14.0
const GAP_MIN_RIGHT := 4.0       # the near-right corner sits by the bottom of the screen
const WIDTH_MIN := 3.0
const WIDTH_MAX := 8.0
const HEIGHT_MIN := 10.0
const HEIGHT_MAX := 40.0
const BASE_Y := -22.0            # tops land between -12 and +18, around the slab
const TILT_MAX_DEG := 6.0
const TAPER_CHANCE := 0.5        # of the rest, top face scaled 0.7-0.9
const STACK_CHANCE := 0.18       # a second block on top, offset
const FAR_EVERY := 6             # 1 in 6 bars gets one far, huge slab
const FAR_GAP_MIN := 20.0
const FAR_GAP_MAX := 30.0
const FAR_WIDTH := Vector2(10.0, 18.0)
const FAR_HEIGHT := Vector2(40.0, 60.0)
const FAR_BASE_Y := -30.0
const TOP_LIGHTER := 0.12        # top faces 12 % lighter than the sides (two-tone)

const SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled;
uniform vec3 colour : source_color;
uniform vec3 colour_far : source_color;
uniform float top_lighter = 0.12;   // top faces this much lighter: a block, not a silhouette
uniform float grain_amount = 0.08;  // triplanar grain, +-8 % at 1.5 units
uniform float grain_scale = 1.5;
uniform float coarse_amount = 0.04; // +-4 % at 5 units so big faces are not flat
uniform float coarse_scale = 5.0;
uniform float band_every = 2.5;     // formwork lines: every 2.5 units of height...
uniform float band_width = 0.05;    // ...0.05 wide...
uniform float band_dark = 0.02;     // ...2 % darker
uniform float foot_band = 0.3;      // contact shadow this high above the bottom
uniform float foot_dark = 0.25;
FADE_HEAD
varying float is_top;
varying vec3 world_pos;
varying vec3 world_n;
varying float local_y;              // -0.5 (bottom) .. 0.5 (top) of the unit box
varying float height;

void vertex() {
	// Taper: the top half of the box narrows to INSTANCE_CUSTOM.r of its width.
	float taper = INSTANCE_CUSTOM.r;
	if (VERTEX.y > 0.0) {
		VERTEX.xz *= taper;
	}
	vec4 wp = MODEL_MATRIX * vec4(VERTEX, 1.0);
	world_z = wp.z;
	world_pos = wp.xyz;
	world_n = normalize(mat3(MODEL_MATRIX) * NORMAL);
	local_y = VERTEX.y;
	height = length(MODEL_MATRIX[1].xyz);
	COLOR = INSTANCE_CUSTOM;
	is_top = NORMAL.y > 0.5 ? 1.0 : 0.0;
}

// Triplanar: blend the noise sampled on the three axis planes by the normal.
float triplanar(vec3 p, vec3 n, float scale) {
	vec3 w = abs(n);
	w /= (w.x + w.y + w.z);
	return grain(vec3(p.y, p.z, 0.0), scale) * w.x + grain(vec3(p.x, p.z, 1.7), scale) * w.y + grain(vec3(p.x, p.y, 3.1), scale) * w.z;
}

void fragment() {
	vec3 c = mix(colour, colour_far, COLOR.g) * (1.0 + top_lighter * is_top);
	// Concrete: fine triplanar grain, a coarse variation, faint formwork lines.
	float g = triplanar(world_pos, world_n, grain_scale) * grain_amount + triplanar(world_pos, world_n, coarse_scale) * coarse_amount;
	float band = 1.0 - smoothstep(band_width * 0.5, band_width, abs(fract(world_pos.y / band_every) - 0.5) * band_every);
	c *= (1.0 + g) * (1.0 - band_dark * band * (1.0 - is_top));
	// Contact shadow where the block meets the fog below.
	float foot = 1.0 - smoothstep(0.0, foot_band, (local_y + 0.5) * height);
	c *= 1.0 - foot_dark * foot;
	ALBEDO = c;
FADE_APPLY
}
"""

var _xforms: Array[Transform3D] = []
var _customs: Array[Color] = []
var _kinds: Array[String] = []


func build(z_from: float, z_to: float) -> void:
	_xforms.clear()
	_customs.clear()
	_kinds.clear()
	var rng := RandomNumberGenerator.new()
	var bar := 0
	var z := z_from
	while z < z_to:
		rng.seed = hash("monoliths-%d-%d" % [Rules.LEVEL, bar])
		for side: float in [-1.0, 1.0]:
			var n := rng.randi_range(PER_SIDE_MIN, PER_SIDE_MAX)
			for i in n:
				var gap := rng.randf_range(GAP_MIN_RIGHT if side < 0.0 else GAP_MIN, GAP_MAX)
				var w := rng.randf_range(WIDTH_MIN, WIDTH_MAX)
				var d := rng.randf_range(WIDTH_MIN, WIDTH_MAX)
				var h := rng.randf_range(HEIGHT_MIN, HEIGHT_MAX)
				var x: float = side * (Rules.half_width() + gap + w * 0.5)
				var zz := z + rng.randf_range(0.0, BeatClock.BAR_UNITS)
				_add(rng, Vector3(x, BASE_Y, zz), Vector3(w, h, d), false)
		if bar % FAR_EVERY == FAR_EVERY - 1:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			var w := rng.randf_range(FAR_WIDTH.x, FAR_WIDTH.y)
			var d := rng.randf_range(FAR_WIDTH.x, FAR_WIDTH.y)
			var h := rng.randf_range(FAR_HEIGHT.x, FAR_HEIGHT.y)
			var x: float = side * (Rules.half_width() + rng.randf_range(FAR_GAP_MIN, FAR_GAP_MAX) + w * 0.5)
			_add(rng, Vector3(x, FAR_BASE_Y, z + rng.randf_range(0.0, BeatClock.BAR_UNITS)), Vector3(w, h, d), true)
		z += BeatClock.BAR_UNITS
		bar += 1

	# Chunks of CHUNK_BARS bars, one MultiMesh per model per chunk, switched
	# on only near the window (brief 4's budget: the whole level's ~330
	# buildings must not be submitted every frame).
	var n_chunks := ceili((z_to - z_from) / (CHUNK_BARS * BeatClock.BAR_UNITS))
	for c in n_chunks:
		var c_z0 := z_from + c * CHUNK_BARS * BeatClock.BAR_UNITS
		var c_z1 := c_z0 + CHUNK_BARS * BeatClock.BAR_UNITS
		var holder := Node3D.new()
		holder.set_meta("z0", c_z0)
		holder.set_meta("z1", c_z1)
		for kind in ["building_tall", "building_stacked"]:
			var idx := []
			for i in _xforms.size():
				if _kinds[i] == kind and _xforms[i].origin.z >= c_z0 and _xforms[i].origin.z < c_z1:
					idx.append(i)
			if idx.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_custom_data = true
			# With use_colors off the per-instance colour multiplies the mesh's
			# vertex colour by ZERO in the web renderer; on, and white, it passes.
			mm.use_colors = true
			mm.mesh = Props.mesh_of(kind)
			mm.instance_count = idx.size()
			var msize: Vector3 = Props.size_of(kind)
			for j in idx.size():
				var x: Transform3D = _xforms[idx[j]]
				# The transform was built for a unit box: divide by the model's size.
				x.basis = x.basis.scaled_local(Vector3(1.0 / msize.x, 1.0 / msize.y, 1.0 / msize.z))
				mm.set_instance_transform(j, x)
				mm.set_instance_color(j, Color.WHITE)
				mm.set_instance_custom_data(j, _customs[idx[j]])
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = Props.building()
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.extra_cull_margin = 256.0
			holder.add_child(mmi)
		add_child(holder)
		_chunks.append(holder)


# Called with the window's back edge every frame: only the chunks within
# the fade range (plus a margin) are drawn.
func set_window(z_back: float) -> void:
	var lo := z_back - Mats.FADE_BEHIND_END - 4.0
	var hi := z_back + Mats.FADE_AHEAD_END + 8.0
	for h in _chunks:
		var on: bool = float(h.get_meta("z1")) >= lo and float(h.get_meta("z0")) <= hi
		if on != h.visible:
			h.visible = on
			if FrameMeter.active:
				FrameMeter.note("building chunk " + ("on" if on else "off"))


# One slab (plus, sometimes, a second one stacked on it with an offset).
func _add(rng: RandomNumberGenerator, base: Vector3, size: Vector3, far: bool) -> void:
	var taper := 1.0
	if not far and rng.randf() < TAPER_CHANCE:
		taper = rng.randf_range(0.7, 0.9)
	var tilt := deg_to_rad(rng.randf_range(-TILT_MAX_DEG, TILT_MAX_DEG))
	var yaw := rng.randf_range(-0.25, 0.25)
	var b := Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, tilt)
	b = b.scaled_local(size)
	# The unit box is centred; lift it so its bottom sits at base.y.
	var centre := base + Vector3(0.0, size.y * 0.5, 0.0)
	_xforms.append(Transform3D(b, centre))
	_customs.append(Color(taper, 1.0 if far else 0.0, 0.0, 1.0))
	_kinds.append("building_tall" if far or rng.randf() < TALL_SHARE else "building_stacked")
	if not far and rng.randf() < STACK_CHANCE:
		var top_size := Vector3(size.x * rng.randf_range(0.5, 0.8), rng.randf_range(4.0, 12.0), size.z * rng.randf_range(0.5, 0.8))
		var off := Vector3(rng.randf_range(-0.2, 0.2) * size.x, 0.0, rng.randf_range(-0.2, 0.2) * size.z)
		var tb := Basis(Vector3.UP, yaw + rng.randf_range(-0.2, 0.2)).scaled_local(top_size)
		_xforms.append(Transform3D(tb, base + off + Vector3(0.0, size.y * taper + top_size.y * 0.5 - 0.3, 0.0)))
		_customs.append(Color(1.0, 0.0, 0.0, 1.0))
		_kinds.append("building_stacked")
