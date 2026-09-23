extends MultiMeshInstance3D
# ============================================================
# DROP SHADOWS (Phase A brief 6 section 2) — things sit on the floor.
#
# ONE draw call for every shadow in the world: a MultiMesh of soft dark
# quads lying just above the floor, one instance per thing that stands
# on or flies over the field -- the creature's body and both its feet,
# the gate and sweeper trains, slammers, orbiter pillars and orbs,
# volley orbs, notes. It replaced the blob the creature used to draw
# under itself (creature.gd's _ring), so the net cost is zero draw
# calls; what it costs is fill (transparent pixels), a fraction of a
# percent of the frame.
#
# The shadows OBEY THE LIGHT: a quad is offset from its caster along
# the light's direction on the floor by height x tan(light angle), and
# it grows and fades with height (MAX_ALPHA at contact, MIN_ALPHA at a
# jump's apex). That is a readability win, not decoration: a slammer's
# shadow tightening and darkening as it drops, a volley orb's running
# along the floor under it, say where the thing is in depth.
#
# Shape follows the caster's footprint: round for orbs, feet and the
# creature; a long rounded bar for a train of wall segments. A darker
# core under the contact point (a fake occlusion), a soft edge.
#
# A quad the exact size of the footprint is INVISIBLE: the caster stands
# on it and covers it (measured with the quads painted red: slivers at
# the pillars' feet, nothing under the creature, which draws on top of
# everything). So a shadow spreads SPREAD beyond the footprint, and is
# offset along the light by a share (SELF_OFFSET) of the caster's own
# height as well as by its height above the floor -- a tall thing's
# shadow leans away from the light, which is what makes it read as lit.
#
# No shadow where there is no floor (Field.floor_at): a quad never hangs
# over a pit. Hazard shadows follow the hazard nodes, which are posed
# from hazard_math for the song time -- so they hold during hit-stop and
# rewind with the song like everything else.
#
# HOW IT RUNS. Every frame, AFTER everything else has posed itself
# (process_priority), it asks each caster to cast (`cast_shadows(self)`
# on the creature and on every hazard in range) and the notes are read
# directly. Casters call cast_round() / cast_bar(); nothing is allocated
# per frame -- the instance buffer is CAP instances, and only the first
# `visible_instance_count` are drawn.
# ============================================================

const Mats := preload("res://prototype/flat_mats.gd")
const CameraRig := preload("res://prototype/camera_rig.gd")

const CAP := 160
const MAX_ALPHA := 0.55          # at contact
const MIN_ALPHA := 0.15          # at a jump's apex...
const APEX := 2.0                # ...which is this high (player3d.gd: WORLD_PER_PX is chosen for 2.0)
const GROW := 0.35               # the quad grows this much per unit of height
const SOFT := 0.45               # the soft edge, as a fraction of the half size (the old blob's softness)
const CORE := 0.35               # the darker core under a contact point
const SPREAD := 0.55             # a shadow is this much wider than the footprint (the soft part)
const SELF_OFFSET := 0.2         # of the caster's own height, cast along the light
const LIFT := 0.02               # above the floor, so it does not fight the tile's depth
# Casters further than this from the window's back edge cast nothing:
# the fade has taken their floor by then anyway.
const AHEAD := Mats.FADE_AHEAD_END
const BEHIND := Mats.FADE_BEHIND_END

# Unshaded, alpha-blended, distance-faded like the world. The shape is
# a signed distance in the quad's own UV: a segment of half length
# (1 - r) along local x with radius r (`r` = width / length, 1 = round).
const SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled, depth_draw_never;
uniform vec4 fill : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float soft = 0.45;
FADE_HEAD
varying vec4 inst;   // alpha, core, width / length, unused

