extends Node3D
# ============================================================
# MONOLITHS — the carved stone buildings around the field (brief 2
# section 3, the two building models since brief 4).
#
# 2026-09-20, after the phone report ("blurry and stretched"):
#  - UNIFORM SCALE. A monolith is one of the two models scaled by ONE
#    number (its height / the model's height), so it keeps the model's
#    proportions. Before, width, height and depth were three random
#    numbers and the shader tapered the top: the carvings smeared.
#  - PROCEDURAL MATERIAL. No colour comes from the model (the rule: no
#    AI image textures in the game). Props.building() is stone from
#    world position, triplanar, lit per facet: crisp at any size.
#  - TWO DETAIL LEVELS. The carved symbols and the recessed circle are
#    real geometry in the source models. Near the window a monolith
#    wears the 6k-triangle copy where they survive; further out, in the
#    fog, the 1.5k copy. Each monolith is its own MeshInstance3D so the
#    switch is per monolith (and the engine culls each one that is off
#    screen); only the ones near the window are visible at all.
#  - FOG carries the far ones: the material fogs by distance to the
#    side and below the field as well as along z.
#
# Placed deterministically per bar from a seeded generator, so the same
# level looks the same on every device. z is time, like everything else.
# ============================================================

const Mats := preload("res://prototype/flat_mats.gd")
const Rules := preload("res://prototype/rules.gd")
const Props := preload("res://prototype/props/props.gd")

const TALL_SHARE := 0.6

# Placement (all in world units; a bar is 8 long, the field 18 wide).
const PER_SIDE_MIN := 1
const PER_SIDE_MAX := 2          # was 3: fewer, but each one is a whole building now
const GAP_MIN := 3.0             # from the field edge to the monolith's nearest face
const GAP_MAX := 14.0
const GAP_MIN_RIGHT := 4.0       # the near-right corner sits by the bottom of the screen
# The ONE number per monolith: its height. Width and depth follow from the
# model (tall: 0.33 x and 0.18 x the height; stacked: 0.51 x and 0.57 x).
const TALL_HEIGHT := Vector2(14.0, 40.0)
const STACKED_HEIGHT := Vector2(14.0, 28.0)
const BASE_Y := -22.0            # tops land between -8 and +18, around the slab
const TILT_MAX_DEG := 6.0
const FAR_EVERY := 6             # 1 in 6 bars gets one far, huge one (always the tall model)
const FAR_GAP_MIN := 20.0
const FAR_GAP_MAX := 30.0
const FAR_HEIGHT := Vector2(44.0, 64.0)
const FAR_BASE_Y := -30.0

# Which monoliths are drawn, and which wear the detailed mesh, measured
# from the window's back edge along z to the monolith's centre.
const SHOW_BEHIND := Mats.FADE_BEHIND_END + 12.0
const SHOW_AHEAD := Mats.FADE_AHEAD_END + 12.0
const DETAIL_BEHIND := 6.0
const DETAIL_AHEAD := 18.0       # the fade starts at 14 and is half-way by ~20: past that the carvings are fog

var _z := PackedFloat32Array()   # each monolith's centre z, ascending
var _nodes: Array[MeshInstance3D] = []
var _kinds: Array[String] = []   # the model name (without _hi)
var _far := PackedByteArray()    # 1 = a far, huge one: never detailed
var _detailed := PackedByteArray()
var _meshes := {}                # model name -> Mesh
var _shown_lo := 0
var _shown_hi := 0


# Part of the seed: the level (the dev path) or SEASON_SEED + lap.
var seed_level := 1
# Monoliths are placed per 8-unit step counted from here (the first z
# ever asked for), so a strip built later continues the same sequence.
var _origin_z := INF


# The level path: everything at once.
func build(z_from: float, z_to: float, level_seed: int) -> void:
	seed_level = level_seed
	build_range(z_from, z_to)


