extends RefCounted
# ============================================================
# PLACEMENT — turns the beatmap's per-bar numbers into hazards.
#
# Nothing here is hand-authored. A different song's beatmap gives
# a different level with zero code changes. Everything is
# deterministic (seeded by bar number) so the level is identical
# on every run and every device.
#
# Density by bar energy:
#   >= 0.85       GAUNTLET  hazard on every beat
#   0.55 .. 0.85  PRESSURE  beats 1 and 3
#   0.35 .. 0.55  BREATHER  beat 1 only (+ checkpoint if section start)
#   <  0.35       REST      nothing
#
# Type by the bar's dominant band:
#   low  -> slammer   (drops onto a lane on the beat, jumpable when down)
#   high -> pulser    (pillar up for half a beat, lane-dodge only)
#   mid  -> sweeper   (moving gap across one whole bar)
# ============================================================

const LANES := 3
const LANE_X := [-2.0, 0.0, 2.0]

# If true, each band is compared relative to its own peak over the song
# instead of raw level. Off by default (the brief's literal rule); left in
# because raw bass dominates nearly every bar of this track.
const NORMALISE_BANDS := false


static func density(energy: float) -> String:
	if energy >= 0.85:
		return "gauntlet"
	if energy >= 0.55:
		return "pressure"
	if energy >= 0.35:
		return "breather"
	return "rest"


static func beats_for(dens: String) -> Array:
	match dens:
		"gauntlet":
			return [0, 1, 2, 3]
		"pressure":
			return [0, 2]
		"breather":
			return [0]
	return []


static func kind_for(clock, bar: int, peaks: Dictionary) -> String:
	var best := "low"
	var best_v := -1.0
	for band in ["low", "mid", "high"]:
		var v: float = clock.bar_band(bar, band)
		if NORMALISE_BANDS and peaks[band] > 0.0:
			v /= peaks[band]
		if v > best_v:
			best_v = v
			best = band
	match best:
		"high":
			return "pulser"
		"mid":
			return "sweeper"
	return "slammer"


# Lanes a player can stand in during a beat slot, given what occupies it.
static func _safe_lanes(slot: Dictionary) -> Array:
	var safe := []
	for l in LANES:
		if not slot.get("blocked", []).has(l):
			safe.append(l)
	return safe


static func _reachable(prev_safe: Array, cur_safe: Array) -> bool:
	for p in prev_safe:
		for c in cur_safe:
			if absi(int(p) - int(c)) <= 1:
				return true
	return false


# Returns {"hazards": [...], "checkpoints": [...]}.
# hazard: bar, beat (0..3), t, kind, lane, dir
# checkpoint: bar, t (marker position), resume_t, lane (spawn lane)
static func build(clock) -> Dictionary:
	var hazards := []
	var checkpoints := []

	var peaks := {"low": 0.0, "mid": 0.0, "high": 0.0}
	for bar in range(1, clock.bar_count() + 1):
		for band in peaks.keys():
			peaks[band] = maxf(peaks[band], clock.bar_band(bar, band))

	# One slot per beat of the whole song so lane safety can be checked
	# across bar boundaries. slot = {"blocked": [lanes]}
	var slots := []
	var prev_slot := {"blocked": []}

	for bar in range(1, clock.bar_count() + 1):
		var dens := density(clock.bar_energy(bar))
		var kind := kind_for(clock, bar, peaks)
		var beat_ts: PackedFloat64Array = clock.bar_beats(bar)
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000003 * bar + 7

		var bar_slots := []
		for k in 4:
			bar_slots.append({"blocked": []})

		if dens != "rest" and kind == "sweeper":
			# One hazard spanning the bar. The gap starts on one edge lane
			# and travels to the other; dir picks which.
			var dir := 1 if rng.randi() % 2 == 0 else -1
			# Pick the direction whose starting gap is reachable from the
			# previous beat, if only one is.
			for attempt in 2:
				var start_lane := 0 if dir == 1 else 2
				if _reachable(_safe_lanes(prev_slot), [start_lane]):
					break
				dir = -dir
			hazards.append({"bar": bar, "beat": 0, "t": beat_ts[0], "kind": "sweeper",
				"lane": 1, "dir": dir})
			for k in 4:
				var gap_x: float = lerpf(-2.0 * dir, 2.0 * dir, k / 4.0)
				var blocked := []
				for l in LANES:
					if absf(LANE_X[l] - gap_x) > 1.0:
						blocked.append(l)
				bar_slots[k]["blocked"] = blocked
		else:
			for k in beats_for(dens):
				var lane := rng.randi() % LANES
				# Guarantee: a safe lane within one lane-width of the
				# previous beat's safe lanes. Re-pick deterministically.
				var prev: Dictionary = prev_slot if k == 0 else bar_slots[k - 1]
				for attempt in LANES:
					var cur := {"blocked": [lane]}
					if _reachable(_safe_lanes(prev), _safe_lanes(cur)):
						break
					lane = (lane + 1) % LANES
				bar_slots[k]["blocked"] = [lane]
				hazards.append({"bar": bar, "beat": k, "t": beat_ts[k], "kind": kind,
					"lane": lane, "dir": 1})

		if dens == "breather" and clock.is_section_start(bar):
			# Resume one beat BEFORE the bar so the player is never dropped
			# onto the bar's own beat-1 hazard. Spawn in a lane that is safe
			# on that first beat.
			var spawn_lane := 1
			var safe := _safe_lanes(bar_slots[0])
			if not safe.has(1):
				spawn_lane = int(safe[0])
			checkpoints.append({"bar": bar, "t": beat_ts[0],
				"resume_t": beat_ts[0] - clock.beat_interval, "lane": spawn_lane})

		for k in 4:
			slots.append(bar_slots[k])
		prev_slot = bar_slots[3]

	# Fair spawns (the 2D game's hard lesson): nothing may be waiting on
	# the beat a checkpoint resumes on. Drop any hazard within half a beat
	# of a resume point.
	for cp in checkpoints:
		var i := hazards.size() - 1
		while i >= 0:
			if absf(float(hazards[i]["t"]) - float(cp["resume_t"])) < clock.beat_interval * 0.5:
				hazards.remove_at(i)
			i -= 1

	return {"hazards": hazards, "checkpoints": checkpoints}
