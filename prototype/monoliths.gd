extends Node3D
# ============================================================
# MONOLITHS -- the mesas around the field. THE CANYON (step 3 brief 2
# section 3, 2026-10-21; concept D): pastel stone mesas rise out of the
# cloud sea on both sides, in three bands:
#
#   near   beside the slab; the tallest, a few tops above the runway
#   mid    further out, tops below the runway
#   far    out in the haze, tops well below: from this camera, which
#          looks steeply down, you see them from above, sunlit tops
#          standing in the clouds
#
# Their feet are far down in the clouds (BASE_Y; the height fog takes
# them). Tops below the runway are the point: the camera cannot show a
# top much above it (tools/pillar_frame.gd measured it in step 3 brief 1),
# so a mesa you look down on is a whole mesa.
#
# Each band of each 64-unit strip is ONE mesh -- one draw call however
# many mesas -- merged from the kit (tools/blender/mesas.py,
# assets/models/mesas/: six faceted pieces of 49-114 triangles). Every
# mesa gets its colour (WorldPalette.MESAS) and whether its top is grassy
# in the vertex colour, and a turn about the vertical: the light is not
# baked any more, so any turn is lit right. (Before the canyon: three
# bands of dark carved pillars from a baked kit.)
#
# Placed deterministically per bar from a seeded generator, so the same
# level looks the same on every device. z is time, like everything else.
# ============================================================

const Mats := preload("res://prototype/flat_mats.gd")
const Rules := preload("res://prototype/rules.gd")
const Props := preload("res://prototype/props/props.gd")

const STRIP := 64.0              # one merged mesh per band per this much z
const BASE_Y := -46.0            # feet deep in the clouds: the height fog dissolves them
# Per band: the gap from the field's edge to the mesa's near face, where
# its top is (world y, the runway is 0), the chance of one per side per
# 8-unit bar (broad mesas need air between them: at one or two a bar the
# canyon was a forest and hid the clouds), and how broad (x / z scale on top of the uniform one: the pieces
# are ~1.9 wide and 8 tall, so a mesa 50 tall is ~12 wide at 1.0; at
# 0.5-1.0 they read as crystal pencils, not mesas).
const BANDS := [
	{"gap": Vector2(2.5, 9.0), "top": Vector2(-8.0, 6.0), "chance": 0.3, "slim": Vector2(1.0, 1.6)},
	{"gap": Vector2(10.0, 26.0), "top": Vector2(-16.0, -2.0), "chance": 0.3, "slim": Vector2(1.2, 2.0)},
	{"gap": Vector2(26.0, 56.0), "top": Vector2(-26.0, -8.0), "chance": 0.45, "slim": Vector2(1.4, 2.4)},
]
const GRASSY := 0.45             # the share of mesas whose top is grassy
# Lower on the screen-left (world +x), per band: the camera sits on the
# screen-right side, so the screen-left mesas stand far off, high in the
# frame, and a top there is cut by the frame's edge unless it is lower
# (tools/pillar_frame.gd, 2026-10-21: tops in frame on the screen-left
# 32 / 45 / 35 % against 60 / 78 / 73 % on the right).
const SCREEN_LEFT_DROP := [4.0, 6.0, 8.0]
# How tall a pillar can be and still show its top is the camera's call,
# not this table's: tools/pillar_frame.gd measures it. Under today's
# camera (54 degrees down, from the screen-right side) a top stays in
# frame 80 % of the time only below about +11.6 / +5.8 / -3.9 (near /
# mid / far, screen-right) and +4.7 / -4.3 / -18.8 (screen-left), the
# floor at 0 (step 3 brief 1 section 3, 2026-10-21; the variant built
# from it, "tops in frame", lost on the phone and is gone).
# How far ahead of the window's back edge a band is drawn at all (its
# material's fade has taken it by then), and how far behind.
const SHOW_BEHIND := 56.0
const SHOW_AHEAD := [72.0, 92.0, 132.0]     # each band's fade end (props.PILLAR_FADE), plus a little

