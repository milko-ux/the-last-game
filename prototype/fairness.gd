extends RefCounted
# ============================================================
# FAIRNESS VALIDATOR — mandatory (addendum).
#
# For every beat of the song there must be at least one safe tile
# inside the window that is reachable, at PLAYER_SPEED, from at
# least one safe tile of the previous beat. Runs on the generated
# layout before play starts and fails loudly if it does not hold.
#
# "Safe" at a beat = a real tile (no pit), inside the window with a
# margin for the scroll, not a lethal pulse plate on that beat, and
# not overlapped by any hazard box at the beat start or mid-beat
# (the same hazard math the hazards themselves use).
# ============================================================

const Rules := preload("res://prototype/rules.gd")
const HazardMath := preload("res://prototype/hazard_math.gd")

const PLAYER_HALF := 0.45


static func validate(plan: Dictionary, clock) -> Dictionary:
	var problems := []
	var beats: PackedFloat64Array = clock.beats
	var bar_z0 := {}
	var bar_depth := {}
	for bar in range(1, clock.bar_count() + 1):
		bar_z0[bar] = clock.z_at(clock.bar_start(bar))
		bar_depth[bar] = clock.z_at(clock.bar_end(bar)) - bar_z0[bar]

	var reach: float = Rules.player_speed() * clock.beat_interval + 0.5
	var prev_safe := {}      # Vector3i(bar,col,row) -> true; empty = "anywhere"
	var first := true
	var last_bar_end: float = clock.z_at(clock.bar_end(clock.bar_count()))

	for i in range(clock.first_bar_beat, beats.size()):
		var t0: float = beats[i]
		var t1: float = beats[i + 1] if i + 1 < beats.size() else t0 + clock.beat_interval
		var t_mid := (t0 + t1) * 0.5
		var z_back: float = clock.z_at(t_mid)          # the edge keeps moving during the beat
		var z_front: float = clock.z_at(t0) + Rules.WINDOW_DEPTH
		var k: int = clock.beat_in_bar_at(t0)
		if z_back > last_bar_end:
			break

		# Hazard boxes near the window, sampled twice.
		var boxes := []
		for spec in plan["hazards"]:
			if absf(float(spec["z"]) - (z_back + z_front) * 0.5) > Rules.WINDOW_DEPTH:
				continue
			boxes.append_array(HazardMath.boxes_at(spec, t0))
			boxes.append_array(HazardMath.boxes_at(spec, t_mid))

		var safe := {}
		for bar in range(1, clock.bar_count() + 1):
			var z0: float = bar_z0[bar]
			var depth: float = bar_depth[bar]
			if z0 + depth < z_back or z0 > z_front:
				continue
			var entry: Dictionary = plan["bars"][bar]
			var pattern := String(entry["pattern"])
			for col in Rules.COLS:
				for row in Rules.ROWS:
					if entry["pits"].has([col, row]):
						continue
					var cz := z0 + (row + 0.5) * depth / Rules.ROWS
					if cz < z_back + 1.0 or cz > z_front - 1.0:
						continue
					if Rules.pattern_lethal(pattern, col, row, k):
						continue
					var cx := Rules.col_x(col)
					if _blocked(cx, cz, boxes):
						continue
					safe[Vector3i(bar, col, row)] = Vector2(cx, cz)

		# The plain outro slab after the last bar is always safe floor.
		if z_front - 1.0 > last_bar_end:
			for col in Rules.COLS:
				safe[Vector3i(clock.bar_count() + 1, col, 0)] = Vector2(Rules.col_x(col), maxf(last_bar_end + 1.0, z_back + 1.0))

		if safe.is_empty():
			problems.append("beat %d (bar %d, beat %d): no safe tile in the window" % [i, clock.bar_at(t0), k + 1])
			prev_safe = {}
			first = true
			continue

		if not first:
			var ok := false
			for key in safe:
				var p: Vector2 = safe[key]
				for pkey in prev_safe:
					if p.distance_to(prev_safe[pkey]) <= reach:
						ok = true
						break
				if ok:
					break
			if not ok:
				problems.append("beat %d (bar %d, beat %d): no safe tile reachable from the previous beat" % [i, clock.bar_at(t0), k + 1])
		prev_safe = safe
		first = false

	return {"ok": problems.is_empty(), "problems": problems}


static func _blocked(cx: float, cz: float, boxes: Array) -> bool:
	for b in boxes:
		var bb: AABB = b
		if bb.position.y > 1.6:
			continue
		if cx + PLAYER_HALF > bb.position.x and cx - PLAYER_HALF < bb.end.x \
			and cz + PLAYER_HALF > bb.position.z and cz - PLAYER_HALF < bb.end.z:
			return true
	return false