# One strip of the course (the endless run builds a lap's monoliths a
# strip at a time, between frames). Strips may come in any order; every
# monolith is inserted at its place in the z-sorted list.
func build_range(z_from: float, z_to: float) -> void:
	if _meshes.is_empty():
		for model in ["building_tall", "building_stacked", "building_tall_hi", "building_stacked_hi"]:
			_meshes[model] = Props.mesh_of(model)
	if _origin_z == INF:
		_origin_z = z_from
	var specs := []              # [z, transform, kind, far]
	var rng := RandomNumberGenerator.new()
	var bar := int(round((z_from - _origin_z) / BeatClock.BAR_UNITS))
	var z := z_from
	while z < z_to:
		rng.seed = hash("monoliths-%d-%d" % [seed_level, bar])
		for side: float in [-1.0, 1.0]:
			for i in rng.randi_range(PER_SIDE_MIN, PER_SIDE_MAX):
				var gap := rng.randf_range(GAP_MIN_RIGHT if side < 0.0 else GAP_MIN, GAP_MAX)
				specs.append(_spec(rng, side, gap, z, false))
		if bar % FAR_EVERY == FAR_EVERY - 1:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			specs.append(_spec(rng, side, rng.randf_range(FAR_GAP_MIN, FAR_GAP_MAX), z, true))
		z += BeatClock.BAR_UNITS
		bar += 1
	# The shown range is indexed: hide it, insert, and let the next
	# set_window() show what belongs (same frame, nothing flickers).
	for i in range(_shown_lo, _shown_hi):
		_nodes[i].visible = false
	_shown_lo = 0
	_shown_hi = 0
	for sp in specs:
		var mi := MeshInstance3D.new()
		mi.mesh = _meshes[sp[2]]
		mi.material_override = Props.building(sp[3])
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.transform = sp[1]
		mi.visible = false
		add_child(mi)
		var at := _z.bsearch(sp[0], false)
		_z.insert(at, sp[0])
		_nodes.insert(at, mi)
		_kinds.insert(at, sp[2])
		_far.insert(at, 1 if sp[3] else 0)
		_detailed.insert(at, 0)


# One monolith: a model, ONE scale, a small yaw and tilt, front or back
# toward the camera (both carry the circle), its near face `gap` from the
# field edge.
func _spec(rng: RandomNumberGenerator, side: float, gap: float, bar_z: float, far: bool) -> Array:
	var kind := "building_tall" if far or rng.randf() < TALL_SHARE else "building_stacked"
	var range_h := FAR_HEIGHT if far else (TALL_HEIGHT if kind == "building_tall" else STACKED_HEIGHT)
	var h := rng.randf_range(range_h.x, range_h.y)
	var msize: Vector3 = Props.size_of(kind)
	var k := h / msize.y                                   # the uniform scale
	var yaw := rng.randf_range(-0.25, 0.25) + (PI if rng.randf() < 0.5 else 0.0)
	var tilt := deg_to_rad(rng.randf_range(-TILT_MAX_DEG, TILT_MAX_DEG))
	var b := (Basis(Vector3.UP, yaw) * Basis(Vector3.BACK, tilt)).scaled_local(Vector3.ONE * k)
	var reach := maxf(msize.x, msize.z) * k * 0.5          # its footprint's half width, whatever the yaw
	var x := side * (Rules.half_width() + gap + reach)
	var zz := bar_z + rng.randf_range(0.0, BeatClock.BAR_UNITS)
	var base_y := FAR_BASE_Y if far else BASE_Y
	# The model is centred on its own middle: lift it so its foot is at base_y.
	return [zz, Transform3D(b, Vector3(x, base_y + h * 0.5, zz)), kind, far]


# Called with the window's back edge every frame: shows the monoliths near
# the window, hides the ones that left, and gives the nearest the detailed
# mesh. Touches only the few in range, not the level's ~250.
func set_window(z_back: float) -> void:
	var lo := _z.bsearch(z_back - SHOW_BEHIND)
	var hi := _z.bsearch(z_back + SHOW_AHEAD)
	for i in range(_shown_lo, _shown_hi):
		if i < lo or i >= hi:
			_nodes[i].visible = false
	for i in range(lo, hi):
		_nodes[i].visible = true
		var d := _z[i] - z_back
		var want := 1 if _far[i] == 0 and d > -DETAIL_BEHIND and d < DETAIL_AHEAD else 0
		if want != _detailed[i]:
			_detailed[i] = want
			_nodes[i].mesh = _meshes[_kinds[i] + ("_hi" if want == 1 else "")]
			if FrameMeter.active:
				FrameMeter.note("monolith detail swap")
	_shown_lo = lo
	_shown_hi = hi


# For tools/autoplay.gd's gap measurement: how many of this node's
# monoliths sit inside the fade-visible range of the window, per side
# (x: the left, screen-right side; y: the right).
func in_view(z_back: float) -> Vector2i:
	var lo := _z.bsearch(z_back - Mats.FADE_BEHIND_END)
	var hi := _z.bsearch(z_back + Mats.FADE_AHEAD_END)
	var n := Vector2i.ZERO
	for i in range(lo, hi):
		if not _nodes[i].visible:
			continue
		if _nodes[i].transform.origin.x < 0.0:
			n.x += 1
		else:
			n.y += 1
	return n


# For the screenshot tool's report.
func counts() -> Dictionary:
	var shown := 0
	var detailed := 0
	for i in range(_shown_lo, _shown_hi):
		shown += 1
		detailed += _detailed[i]
	return {"total": _nodes.size(), "shown": shown, "detailed": detailed}