# Part of the seed: the level (the dev path) or SEASON_SEED + lap.
var seed_level := 1
# Pillars are placed per 8-unit bar counted from here (the first z ever
# asked for), so a strip built later continues the same sequence.
var _origin_z := INF
var _strips: Array = []          # {z0, z1, nodes: [3], zs: [3 x PackedFloat32Array], sides: [3 x PackedByteArray], boxes: [3 x Array[AABB]]}


# The level path: everything at once (split into strips inside).
func build(z_from: float, z_to: float, level_seed: int) -> void:
	seed_level = level_seed
	build_range(z_from, z_to)


# One or more strips of the course. Strips may come in any order.
func build_range(z_from: float, z_to: float) -> void:
	if _origin_z == INF:
		_origin_z = z_from
	var z := z_from
	while z < z_to - 0.01:
		_build_strip(z, minf(z + STRIP, z_to))
		z += STRIP


func _build_strip(z0: float, z1: float) -> void:
	# Per band: the merged arrays of every mesa in the strip (one mesh, one
	# draw), and each mesa's z / side for the readouts.
	var verts: Array = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	var norms: Array = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	var cols: Array = [PackedColorArray(), PackedColorArray(), PackedColorArray()]
	var idx: Array = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	var zs: Array = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	var sides: Array = [PackedByteArray(), PackedByteArray(), PackedByteArray()]
	var boxes: Array = [[], [], []]       # each mesa's box, for tools/pillar_frame.gd
	var names: Array = Props.kit_names()
	var rng := RandomNumberGenerator.new()
	var bar := int(round((z0 - _origin_z) / BeatClock.BAR_UNITS))
	# set_density's thinning, per band and side: a mesa is kept each time
	# this passes 1. Decided AFTER the mesa's random draws, so the kept
	# ones stand exactly where they stand at 1.0.
	var keep := PackedFloat32Array()
	keep.resize(BANDS.size() * 2)
	var z := z0
	while z < z1 - 0.01:
		rng.seed = hash("pillars-%d-%d" % [seed_level, bar])
		for b in BANDS.size():
			var band: Dictionary = BANDS[b]
			for side: float in [-1.0, 1.0]:
				var n := 1 if rng.randf() < float(band["chance"]) else 0
				for i in n:
					var name: String = names[rng.randi_range(0, names.size() - 1)]
					var gap: float = rng.randf_range(band["gap"].x, band["gap"].y)
					var top: float = rng.randf_range(band["top"].x, band["top"].y) - (SCREEN_LEFT_DROP[b] if side > 0.0 else 0.0)
					var slim: float = rng.randf_range(band["slim"].x, band["slim"].y)
					var zz := z + rng.randf_range(0.0, BeatClock.BAR_UNITS)
					var turn := rng.randf_range(0.0, TAU)
					var c: Color = WorldPalette.MESAS[rng.randi_range(0, WorldPalette.MESAS.size() - 1)]
					c = Color(c.lightened(rng.randf_range(-0.04, 0.04)), 1.0 if rng.randf() < GRASSY else 0.0)
					var ki := b * 2 + (0 if side < 0.0 else 1)
					keep[ki] += _density
					if keep[ki] < 1.0:
						continue
					keep[ki] -= 1.0
					_place(b, name, gap, top - BASE_Y, slim, turn, c, side, zz, verts, norms, cols, idx, zs, sides, boxes)
		z += BeatClock.BAR_UNITS
		bar += 1
	var strip := {"z0": z0, "z1": z1, "nodes": [], "zs": zs, "sides": sides, "boxes": boxes}
	for b in BANDS.size():
		var mi := MeshInstance3D.new()
		var mesh := ArrayMesh.new()
		if verts[b].size() > 0:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts[b]
			arrays[Mesh.ARRAY_NORMAL] = norms[b]
			arrays[Mesh.ARRAY_COLOR] = cols[b]
			arrays[Mesh.ARRAY_INDEX] = idx[b]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mi.mesh = mesh
		mi.material_override = Props.pillar(b)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		strip["nodes"].append(mi)
	_strips.append(strip)


