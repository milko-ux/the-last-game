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
# Each band of each 64-unit strip is ONE MultiMeshInstance3D — one draw
# call however many pillars — of the measured 108-triangle hull of the
# tall building model (Props.low_mesh: the same faceted silhouette,
# nothing carved, and a dark silhouette cannot show a carving anyway).
# The carved 6k / 1.5k buildings, the near huge blocks, the far huge
# ones and their detail swap are gone from the run (the menu still uses
# the carved models). Per strip that is 3 draw calls and a few thousand
# triangles where one carved building was 4-6k on its own.
#
# Placed deterministically per bar from a seeded generator, so the same
# level looks the same on every device. z is time, like everything else.
# ============================================================

const Mats := preload("res://prototype/flat_mats.gd")
const Rules := preload("res://prototype/rules.gd")
const Props := preload("res://prototype/props/props.gd")

const STRIP := 64.0              # one MultiMesh per band per this much z
const BASE_Y := -22.0            # feet well below the slab: the height fog dissolves them
const TILT_MAX_DEG := 6.0
# Per band: the gap from the field's edge to the pillar's near face, the
# height, how many per side per 8-unit bar, and how slim (x / z scale on
# top of the uniform one, so a pillar is thinner than the model).
const BANDS := [
	{"gap": Vector2(2.0, 9.0), "h": Vector2(12.0, 28.0), "n": Vector2i(1, 2), "slim": Vector2(0.45, 0.8)},
	{"gap": Vector2(11.0, 22.0), "h": Vector2(18.0, 42.0), "n": Vector2i(1, 2), "slim": Vector2(0.5, 0.9)},
	{"gap": Vector2(24.0, 46.0), "h": Vector2(30.0, 70.0), "n": Vector2i(2, 3), "slim": Vector2(0.55, 1.0)},
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
var _mesh: Mesh = null


# The level path: everything at once (split into strips inside).
func build(z_from: float, z_to: float, level_seed: int) -> void:
	seed_level = level_seed
	build_range(z_from, z_to)


# One or more strips of the course. Strips may come in any order.
func build_range(z_from: float, z_to: float) -> void:
	if _mesh == null:
		_mesh = Props.low_mesh("building_tall")
	if _origin_z == INF:
		_origin_z = z_from
	var z := z_from
	while z < z_to - 0.01:
		_build_strip(z, minf(z + STRIP, z_to))
		z += STRIP


func _build_strip(z0: float, z1: float) -> void:
	var msize: Vector3 = Props.size_of("building_tall")
	var xforms: Array = [[], [], []]
	var zs: Array = [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	var sides: Array = [PackedByteArray(), PackedByteArray(), PackedByteArray()]
	var rng := RandomNumberGenerator.new()
	var bar := int(round((z0 - _origin_z) / BeatClock.BAR_UNITS))
	var z := z0
	while z < z1 - 0.01:
		rng.seed = hash("pillars-%d-%d" % [seed_level, bar])
		for b in BANDS.size():
			var band: Dictionary = BANDS[b]
			for side: float in [-1.0, 1.0]:
				var n: int = rng.randi_range(band["n"].x, band["n"].y)
				for i in n:
					var gap: float = rng.randf_range(band["gap"].x, band["gap"].y)
					var h: float = rng.randf_range(band["h"].x, band["h"].y)
					var slim: float = rng.randf_range(band["slim"].x, band["slim"].y)
					var k := h / msize.y                                   # the uniform scale
					var yaw := rng.randf_range(-0.25, 0.25) + (PI if rng.randf() < 0.5 else 0.0)
					var tilt := deg_to_rad(rng.randf_range(-TILT_MAX_DEG, TILT_MAX_DEG))
					var basis := (Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, tilt)).scaled_local(Vector3(k * slim, k, k * slim))
					var reach := maxf(msize.x, msize.z) * k * slim * 0.5   # its footprint's half width
					var x := side * (Rules.half_width() + gap + reach)
					var zz := z + rng.randf_range(0.0, BeatClock.BAR_UNITS)
					xforms[b].append(Transform3D(basis, Vector3(x, BASE_Y + h * 0.5, zz)))
					zs[b].append(zz)
					sides[b].append(0 if side < 0.0 else 1)
		z += BeatClock.BAR_UNITS
		bar += 1
	var strip := {"z0": z0, "z1": z1, "nodes": [], "zs": zs, "sides": sides}
	for b in BANDS.size():
		var mmi := MultiMeshInstance3D.new()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _mesh
		mm.instance_count = xforms[b].size()
		for i in xforms[b].size():
			mm.set_instance_transform(i, xforms[b][i])
		mmi.multimesh = mm
		mmi.material_override = Props.pillar(b)
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visible = false
		add_child(mmi)
		strip["nodes"].append(mmi)
	_strips.append(strip)


# Called with the window's back edge every frame: a band of a strip is
# drawn while the strip overlaps the band's own range.
func set_window(z_back: float) -> void:
	for strip in _strips:
		for b in BANDS.size():
			var on: bool = float(strip["z1"]) >= z_back - SHOW_BEHIND and float(strip["z0"]) <= z_back + float(SHOW_AHEAD[b])
			var mmi: MultiMeshInstance3D = strip["nodes"][b]
			if mmi.visible != on:
				mmi.visible = on


# The probe's "half the pillars": draw this fraction of every band.
func set_density(f: float) -> void:
	for strip in _strips:
		for b in BANDS.size():
			var mm: MultiMesh = strip["nodes"][b].multimesh
			mm.visible_instance_count = int(round(mm.instance_count * clampf(f, 0.0, 1.0)))


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
