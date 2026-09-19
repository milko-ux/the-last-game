extends MultiMeshInstance3D
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

const SHADER := """
shader_type spatial;
render_mode unshaded, fog_disabled;
uniform vec3 colour : source_color;
uniform vec3 colour_far : source_color;
FADE_HEAD

void vertex() {
	// Taper: the top half of the box narrows to INSTANCE_CUSTOM.r of its width.
	float taper = INSTANCE_CUSTOM.r;
	if (VERTEX.y > 0.0) {
		VERTEX.xz *= taper;
	}
	world_z = (MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
	COLOR = INSTANCE_CUSTOM;
}

void fragment() {
	ALBEDO = mix(colour, colour_far, COLOR.g);
FADE_APPLY
}
"""

var _xforms: Array[Transform3D] = []
var _customs: Array[Color] = []


func build(z_from: float, z_to: float) -> void:
	_xforms.clear()
	_customs.clear()
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

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	mm.mesh = box
	mm.instance_count = _xforms.size()
	for i in _xforms.size():
		mm.set_instance_transform(i, _xforms[i])
		mm.set_instance_custom_data(i, _customs[i])
	multimesh = mm
	var sh := Shader.new()
	sh.code = SHADER.replace("FADE_HEAD", Mats.FADE_HEAD).replace("FADE_APPLY", Mats.FADE_APPLY)
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("colour", WorldPalette.MONOLITH)
	m.set_shader_parameter("colour_far", WorldPalette.MONOLITH_FAR)
	m.set_shader_parameter("background", WorldPalette.BG_BOTTOM)
	m.set_shader_parameter("fade", Quaternion(Mats.FADE_AHEAD_START, Mats.FADE_AHEAD_END, Mats.FADE_BEHIND_START, Mats.FADE_BEHIND_END))
	material_override = m
	# Never frustum-culled away as one unit: its box spans the whole level.
	extra_cull_margin = 16384.0


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
	if not far and rng.randf() < STACK_CHANCE:
		var top_size := Vector3(size.x * rng.randf_range(0.5, 0.8), rng.randf_range(4.0, 12.0), size.z * rng.randf_range(0.5, 0.8))
		var off := Vector3(rng.randf_range(-0.2, 0.2) * size.x, 0.0, rng.randf_range(-0.2, 0.2) * size.z)
		var tb := Basis(Vector3.UP, yaw + rng.randf_range(-0.2, 0.2)).scaled_local(top_size)
		_xforms.append(Transform3D(tb, base + off + Vector3(0.0, size.y * taper + top_size.y * 0.5 - 0.3, 0.0)))
		_customs.append(Color(1.0, 0.0, 0.0, 1.0))
