extends RefCounted
# ============================================================
# TIME OF DAY (2026-10-21) — the canyon's day passes as the run goes
# further: morning, the sun going down, night, and dawn again. Milko: "the
# sunrise to a sunset and eventually the character is running at night
# ... the days need to pass a bit faster just so that the user can see
# that something is happening the further they run".
#
# Driven by the run's DISTANCE (track_test.distance_m, the HUD's metres:
# the furthest point reached, so a death and its rewind never turn the
# clock back). Along one day of CYCLE_M metres, KEYS says which time of
# day holds where; between two keys the sets blend (smoothstep). The sets
# themselves are colours, so they live in WorldPalette.TIMES.
#
# What one blend paints, all of it uniforms (no material is rebuilt, no
# new shader): the fog stops and the scenery's light and shade colours
# (global uniforms, every world shader), the backdrop's sky, sun, cliffs
# and clouds (camera_rig.backdrop), the drop shadows' colour, and the
# CreatureLight. Published only when the blend has moved.
#
# `forced` holds one time of day still: the look switch ("sunset",
# "night": looks.gd) and the web's ?time=sunset, for judging a time of day
# without running to it.
# ============================================================

const Mats := preload("res://prototype/flat_mats.gd")
const Shadows := preload("res://prototype/shadows.gd")
const CameraRig := preload("res://prototype/camera_rig.gd")

const CYCLE_M := 950.0
# [metres into the day, the time of day held there]: morning to 150 m,
# the sun going down until it has set at 300, sunset to 420, dusk to full
# night at 560, night to 800, dawn back to morning at 950.
const KEYS := [[0.0, "morning"], [150.0, "morning"], [300.0, "sunset"], [420.0, "sunset"],
	[560.0, "night"], [800.0, "night"], [950.0, "morning"]]

static var forced := ""
static var light: DirectionalLight3D = null     # the scene's CreatureLight (the scene sets it)
static var _last := -1.0


# Paint the world for this distance (cheap when nothing moved).
static func update(metres: float) -> void:
	var at := fposmod(metres, CYCLE_M)
	if forced != "":
		at = _held_at(forced)
	if absf(at - _last) < 0.25:
		return
	_last = at
	_publish(blend(at))


# The next update paints, whatever moved (a look switch, a new scene).
static func reset() -> void:
	_last = -1.0


# Where along the day a time of day is held (its first key).
static func _held_at(name: String) -> float:
	for k in KEYS:
		if k[1] == name:
			return float(k[0])
	return 0.0


# The blended set at a point along the day.
static func blend(at: float) -> Dictionary:
	for i in KEYS.size() - 1:
		var a: Array = KEYS[i]
		var b: Array = KEYS[i + 1]
		if at <= float(b[0]):
			var u := smoothstep(float(a[0]), float(b[0]), at)
			return _mix(WorldPalette.TIMES[a[1]], WorldPalette.TIMES[b[1]], u)
	return WorldPalette.TIMES[KEYS[-1][1]]


static func _mix(a: Dictionary, b: Dictionary, u: float) -> Dictionary:
	var out := {}
	for k in a:
		var x = a[k]
		var y = b[k]
		if x is Array:
			var arr := []
			for i in x.size():
				arr.append((x[i] as Color).lerp(y[i], u))
			out[k] = arr
		else:
			out[k] = lerp(x, y, u)
	return out


static func _publish(d: Dictionary) -> void:
	Mats.publish_fog(d["fog"], Mats.LOW_FOG_MAX)
	var st: Color = d["sun_tint"]
	var sh: Color = d["shade_tint"]
	RenderingServer.global_shader_parameter_set("pr_sun_tint", Vector3(st.r, st.g, st.b))
	RenderingServer.global_shader_parameter_set("pr_shade_tint", Vector3(sh.r, sh.g, sh.b))
	if CameraRig.backdrop != null:
		for k in ["sky_top", "sky_horizon", "sun", "sun_glow", "sun_pos", "cliff_far", "cliff_near", "cloud_lit", "cloud_shade", "night"]:
			CameraRig.backdrop.set_shader_parameter(k, d[k])
	Shadows.shadow_material().set_shader_parameter("fill", d["shadow"])
	if light != null and is_instance_valid(light):
		light.light_color = d["light_colour"]
		light.light_energy = d["light_energy"]
