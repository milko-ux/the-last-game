extends SceneTree
# ============================================================
# PILLAR FRAME — step 3 brief 1 section 3: what the camera does to the
# pillars, by projection, no rendering. Builds the real monoliths.gd
# strips, then walks the window along the course
# a unit at a time with the real camera (camera_rig.gd's offset, FOV,
# the phone's 2556 x 1179) and counts, per band and side:
#
#   in view   pillars on screen and clearly there (their band's fade < 0.5)
#   top in    of those, the share whose top face is inside the frame,
#             at least MARGIN below its top edge
#   above     of those, the share whose top is above the floor (y 0)
#   allowed   the highest top (world y, the floor is 0) that would still
#             be inside the frame for 80 % / 50 % of those sightings --
#             the number a band's height range is set from
#   covers    frames where a pillar is between the camera and any part
#             of the playing field or the hero (rays to a grid over the
#             window, at the floor and at hero height)
#
# and per side the readout's own count (monoliths.in_view, `mono L/R`).
#
#   godot --headless --path . -s tools/pillar_frame.gd -- bars=2.2 seeds=1,2,3
#
# Dev-only, writes nothing.
# ============================================================

# Loaded in _initialize, not preloaded: they need the BeatClock autoload.
var Monoliths: GDScript
var Props: GDScript
var Rig: GDScript
var Rules: GDScript

const W := 2556.0
const H := 1179.0
const MARGIN := 0.05            # of the frame's height, kept clear above a top
var SEEDS := [1, 2, 3]       # seeds=a,b: e.g. 20260901, the season's lap 0
const Z_FROM := 0.0
const Z_TO := 800.0             # 100 bars per seed
const HERO_Y := 2.5             # the hero's top, and about the hazards' height


func _initialize() -> void:
	Rules = load("res://prototype/rules.gd")
	Props = load("res://prototype/props/props.gd")
	Rig = load("res://prototype/camera_rig.gd")
	Monoliths = load("res://prototype/monoliths.gd")
	var bars: float = Rules.WINDOW_BARS_DEFAULT
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() == 2 and kv[0] == "seeds":
			SEEDS = Array(kv[1].split(",")).map(func(x): return int(x))
		if kv.size() == 2 and kv[0] == "bars":
			bars = float(kv[1])
	var progress = root.get_node_or_null("Progress")
	if progress != null:
		progress.save_enabled = false
	var clock = root.get_node_or_null("BeatClock")
	if clock == null:
		clock = load("res://prototype/beat_clock.gd").new()
		clock.name = "BeatClock"
		root.add_child(clock)

	var depth: float = bars * Rules.BAR_LENGTH
	Rig.CAMERA_DISTANCE = Rig.CAMERA_DISTANCE_AT_2_2 + (bars - 2.2) * Rig.CAMERA_DISTANCE_PER_BAR
	var offset: Vector3 = Rig.camera_offset()
	var proj := Projection.create_perspective(Rig.FOV, W / H, 0.05, 4000.0)
	print("PILLAR FRAME  window %.1f bars  camera distance %.1f  offset %s  FOV %.0f  %dx%d" % [
		bars, Rig.CAMERA_DISTANCE, offset, Rig.FOV, W, H])

	# [band][side] -> totals over every frame of every seed.
	var seen := []
	var top_in := []
	var above := []
	var allowed := []                   # [band][side] -> every sighting's highest top in frame
	for b in Monoliths.BANDS.size():
		seen.append([0, 0]); top_in.append([0, 0]); above.append([0, 0])
		allowed.append([PackedFloat32Array(), PackedFloat32Array()])
	var frames := 0
	var cover_frames := 0
	var low_frames := 0                 # frames where a band's top-in share was under 80 %
	var readout := Vector2.ZERO
	var on_screen := Vector2.ZERO
	var built := 0                      # pieces built (pillars and bridges) and their triangles, every seed
	var tris := 0

	for s in SEEDS:
		var m = Monoliths.new()
		m.seed_level = s
		m.build_range(Z_FROM, Z_TO)
		for strip in m._strips:
			for mi: MeshInstance3D in strip["nodes"]:
				if mi.mesh.get_surface_count() > 0:
					tris += mi.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3
			for b in Monoliths.BANDS.size():
				built += strip["boxes"][b].size()
		var z_back := Z_FROM + 40.0
		while z_back < Z_TO - 120.0:
			frames += 1
			var look := Vector3(0.0, 0.0, z_back + depth * 0.5)
			var cam := Transform3D(Basis(), look + offset).looking_at(look, Vector3.UP)
			var view := cam.affine_inverse()
			var frame_seen := [0, 0, 0]
			var frame_in := [0, 0, 0]
			var blockers: Array = []
			var vis := Vector2.ZERO
			for strip in m._strips:
				for b in Monoliths.BANDS.size():
					var f4: Vector4 = Props.PILLAR_FADE[b]
					for box: AABB in strip["boxes"][b]:
						var c := box.get_center()
						var d := c.z - z_back
						var fade := maxf(smoothstep(f4.x, f4.y, d), smoothstep(f4.z, f4.w, -d))
						if fade > 0.97:
							continue
						var r := _rect(box, view, proj)
						if r.size.x <= 0.0:
							continue
						var cx := r.position.x + r.size.x * 0.5
						var on := cx >= 0.0 and cx <= W and r.end.y > 0.0 and r.position.y < H
						if not on:
							continue
						blockers.append(box)
						if fade >= 0.5:
							continue
						var side := 0 if c.x < 0.0 else 1
						if side == 0: vis.x += 1
						else: vis.y += 1
						seen[b][side] += 1
						frame_seen[b] += 1
						if _top_y(box, view, proj) >= MARGIN * H:
							top_in[b][side] += 1
							frame_in[b] += 1
						if box.end.y > 0.0:
							above[b][side] += 1
						allowed[b][side].append(_highest_top(box, view, proj))
			for b in Monoliths.BANDS.size():
				if frame_seen[b] >= 3 and float(frame_in[b]) / frame_seen[b] < 0.8:
					low_frames += 1
					break
			on_screen += vis
			readout += Vector2(m.in_view(z_back))
			if _covers(blockers, cam.origin, z_back, depth):
				cover_frames += 1
			z_back += 1.0
		m.free()

	var names := ["near", "mid", "far"]
	print("band  side          in view/frame  top in frame  top above floor  allowed top 80 % / 50 %")
	for b in Monoliths.BANDS.size():
		for side in 2:
			var n: int = seen[b][side]
			var al: PackedFloat32Array = allowed[b][side]
			al.sort()
			var a80: float = al[int(al.size() * 0.2)] if al.size() > 0 else NAN
			var a50: float = al[int(al.size() * 0.5)] if al.size() > 0 else NAN
			print("%-5s %-13s %13.1f  %11.0f %%  %14.0f %%  %+11.1f / %+.1f" % [names[b], "screen-right" if side == 0 else "screen-left",
				float(n) / frames, 100.0 * top_in[b][side] / maxi(n, 1), 100.0 * above[b][side] / maxi(n, 1), a80, a50])
		var nb: int = seen[b][0] + seen[b][1]
		print("%-5s %-13s %13.1f  %11.0f %%  %14.0f %%" % [names[b], "both", float(nb) / frames,
			100.0 * (top_in[b][0] + top_in[b][1]) / maxi(nb, 1), 100.0 * (above[b][0] + above[b][1]) / maxi(nb, 1)])
	print("on screen per side (screen-left / screen-right): %.1f / %.1f" % [on_screen.y / frames, on_screen.x / frames])
	print("readout mono L/R (in_view, all bands): %.1f / %.1f" % [readout.x / frames, readout.y / frames])
	print("frames with a band under 80 %% tops in frame: %d of %d" % [low_frames, frames])
	print("built per 100 bars: %.0f pieces, %.0f triangles (one mesh per band per strip either way)" % [
		float(built) / SEEDS.size(), float(tris) / SEEDS.size()])
	print("frames where a pillar covers the field or the hero: %d of %d" % [cover_frames, frames])
	quit()


