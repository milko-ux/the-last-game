extends Node3D
# ============================================================
# MONOLITHS — the pillars around the field. LOOK PASS v2 section 3
# (2026-09-23): the concept has MANY slim pillars at graduated
# distances, not a few huge blocks by the camera. Three bands per side:
#
#   near   dark silhouettes, close to the slab, the darkest thing in frame
#   mid    a little further, a little lighter
#   far    a skyline, fading into the light fog
#
# Each band of each 64-unit strip is ONE mesh -- one draw call however
# many pillars -- merged from THE PILLAR KIT (brief stage B, 2026-09-24:
# six variants and a bridge piece built and baked in Blender,
# tools/blender/pillars.py, assets/models/kit/). The stone, the light and
# the occlusion are in the atlas; the meshes are 26-130 triangles each.
# Every pillar stands straight and is never turned: the light is baked.
# (Before that: the measured hull of the tall building model, and before
# that the carved 6k buildings with a detail swap.)
#
# Placed deterministically per bar from a seeded generator, so the same
# level looks the same on every device. z is time, like everything else.
# ============================================================

const Mats := preload("res://prototype/flat_mats.gd")
const Rules := preload("res://prototype/rules.gd")
const Props := preload("res://prototype/props/props.gd")

const STRIP := 64.0              # one merged mesh per band per this much z
const LINTEL_EVERY := 5          # in the near band, every this many bars: a pair of pillars with the bridge piece
const BASE_Y := -22.0            # feet well below the slab: the height fog dissolves them
const TILT_MAX_DEG := 6.0
# Per band: the gap from the field's edge to the pillar's near face, the
# height, how many per side per 8-unit bar, and how slim (x / z scale on
# top of the uniform one, so a pillar is thinner than the model).
const BANDS := [
	{"gap": Vector2(3.0, 10.0), "h": Vector2(12.0, 28.0), "n": Vector2i(0, 1), "slim": Vector2(0.6, 1.0)},
	{"gap": Vector2(12.0, 24.0), "h": Vector2(18.0, 42.0), "n": Vector2i(1, 2), "slim": Vector2(0.7, 1.1)},
	{"gap": Vector2(26.0, 48.0), "h": Vector2(30.0, 70.0), "n": Vector2i(1, 2), "slim": Vector2(0.8, 1.3)},
]
# How far ahead of the window's back edge a band is drawn at all (its
# material's fade has taken it by then), and how far behind.
const SHOW_BEHIND := 24.0
const SHOW_AHEAD := [Mats.FADE_AHEAD_END + 12.0, 62.0, 102.0]

