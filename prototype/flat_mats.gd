extends RefCounted
# ============================================================
# FLAT MATERIALS — the entire Phase R look. Unlit, flat, no glow.
# Colours come from Palette so the meaning is unchanged:
#   magenta = will kill you, cyan = safe surface, amber = goal.
# Materials are cached so the whole track shares a handful.
# ============================================================

static var _cache := {}


static func flat(c: Color) -> StandardMaterial3D:
	var key := c.to_html()
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = c
		_cache[key] = m
	return _cache[key]


static func magenta() -> StandardMaterial3D:
	return flat(Palette.HAZ)


# Dormant hazard state: still clearly magenta, clearly "not yet".
static func magenta_dim() -> StandardMaterial3D:
	return flat(Palette.HAZ.darkened(0.62))


# Slightly under full cyan so the magenta stays the loudest thing on screen.
static func cyan() -> StandardMaterial3D:
	return flat(Palette.EDGE.darkened(0.42))


# Walls (sweepers, gates): see-through so a wall between the camera and
# the player can never hide the player or the floor behind it.
static func magenta_wall() -> StandardMaterial3D:
	var key := "wall"
	if not _cache.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		m.albedo_color = Color(Palette.HAZ.r, Palette.HAZ.g, Palette.HAZ.b, 0.55)
		_cache[key] = m
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


static func amber() -> StandardMaterial3D:
	return flat(Palette.GOAL)


static func amber_dim() -> StandardMaterial3D:
	return flat(Palette.GOAL.darkened(0.55))


static func white() -> StandardMaterial3D:
	return flat(Color.WHITE)