# One mesa: the kit piece scaled to `h` (uniform), broadened or thinned
# by `slim`, turned by `turn` about the vertical, base at BASE_Y, its
# near side `gap` from the field's edge.
func _place(b: int, name: String, gap: float, h: float, slim: float, turn: float, c: Color, side: float, zz: float,
		verts: Array, norms: Array, cols: Array, idx: Array, zs: Array, sides: Array, boxes: Array) -> void:
	var size := Props.kit_size(name)
	var k := h / size.y
	var reach := maxf(size.x, size.z) * k * slim * 0.5
	var x := side * (Rules.half_width() + gap + reach)
	var basis := Basis(Vector3.UP, turn).scaled_local(Vector3(k * slim, k, k * slim))
	var xf := Transform3D(basis, Vector3(x, BASE_Y, zz))
	var src: Mesh = Props.kit_mesh(name)
	if src == null:
		return
	var a: Array = src.surface_get_arrays(0)
	var sv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var sn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var si: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var base: int = verts[b].size()
	var nb: Basis = xf.basis.inverse().transposed()
	for i in sv.size():
		verts[b].append(xf * sv[i])
		norms[b].append((nb * sn[i]).normalized())
		cols[b].append(c)
	for i in si.size():
		idx[b].append(base + si[i])
	zs[b].append(zz)
	sides[b].append(0 if side < 0.0 else 1)
	boxes[b].append(xf * src.get_aabb())


# Called with the window's back edge every frame: a band of a strip is
# drawn while the strip overlaps the band's own range.
func set_window(z_back: float) -> void:
	for strip in _strips:
		for b in BANDS.size():
			var on: bool = float(strip["z1"]) >= z_back - SHOW_BEHIND and float(strip["z0"]) <= z_back + float(SHOW_AHEAD[b])
			var mmi: MeshInstance3D = strip["nodes"][b]
			if mmi.visible != on:
				mmi.visible = on


# The fraction of the pillars kept (the probe's "no pillars" / "pillars
# x0.5", looks.gd's "pillars"): every band and side keeps that share, the
# rest are left out of the merged meshes. The bands are merged into one
# mesh each, so a change rebuilds every strip already built, from the
# same seeds (a few hundred microseconds a strip on the Mac).
var _density := 1.0
func set_density(f: float) -> void:
	f = clampf(f, 0.0, 1.0)
	if is_equal_approx(f, _density):
		return
	_density = f
	_rebuild()


func _rebuild() -> void:
	var built: Array = _strips
	_strips = []
	for strip in built:
		for mi: MeshInstance3D in strip["nodes"]:
			mi.queue_free()
		_build_strip(float(strip["z0"]), float(strip["z1"]))


# For tools/autoplay.gd's gap measurement and the dev readout: how many
# pillars sit inside the fade-visible range of the window, per side
# (x: the left, screen-right side; y: the right), all bands.
func in_view(z_back: float) -> Vector2i:
	var n := Vector2i.ZERO
	var lo := z_back - Mats.FADE_BEHIND_END
	var hi := z_back + Mats.FADE_AHEAD_END
	for strip in _strips:
		if float(strip["z1"]) < lo or float(strip["z0"]) > hi:
			continue
		for b in BANDS.size():
			var zs: PackedFloat32Array = strip["zs"][b]
			var sides: PackedByteArray = strip["sides"][b]
			for i in zs.size():
				if zs[i] >= lo and zs[i] <= hi:
					if sides[i] == 0:
						n.x += 1
					else:
						n.y += 1
	return n


# For the screenshot tool's report.
func counts() -> Dictionary:
	var total := 0
	var shown := 0
	for strip in _strips:
		for b in BANDS.size():
			var k: int = strip["zs"][b].size()
			total += k
			if strip["nodes"][b].visible:
				shown += k
	return {"total": total, "shown": shown, "detailed": 0}
