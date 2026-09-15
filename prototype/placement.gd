extends RefCounted
# ============================================================
# PLACEMENT — turns the beatmap's per-bar numbers into a layout,
# shaped by a CURRICULUM (addendum 2): which hazard types are
# allowed from which bar, capped density, demo bars.
#
# Nothing here is hand-authored: a different song's beatmap gives a
# different level with zero code changes. Everything is seeded by
# bar number, so the level is identical on every run and device.
#
# Density by bar energy (capped by the curriculum):
#   >= 0.85       GAUNTLET  plate pattern + one secondary hazard
#   0.55 .. 0.85  PRESSURE  one hazard type
#   0.35 .. 0.55  BREATHER  open floor, note
#   <  0.35       REST      open floor
#
# Hard rule, enforced below: no hazard type becomes lethal before its
# demo bar has played. A demo bar shows the type in warning colour,
# non-lethal; the bar after it has exactly that type, live, at
# Pressure density, nothing else.
# ============================================================

const Rules := preload("res://prototype/rules.gd")
const HazardMath := preload("res://prototype/hazard_math.gd")

const DEMO_WORDS := {"plates": "FLOOR", "sweeper": "WALL", "gate": "GATE", "orbiter": "ORBIT"}

# Level 1 for this song. Bars are inclusive. "types" are what may be
# LIVE in the entry; "demo" names the type introduced by its first bar.
const LEVEL1 := [
	{"from": 1, "to": 8, "role": "wave", "types": ["plates"], "patterns": ["row", "checker"], "cap": "gauntlet", "demo": "plates"},
	{"from": 9, "to": 16, "role": "breather", "checkpoint": 9},
	{"from": 17, "to": 24, "role": "wave", "types": ["plates", "sweeper"], "patterns": ["row", "checker", "column_wave", "spiral"], "cap": "gauntlet", "demo": "sweeper"},
	{"from": 25, "to": 31, "role": "breather", "checkpoint": 25},
	{"from": 32, "to": 40, "role": "wave", "types": ["plates", "sweeper", "gate"], "patterns": ["row", "checker", "column_wave", "spiral"], "cap": "gauntlet", "demo": "gate"},
	{"from": 41, "to": 48, "role": "breather", "checkpoint": 41},
	{"from": 49, "to": 56, "role": "wave", "types": ["plates", "sweeper", "gate", "orbiter"], "patterns": ["row", "checker", "column_wave", "spiral"], "cap": "gauntlet", "demo": "orbiter", "force": {"orbiter": 2}},
	{"from": 57, "to": 78, "role": "wave", "types": ["plates", "sweeper", "gate", "orbiter"], "patterns": ["row", "checker", "column_wave"], "cap": "pressure"},
]

const DENSITY_RANK := {"rest": 0, "breather": 1, "pressure": 2, "gauntlet": 3}


static func density(energy: float) -> String:
	if energy >= 0.85:
		return "gauntlet"
	if energy >= 0.55:
		return "pressure"
	if energy >= 0.35:
		return "breather"
	return "rest"


static func _cap(dens: String, cap: String) -> String:
	if DENSITY_RANK[dens] > DENSITY_RANK[cap]:
		return cap
	return dens


static func dominant_band(clock, bar: int) -> String:
	var best := "low"
	var best_v := -1.0
	for band in ["low", "mid", "high"]:
		var v: float = clock.bar_band(bar, band)
		if v > best_v:
			best_v = v
			best = band
	return best


static func _weighted(rng: RandomNumberGenerator, options: Dictionary) -> String:
	var total := 0.0
	for k in options:
		total += float(options[k])
	var r := rng.randf() * total
	for k in options:
		r -= float(options[k])
		if r <= 0.0:
			return String(k)
	return String(options.keys()[0])


static func _entry_for(curriculum: Array, bar: int) -> Dictionary:
	for e in curriculum:
		if bar >= int(e["from"]) and bar <= int(e["to"]):
			return e
	return {"from": bar, "to": bar, "role": "wave", "types": ["plates", "sweeper", "gate", "orbiter"],
		"patterns": Rules.PATTERNS, "cap": "gauntlet"}