# A box's screen rectangle (pixels, y down) from its corners in front of
# the camera; empty if none is.
func _rect(box: AABB, view: Transform3D, proj: Projection) -> Rect2:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for i in 8:
		var p = _px(box.get_endpoint(i), view, proj)
		if p == null:
			continue
		lo = lo.min(p)
		hi = hi.max(p)
	if lo.x == INF:
		return Rect2()
	return Rect2(lo, hi - lo)


# The highest point on screen (smallest y, pixels) of the box's top face.
func _top_y(box: AABB, view: Transform3D, proj: Projection) -> float:
	var y := INF
	for i in 8:
		var e := box.get_endpoint(i)
		if e.y < box.end.y - 0.001:
			continue
		var p = _px(e, view, proj)
		if p != null:
			y = minf(y, p.y)
	return y


# The highest world y the box's top could have and still be MARGIN
# inside the frame where the box stands now (bisection on the top).
func _highest_top(box: AABB, view: Transform3D, proj: Projection) -> float:
	var lo := -60.0
	var hi := 60.0
	for i in 24:
		var mid := (lo + hi) * 0.5
		var b2 := AABB(Vector3(box.position.x, minf(box.position.y, mid - 0.1), box.position.z),
			Vector3(box.size.x, mid - minf(box.position.y, mid - 0.1), box.size.z))
		if _top_y(b2, view, proj) >= MARGIN * H:
			lo = mid
		else:
			hi = mid
	return lo


func _px(p: Vector3, view: Transform3D, proj: Projection):
	var v := view * p
	var clip: Vector4 = proj * Vector4(v.x, v.y, v.z, 1.0)
	if clip.w <= 0.01:
		return null
	return Vector2((clip.x / clip.w + 1.0) * 0.5 * W, (1.0 - clip.y / clip.w) * 0.5 * H)


# Any pillar box on a ray from the camera to the playing field: a grid
# over the window (and a little behind and ahead), at the floor and at
# the hero's height.
func _covers(boxes: Array, eye: Vector3, z_back: float, depth: float) -> bool:
	var hw: float = Rules.half_width()
	var z := z_back - 2.0
	while z <= z_back + depth + 4.0:
		var x := -hw
		while x <= hw + 0.01:
			for y in [0.0, HERO_Y]:
				var to := Vector3(x, y, z)
				for box: AABB in boxes:
					if box.intersects_segment(eye, to):
						return true
			x += 1.5
		z += 1.0
	return false