# Part of the seed: the level (the dev path) or SEASON_SEED + lap.
var seed_level := 1
# Pillars are placed per 8-unit bar counted from here (the first z ever
# asked for), so a strip built later continues the same sequence.
var _origin_z := INF
var _strips: Array = []          # {z0, z1, nodes: [3], zs: [3 x PackedFloat32Array], sides: [3 x PackedByteArray]}


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
	# Per band: the merged arrays of every pillar in the strip (one mesh,
	# one draw), and each pillar's z / side for the readouts.
	var verts: Array = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	var norms: Array = [PackedVector3Array(), PackedVector3Array(), PackedVector3Array()]
	var uvs: Array = [PackedVector2Array(), PackedVector2Array(), PackedVector2Array()]
	var idx: Array = [PackedInt32Array(), PackedInt32Array(), PackedInt32Array()]
	var zs: Array = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	var sides: Array = [PackedByteArray(), PackedByteArray(), PackedByteArray()]
	var names: Array = Props.kit_names()
	var pillars: Array = names.filter(func(n): return n != "lintel")
	var rng := RandomNumberGenerator.new()
	var bar := int(round((z0 - _origin_z) / BeatClock.BAR_UNITS))
	var z := z0
	while z < z1 - 0.01:
		rng.seed = hash("pillars-%d-%d" % [seed_level, bar])
		for b in BANDS.size():
			var band: Dictionary = BANDS[b]
			for side: float in [-1.0, 1.0]:
				var n: int = rng.randi_range(band["n"].x, band["n"].y)
				# The near band: every LINTEL_EVERY bars, a pair of the same
				# pillar with the bridge piece across them, instead of one.
				var pair: bool = b == 0 and bar % LINTEL_EVERY == (2 if side < 0.0 else 4)
				for i in n:
					var name: String = pillars[rng.randi_range(0, pillars.size() - 1)]
					var gap: float = rng.randf_range(band["gap"].x, band["gap"].y)
					var h: float = rng.randf_range(band["h"].x, band["h"].y)
					var slim: float = rng.randf_range(band["slim"].x, band["slim"].y)
					var zz := z + rng.randf_range(0.0, BeatClock.BAR_UNITS)
					if pair and i == 0:
						var lsize := Props.kit_size("lintel")
						var span := lsize.z * 0.9
						var x0 := _place(b, name, gap, h, slim, side, zz, verts, norms, uvs, idx, zs, sides)
						_place(b, name, gap, h, slim, side, zz + span, verts, norms, uvs, idx, zs, sides)
						var k := h / Props.kit_size(name).y * slim * 0.9   # the lintel's scale follows the pair
						_append(b, "lintel", Transform3D(Basis.IDENTITY.scaled(Vector3(k, k, span / lsize.z)),
							Vector3(x0, BASE_Y + h, zz + span * 0.5)), verts, norms, uvs, idx, zs, sides, side)
					else:
						_place(b, name, gap, h, slim, side, zz, verts, norms, uvs, idx, zs, sides)
		z += BeatClock.BAR_UNITS
		bar += 1
	var strip := {"z0": z0, "z1": z1, "nodes": [], "zs": zs, "sides": sides}
	for b in BANDS.size():
		var mi := MeshInstance3D.new()
		var mesh := ArrayMesh.new()
		if verts[b].size() > 0:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = verts[b]
			arrays[Mesh.ARRAY_NORMAL] = norms[b]
			arrays[Mesh.ARRAY_TEX_UV] = uvs[b]
			arrays[Mesh.ARRAY_INDEX] = idx[b]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mi.mesh = mesh
		mi.material_override = Props.pillar(b)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.visible = false
		add_child(mi)
		strip["nodes"].append(mi)
	_strips.append(strip)


# One pillar: the kit variant scaled to `h` (uniform) and thinned, base
# at BASE_Y, its near face `gap` from the field's edge, NEVER turned or
# tilted (the light is baked in). Returns its x.
func _place(b: int, name: String, gap: float, h: float, slim: float, side: float, zz: float,
		verts: Array, norms: Array, uvs: Array, idx: Array, zs: Array, sides: Array) -> float:
	var size := Props.kit_size(name)
	var k := h / size.y
	var reach := maxf(size.x, size.z) * k * slim * 0.5
	var x := side * (Rules.half_width() + gap + reach)
	_append(b, name, Transform3D(Basis.IDENTITY.scaled(Vector3(k * slim, k, k * slim)), Vector3(x, BASE_Y, zz)),
		verts, norms, uvs, idx, zs, sides, side)
	return x


func _append(b: int, name: String, xf: Transform3D, verts: Array, norms: Array, uvs: Array, idx: Array,
		zs: Array, sides: Array, side: float) -> void:
	var src: Mesh = Props.kit_mesh(name)
	if src == null:
		return
	var a: Array = src.surface_get_arrays(0)
	var sv: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var sn: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
	var su: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
	var si: PackedInt32Array = a[Mesh.ARRAY_INDEX]
	var base: int = verts[b].size()
	var nb: Basis = xf.basis.inverse().transposed()
	for i in sv.size():
		verts[b].append(xf * sv[i])
		norms[b].append((nb * sn[i]).normalized())
	uvs[b].append_array(su)
	for i in si.size():
		idx[b].append(base + si[i])
	zs[b].append(xf.origin.z)
	sides[b].append(0 if side < 0.0 else 1)


# Called with the window's back edge every frame: a band of a strip is
# drawn while the strip overlaps the band's own range.
func set_window(z_back: float) -> void:
	for strip in _strips:
		for b in BANDS.size():
			var on: bool = float(strip["z1"]) >= z_back - SHOW_BEHIND and float(strip["z0"]) <= z_back + float(SHOW_AHEAD[b]) \
				and not (b == 2 and _density < 0.999)
			var mmi: MeshInstance3D = strip["nodes"][b]
			if mmi.visible != on:
				mmi.visible = on


# The probe's "half the pillars": with the bands merged into one mesh
# each there is no instance count to halve, so below 1.0 the far band is
# dropped (about half the pillars by count), and at 1.0 it is back.
var _density := 1.0
func set_density(f: float) -> void:
	_density = f


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