# Band -> secondary type bias, restricted to the allowed types.
static func _secondary(rng: RandomNumberGenerator, band: String, allowed: Array) -> String:
	var w := {}
	match band:
		"low":
			w = {"gate": 0.6, "sweeper": 0.2, "orbiter": 0.2}
		"mid":
			w = {"sweeper": 0.5, "orbiter": 0.3, "gate": 0.2}
		_:
			w = {"orbiter": 0.5, "sweeper": 0.3, "gate": 0.2}
	var opts := {}
	for k in w:
		if allowed.has(k):
			opts[k] = w[k]
	if opts.is_empty():
		return ""
	return _weighted(rng, opts)


# Returns {"bars": {bar: {...}}, "hazards": [...], "notes": [...], "checkpoints": [...],
#          "demo_bars": {bar: type}}
# bar entry: density, pattern, plain_rows, pits, checkpoint, demo (bool: plates non-lethal), word
# hazard: kind, bar, x, z, dir, phase, seed, beat, col, row, demo
static func build(clock, rerolls: Dictionary = {}, curriculum: Array = LEVEL1) -> Dictionary:
	var bars := {}
	var hazards := []
	var notes := []
	var checkpoints := []
	var demo_bars := {}
	var prev_had_gate := false    # live gate in the previous bar: no sweeper right after it
	var after_gate := false       # any gate (demo or live) in the previous bar: its first row is plain
	var seen := {}                # type -> first bar it was live (demo bar counts as introduced)
	var orbiter_bars := {}        # entry.from -> count

	for bar in range(1, clock.bar_count() + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000003 * bar + 7 + 7919 * int(rerolls.get(bar, 0))
		var e := _entry_for(curriculum, bar)
		var band := dominant_band(clock, bar)
		var z0: float = clock.z_at(clock.bar_start(bar))
		var z1: float = clock.z_at(clock.bar_end(bar))
		var zc := (z0 + z1) * 0.5
		var depth := z1 - z0
		var entry := {"density": "rest", "pattern": "none", "plain_rows": [], "pits": [],
			"checkpoint": false, "demo": false, "word": ""}
		var role := String(e["role"])
		var demo_type := String(e.get("demo", ""))
		var is_demo_bar := demo_type != "" and bar == int(e["from"])
		var is_after_demo := demo_type != "" and bar == int(e["from"]) + 1
		var allowed: Array = e.get("types", [])
		var patterns: Array = e.get("patterns", Rules.PATTERNS)

		if role == "breather" or (role == "wave" and not is_demo_bar and not is_after_demo
				and _cap(density(clock.bar_energy(bar)), String(e.get("cap", "gauntlet"))) in ["breather", "rest"]):
			# Open floor. A note now and then, a checkpoint where the curriculum says.
			var dens := density(clock.bar_energy(bar))
			entry["density"] = "breather" if dens != "rest" else "rest"
			if role == "breather" and int(e.get("checkpoint", -1)) == bar:
				entry["checkpoint"] = true
				var lead: float = Rules.WINDOW_DEPTH * 0.45 / clock.track_speed
				var t0: float = clock.bar_start(bar)
				checkpoints.append({"bar": bar, "t": t0, "resume_t": maxf(0.0, t0 - lead), "x": 0.0, "z": z0 + 1.0})
			if rng.randf() < 0.6:
				var col := rng.randi() % Rules.COLS
				var row := (1 + rng.randi() % 3) if entry["checkpoint"] else (rng.randi() % Rules.ROWS)
				notes.append({"x": Rules.col_x(col), "z": _row_z(z0, depth, row), "bar": bar})
		elif is_demo_bar:
			# The type shows itself, non-lethal, alone.
			entry["density"] = "demo"
			entry["word"] = String(DEMO_WORDS.get(demo_type, ""))
			demo_bars[bar] = demo_type
			seen[demo_type] = bar
			match demo_type:
				"plates":
					entry["pattern"] = String(patterns[rng.randi() % patterns.size()])
					entry["demo"] = true
				"sweeper":
					hazards.append(_sweeper(bar, zc, rng, _sweeper_phase(bar), true))
					entry["plain_rows"] = [1, 2]
				"gate":
					hazards.append(_gate(bar, z1 - 0.5, rng, true))
					entry["plain_rows"] = [Rules.ROWS - 1]
				"orbiter":
					hazards.append_array(_orbiter_pair(bar, zc, true))
		elif is_after_demo:
			# Exactly the demoed type, live, at Pressure density, nothing else.
			entry["density"] = "pressure"
			match demo_type:
				"plates":
					entry["pattern"] = String(patterns[rng.randi() % patterns.size()])
				"sweeper":
					hazards.append(_sweeper(bar, zc, rng, _sweeper_phase(bar), false))
					entry["plain_rows"] = [1, 2]
					notes.append(_sweeper_note(hazards[-1], clock, bar))
				"gate":
					hazards.append(_gate(bar, z1 - 0.5, rng, false))
					entry["plain_rows"] = [Rules.ROWS - 1]
					notes.append(_gate_note(z1, rng, bar))
				"orbiter":
					hazards.append_array(_orbiter_pair(bar, zc, false))
					notes.append({"x": 0.0, "z": zc, "bar": bar})
		else:
			var dens := _cap(density(clock.bar_energy(bar)), String(e.get("cap", "gauntlet")))
			entry["density"] = dens
			var second := ""
			var secondary_allowed := []
			for tname in allowed:
				if tname != "plates":
					secondary_allowed.append(tname)
			if dens == "gauntlet":
				if allowed.has("plates"):
					entry["pattern"] = String(patterns[rng.randi() % patterns.size()])
				second = _secondary(rng, band, secondary_allowed)
			elif dens == "pressure":
				second = _secondary(rng, band, secondary_allowed)
				if second == "" and allowed.has("plates"):
					entry["pattern"] = String(patterns[rng.randi() % patterns.size()])
			if second == "sweeper" and prev_had_gate:
				second = "gate" if secondary_allowed.has("gate") else ""
			# Forced orbiter bars in the entry that asks for them.
			var need: int = int(e.get("force", {}).get("orbiter", 0))
			var have: int = int(orbiter_bars.get(int(e["from"]), 0))
			if second != "" and second != "orbiter" and need > have and secondary_allowed.has("orbiter") \
					and (int(e["to"]) - bar) <= (need - have) + 1:
				second = "orbiter"
			match second:
				"sweeper":
					hazards.append(_sweeper(bar, zc, rng, _sweeper_phase(bar), false))
					entry["plain_rows"] = [1, 2]
					notes.append(_sweeper_note(hazards[-1], clock, bar))
				"gate":
					hazards.append(_gate(bar, z1 - 0.5, rng, false))
					entry["plain_rows"] = [Rules.ROWS - 1]
					notes.append(_gate_note(z1, rng, bar))
				"orbiter":
					hazards.append_array(_orbiter_pair(bar, zc, false))
					notes.append({"x": 0.0, "z": zc, "bar": bar})
					orbiter_bars[int(e["from"])] = have + 1
			if String(entry["pattern"]) != "none":
				var n := 1 + rng.randi() % 2
				for tile in _riskiest_tiles(String(entry["pattern"]), entry["plain_rows"], rng, n):
					notes.append({"x": Rules.col_x(int(tile.x)), "z": _row_z(z0, depth, int(tile.y)), "bar": bar})
			if second != "":
				seen[second] = mini(int(seen.get(second, bar)), bar)

		# Milko, 2026-09-15: a player who has just come through a gate has
		# no attention to spare for plates, so the row after every gate is
		# plain (the row before it already is).
		if after_gate and not entry["plain_rows"].has(0):
			entry["plain_rows"].append(0)
			var kept := []
			for n in notes:
				if int(n["bar"]) != bar or absf(float(n["z"]) - _row_z(z0, depth, 0)) > 0.01:
					kept.append(n)
			notes = kept
		prev_had_gate = false
		after_gate = false
		for h in hazards:
			if h["bar"] == bar and h["kind"] == "gate":
				after_gate = true
				if not h["demo"]:
					prev_had_gate = true
		bars[bar] = entry

	# Hard rule: nothing lethal before its demo bar. (Plates: bar 1 is the
	# demo; the intro rehearsal shows them too.)
	for h in hazards:
		if h["demo"]:
			continue
		var intro := _demo_bar_for(curriculum, String(h["kind"]))
		if intro > 0 and int(h["bar"]) <= intro:
			push_error("CURRICULUM: %s live in bar %d before its demo bar %d" % [h["kind"], h["bar"], intro])
	var plate_demo := _demo_bar_for(curriculum, "plates")
	for bar in bars:
		var en: Dictionary = bars[bar]
		if String(en["pattern"]) != "none" and not en["demo"] and plate_demo > 0 and int(bar) <= plate_demo:
			push_error("CURRICULUM: plates live in bar %d before their demo bar %d" % [bar, plate_demo])

	return {"bars": bars, "hazards": hazards, "notes": notes, "checkpoints": checkpoints, "demo_bars": demo_bars}


static func _demo_bar_for(curriculum: Array, kind: String) -> int:
	for e in curriculum:
		if String(e.get("demo", "")) == kind:
			return int(e["from"])
	return 0


static func _row_z(z0: float, depth: float, row: int) -> float:
	return z0 + (row + 0.5) * depth / Rules.ROWS


static func _sweeper(bar: int, zc: float, rng: RandomNumberGenerator, phase: float, demo: bool) -> Dictionary:
	return {"kind": "sweeper", "bar": bar, "x": 0.0, "z": zc, "dir": 1 if rng.randi() % 2 == 0 else -1,
		"phase": phase, "seed": bar, "beat": 0, "col": 0, "row": 0, "demo": demo}


# Sweeper phase from the bar number alone (so re-rolling one bar never
# shifts another). Consecutive bars differ by ~4-6 units of gap travel.
static func _sweeper_phase(bar: int) -> float:
	return fposmod(bar * 0.2137 + 0.05, 1.0)


static func _gate(bar: int, z: float, rng: RandomNumberGenerator, demo: bool) -> Dictionary:
	return {"kind": "gate", "bar": bar, "x": 0.0, "z": z, "dir": 1, "phase": 0.0,
		"seed": int(rng.randi() % 100000), "beat": 0, "col": 0, "row": 0, "demo": demo}


# The classic pair: side by side, opposite spin, orbs opposed.
static func _orbiter_pair(bar: int, zc: float, demo: bool) -> Array:
	return [
		{"kind": "orbiter", "bar": bar, "x": -4.0, "z": zc, "dir": 1, "phase": 0.0, "seed": bar,
			"beat": 0, "col": 0, "row": 0, "demo": demo},
		{"kind": "orbiter", "bar": bar, "x": 4.0, "z": zc, "dir": -1, "phase": PI, "seed": bar,
			"beat": 0, "col": 0, "row": 0, "demo": demo},
	]


# The note sits in the wall line where the gap is at mid-bar: you only
# get it by threading the gap at that moment.
static func _sweeper_note(spec: Dictionary, clock, bar: int) -> Dictionary:
	var t_mid: float = (clock.bar_start(bar) + clock.bar_end(bar)) * 0.5
	var gx := HazardMath.sweeper_gap_x(spec, t_mid)
	return {"x": gx, "z": float(spec["z"]), "bar": bar}


# Just before the gate, hugging an edge: the risky way to line up.
static func _gate_note(z1: float, rng: RandomNumberGenerator, bar: int) -> Dictionary:
	var side := -1.0 if rng.randi() % 2 == 0 else 1.0
	return {"x": side * (Rules.half_width() - 1.0), "z": z1 - 1.6, "bar": bar}


# Tiles lethal on the most beats of the pattern (seeded among ties).
static func _riskiest_tiles(pattern: String, plain_rows: Array, rng: RandomNumberGenerator, n: int) -> Array:
	var scored := []
	for col in Rules.COLS:
		for row in Rules.ROWS:
			if plain_rows.has(row):
				continue
			var c := 0
			for k in 4:
				if Rules.pattern_lethal(pattern, col, row, k):
					c += 1
			scored.append({"t": Vector2i(col, row), "c": c, "r": rng.randf()})
	scored.sort_custom(func(a, b): return a["c"] > b["c"] if a["c"] != b["c"] else a["r"] < b["r"])
	var out := []
	for i in mini(n, scored.size()):
		out.append(scored[i]["t"])
	return out