void vertex() {
	world_z = (MODEL_MATRIX * vec4(VERTEX, 1.0)).z;
	fog_sy = screen_y_of(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	inst = INSTANCE_CUSTOM;
}

void fragment() {
	vec2 p = (UV - 0.5) * 2.0;
	float r = max(inst.z, 0.05);
	float h = 1.0 - r;
	float d = length(vec2(max(abs(p.x) - h, 0.0), p.y)) / r;
	float edge = 1.0 - smoothstep(1.0 - soft, 1.0, d);
	float core = 1.0 + inst.y * (1.0 - smoothstep(0.0, 0.55, d));
	float f = fade_amount();
	ALBEDO = fill.rgb;
	ALPHA = clamp(inst.x * edge * edge * core * (1.0 - f) * pr_light_on, 0.0, 1.0);
}
"""

static var _material: ShaderMaterial = null

var field: Node = null           # Field: hazards, notes, floor_at (null in the menu)
var creature: Node3D = null
var window_back := 0.0           # the window's back edge (the run sets it every frame)
var _n := 0
var _light := Vector3(0.0, 1.0, 0.0)


# The one material, for prewarm.gd as well: the web renderer compiles a
# shader the first time something using it is DRAWN, and a MultiMesh is
# its own variant of the pipeline, so the warm-up draws a MultiMesh too.
static func shadow_material() -> ShaderMaterial:
	if _material == null:
		var sh := Shader.new()
		sh.code = SHADER.replace("FADE_HEAD", Mats.fade_head())
		_material = ShaderMaterial.new()
		_material.shader = sh
		_material.render_priority = 9
		_material.set_shader_parameter("fill", Color(0.0, 0.0, 0.0, 1.0))
		_material.set_shader_parameter("soft", SOFT)
		_material.set_shader_parameter("fade", Quaternion(Mats.FADE_AHEAD_START, Mats.FADE_AHEAD_END, Mats.FADE_BEHIND_START, Mats.FADE_BEHIND_END))
	return _material


static func make_multimesh(count: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.orientation = PlaneMesh.FACE_Y
	mm.mesh = quad
	mm.instance_count = count
	mm.visible_instance_count = 0
	return mm


func _ready() -> void:
	multimesh = make_multimesh(CAP)
	material_override = shadow_material()
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	top_level = true
	# After every caster has posed itself this frame.
	process_priority = 100


func _process(_delta: float) -> void:
	_n = 0
	# The direction the scene published (camera_rig.gd) -- the same one
	# the shaders shade by, so a shadow lands where the tones say it should.
	_light = CameraRig.light_dir
	if creature != null and creature.has_method("cast_shadows"):
		creature.cast_shadows(self)
	if field != null:
		for h in field.hazards:
			var dz: float = h.position.z - window_back
			if dz < -BEHIND or dz > AHEAD:
				continue
			h.cast_shadows(self)
		for n in field.notes:
			if n["taken"]:
				continue
			var node: Node3D = n["node"]
			var dz: float = node.position.z - window_back
			if dz < -BEHIND or dz > AHEAD:
				continue
			cast_round(node.global_position, 0.0, 0.4, 0.8)
	multimesh.visible_instance_count = _n


# A round shadow under a thing whose base centre is `centre` and which
# is `height` tall, standing on a floor at height `floor_y`.
func cast_round(centre: Vector3, floor_y: float, radius: float, height: float) -> void:
	_cast(centre, floor_y, Vector2(radius, radius), 0.0, height)


# A rounded bar: half its length along its own x (turned `yaw` about the
# vertical), half its width across.
func cast_bar(centre: Vector3, floor_y: float, half_len: float, half_wid: float, height: float, yaw: float = 0.0) -> void:
	_cast(centre, floor_y, Vector2(half_len, half_wid), yaw, height)


func _cast(centre: Vector3, floor_y: float, half: Vector2, yaw: float, height: float) -> void:
	if _n >= CAP:
		return
	var h := maxf(centre.y - floor_y, 0.0)
	# Along the light, on the floor: a point `h` up casts h / tan(angle)
	# away from under itself; the caster's own height leans it further.
	var off := Vector2(-_light.x, -_light.z) / maxf(_light.y, 0.2) * (h + height * SELF_OFFSET)
	var x := centre.x + off.x
	var z := centre.z + off.y
	if field != null and not field.floor_at(x, z):
		return
	var u := clampf(h / APEX, 0.0, 1.0)
	var grow := (1.0 + SPREAD) * (1.0 + h * GROW)
	var alpha := lerpf(MAX_ALPHA, MIN_ALPHA, u)
	var core := CORE * (1.0 - u)
	var b := Basis(Vector3.UP, yaw).scaled(Vector3(half.x * 2.0 * grow, 1.0, half.y * 2.0 * grow))
	multimesh.set_instance_transform(_n, Transform3D(b, Vector3(x, floor_y + LIFT, z)))
	multimesh.set_instance_custom_data(_n, Color(alpha, core, minf(half.y, half.x) / maxf(half.x, half.y), 0.0))
	_n += 1
