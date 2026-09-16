extends RefCounted
# ============================================================
# PLACEMENT — turns the beatmap's bars into a layout, shaped by a
# CURRICULUM (addendum 3: concrete before abstract) and the level's
# knobs (Rules.LEVELS).
#
# Nothing here is hand-authored: a different song's beatmap gives a
# different level with zero code changes. Everything is seeded by
# bar number, so the level is identical on every run and device.
#
# Level 1 (addendum 3 section 3):
#   1-8   doorways   a gate every second bar, a pit in the bars between
#   9-16  breather   checkpoint at 9
#   17-24 thrown     volleys and slammers, one per bar
#   25-31 breather   checkpoint at 25
#   32-40 walls      sweepers (one gate allowed)
#   41-48 breather   checkpoint at 41
#   49-56 orbiters   single orbiters (gates allowed)
#   57-64 floor      plates, at most 4 tiles per bar: a row segment or a 2x2 block
#   65-    outro     one of the above every other bar, breather density
#
# Hard rules, enforced below: never two hazard types in one bar; plates
# never before the floor wave; no beat-rate patterns (checker, spiral,
# column_wave) in level 1; nothing lethal before its demo bar, per type
# AND per plate pattern; plain rows before and after every gate and on
# both sides of every sweeper.
# ============================================================

const Rules := preload("res://prototype/rules.gd")
const HazardMath := preload("res://prototype/hazard_math.gd")

const DEMO_WORDS := {"plates": "FLOOR", "sweeper": "WALL", "gate": "GATE", "orbiter": "ORBIT",
	"volley": "VOLLEY", "slammer": "SLAM"}

const LEVEL1 := [
	{"from": 1, "to": 8, "wave": "doorways"},
	{"from": 9, "to": 16, "wave": "breather", "checkpoint": 9},
	{"from": 17, "to": 24, "wave": "thrown"},
	{"from": 25, "to": 31, "wave": "breather", "checkpoint": 25},
	{"from": 32, "to": 40, "wave": "walls"},
	{"from": 41, "to": 48, "wave": "breather", "checkpoint": 41},
	{"from": 49, "to": 56, "wave": "orbiters"},
	{"from": 57, "to": 64, "wave": "floor"},
	{"from": 65, "to": 9999, "wave": "outro"},
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


static func _entry_for(curriculum: Array, bar: int) -> Dictionary:
	for e in curriculum:
		if bar >= int(e["from"]) and bar <= int(e["to"]):
			return e
	return {"from": bar, "to": bar, "wave": "outro"}


# Returns {"bars": {bar: {...}}, "hazards": [...], "notes": [...], "checkpoints": [...],
#          "demo_bars": {bar: type}}
# bar entry: density, pattern, plates, plain_rows, pits, checkpoint, demo, word
# hazard: kind, bar, x, z, dir, phase, seed, beat, col, row, cycle, demo
static func build(clock, rerolls: Dictionary = {}, curriculum: Array = LEVEL1) -> Dictionary:
	var bars := {}
	var hazards := []
	var notes := []
	var checkpoints := []
	var demo_bars := {}
	var after_gate := false
	var shown := []              # hazard kinds / plate patterns demoed so far, in order
	var gate_in_wave := {}       # wave "from" -> a gate has been used in that wave
	var allowed_patterns: Array = Rules.level()["plate_patterns"]
	var max_plates: int = maxi(1, int(floor(float(Rules.level()["plate_coverage"]) * Rules.COLS * Rules.ROWS)))

	for bar in range(1, clock.bar_count() + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000003 * bar + 7 + 7919 * int(rerolls.get(bar, 0))
		var e := _entry_for(curriculum, bar)
		var z0: float = clock.z_at(clock.bar_start(bar))
		var z1: float = clock.z_at(clock.bar_end(bar))
		var zc := (z0 + z1) * 0.5
		var depth := z1 - z0
		var entry := {"density": "rest", "pattern": "none", "plates": [], "plain_rows": [], "pits": [],
			"checkpoint": false, "demo": false, "word": ""}
		var wave := String(e["wave"])
		var k: int = bar - int(e["from"])
		var placed := ""          # the one hazard kind in this bar ("" = open floor)
		var demo := false

		match wave:
			"doorways":
				if k % 2 == 0:
					placed = "gate"
					demo = (k == 0)
					hazards.append(_gate(bar, z1 - 0.5, rng, demo))
					entry["plain_rows"] = [Rules.ROWS - 1]
					if not demo:
						notes.append(_gate_note(z1, rng, bar))
				else:
					# One pit, one tile, in a middle row (rows 0 and 3 stay plain
					# around the gates).
					placed = "pit"
					entry["pits"] = [[rng.randi() % Rules.COLS, 1 + rng.randi() % 2]]
			"breather":
				_open_floor(entry, e, bar, z0, depth, clock, rng, notes, checkpoints)
			"thrown":
				# Two demos, two words, then one thrown hazard per bar.
				var kind := ""
				match k:
					0:
						kind = "volley"
						demo = true
					1:
						kind = "slammer"
						demo = true
					2:
						kind = "volley"
					3:
						kind = "slammer"
					_:
						kind = "volley" if rng.randi() % 2 == 0 else "slammer"
				placed = kind
				# Fires in the period the player is normally passing through
				# this bar (period bar-1), warns the period before.
				var cycle := (bar - 1) % 2
				if kind == "volley":
					var row := rng.randi() % Rules.ROWS
					hazards.append(_volley(bar, _row_z(z0, depth, row), rng, cycle, demo))
				else:
					var col := rng.randi() % Rules.COLS
					var row := 1 + rng.randi() % 2
					hazards.append(_slammer(bar, Rules.col_x(col), _row_z(z0, depth, row), cycle, demo))
			"walls":
				if k == 0 or k == 1:
					placed = "sweeper"
					demo = (k == 0)
				elif not gate_in_wave.get(int(e["from"]), false) and not after_gate and rng.randf() < 0.3:
					placed = "gate"
					gate_in_wave[int(e["from"])] = true
				elif rng.randf() < 0.7:
					placed = "sweeper"
				match placed:
					"sweeper":
						hazards.append(_sweeper(bar, zc, rng, _sweeper_phase(bar), demo))
						entry["plain_rows"] = [1, 2]
						if not demo:
							notes.append(_sweeper_note(hazards[-1], clock, bar))
					"gate":
						hazards.append(_gate(bar, z1 - 0.5, rng, false))
						entry["plain_rows"] = [Rules.ROWS - 1]
						notes.append(_gate_note(z1, rng, bar))
			"orbiters":
				if k == 0 or k == 1:
					placed = "orbiter"
					demo = (k == 0)
				elif not gate_in_wave.get(int(e["from"]), false) and not after_gate and rng.randf() < 0.25:
					placed = "gate"
					gate_in_wave[int(e["from"])] = true
				elif rng.randf() < 0.65:
					placed = "orbiter"
				match placed:
					"orbiter":
						var x: float = [-4.0, 0.0, 4.0][rng.randi() % 3]
						if bool(Rules.level()["orbiter_pairs"]):
							hazards.append_array(_orbiter_pair(bar, zc, demo))
						else:
							hazards.append(_orbiter(bar, x, zc, rng, demo))
						if not demo:
							notes.append({"x": x + (2.0 if x <= 0.0 else -2.0), "z": zc, "bar": bar})
					"gate":
						hazards.append(_gate(bar, z1 - 0.5, rng, false))
						entry["plain_rows"] = [Rules.ROWS - 1]
						notes.append(_gate_note(z1, rng, bar))
			"floor":
				# Each allowed pattern gets its own demo bar, then a live bar.
				var pattern := ""
				if k < allowed_patterns.size() * 2:
					pattern = String(allowed_patterns[k / 2])
					demo = (k % 2 == 0)
				elif rng.randf() < 0.7:
					pattern = String(allowed_patterns[rng.randi() % allowed_patterns.size()])
				if pattern != "":
					placed = "plates"
					entry["pattern"] = pattern
					entry["plates"] = _plate_tiles(pattern, rng, max_plates)
			"outro":
				# Nothing new, nothing dense: one thing already shown, every other bar.
				if k % 2 == 0 and bar <= clock.bar_count() - 2 and not shown.is_empty():
					var kind := String(shown[rng.randi() % shown.size()])
					if kind in ["row", "block"]:
						placed = "plates"
						entry["pattern"] = kind
						entry["plates"] = _plate_tiles(kind, rng, max_plates)
					else:
						placed = kind
						match kind:
							"gate":
								hazards.append(_gate(bar, z1 - 0.5, rng, false))
								entry["plain_rows"] = [Rules.ROWS - 1]
							"sweeper":
								hazards.append(_sweeper(bar, zc, rng, _sweeper_phase(bar), false))
								entry["plain_rows"] = [1, 2]
							"orbiter":
								hazards.append(_orbiter(bar, [-4.0, 0.0, 4.0][rng.randi() % 3], zc, rng, false))
							"volley":
								hazards.append(_volley(bar, _row_z(z0, depth, rng.randi() % Rules.ROWS), rng, (bar - 1) % 2, false))
							"slammer":
								hazards.append(_slammer(bar, Rules.col_x(rng.randi() % Rules.COLS), _row_z(z0, depth, 1 + rng.randi() % 2), (bar - 1) % 2, false))
				if placed == "":
					_open_floor(entry, e, bar, z0, depth, clock, rng, notes, checkpoints)

		if placed != "":
			entry["density"] = "breather" if wave == "outro" else "pressure"
		if demo:
			entry["demo"] = true
			entry["density"] = "demo"
			var shown_as := String(entry["pattern"]) if placed == "plates" else placed
			entry["word"] = String(DEMO_WORDS.get(placed, ""))
			demo_bars[bar] = placed
			if not shown.has(shown_as):
				shown.append(shown_as)

		# Milko, 2026-09-15: a player who has just come through a gate has
		# no attention to spare, so the row after every gate is plain too.
		if after_gate and not entry["plain_rows"].has(0):
			entry["plain_rows"].append(0)
		var kept_plates := []
		for tile in entry["plates"]:
			if not entry["plain_rows"].has(int(tile[1])):
				kept_plates.append(tile)
		entry["plates"] = kept_plates
		after_gate = (placed == "gate")
		bars[bar] = entry

	_check(bars, hazards, demo_bars)
	return {"bars": bars, "hazards": hazards, "notes": notes, "checkpoints": checkpoints, "demo_bars": demo_bars}


# Open floor: a note now and then, a checkpoint where the curriculum says.
static func _open_floor(entry: Dictionary, e: Dictionary, bar: int, z0: float, depth: float, clock,
		rng: RandomNumberGenerator, notes: Array, checkpoints: Array) -> void:
	entry["density"] = "breather" if density(clock.bar_energy(bar)) != "rest" else "rest"
	if int(e.get("checkpoint", -1)) == bar:
		entry["checkpoint"] = true
		var lead: float = Rules.WINDOW_DEPTH * 0.45 / clock.track_speed
		var t0: float = clock.bar_start(bar)
		checkpoints.append({"bar": bar, "t": t0, "resume_t": maxf(0.0, t0 - lead), "x": 0.0, "z": z0 + 1.0})
	if rng.randf() < 0.6:
		var col := rng.randi() % Rules.COLS
		var row := (1 + rng.randi() % 3) if entry["checkpoint"] else (rng.randi() % Rules.ROWS)
		notes.append({"x": Rules.col_x(col), "z": _row_z(z0, depth, row), "bar": bar})


# The hard rules. Any violation is a generator bug and goes to the log.
static func _check(bars: Dictionary, hazards: Array, demo_bars: Dictionary) -> void:
	var first_demo := {}
	for bar in demo_bars:
		var kind := String(demo_bars[bar])
		var key := kind
		if kind == "plates":
			key = "plates:" + String(bars[bar]["pattern"])
		if not first_demo.has(key) or int(bar) < int(first_demo[key]):
			first_demo[key] = int(bar)
	var kinds_in_bar := {}
	for h in hazards:
		var b := int(h["bar"])
		var kind := String(h["kind"])
		if not kinds_in_bar.has(b):
			kinds_in_bar[b] = []
		if not kinds_in_bar[b].has(kind):
			kinds_in_bar[b].append(kind)
		if not h["demo"]:
			var intro := int(first_demo.get(kind, 0))
			if intro == 0 or b <= intro:
				push_error("CURRICULUM: %s live in bar %d before its demo bar %d" % [kind, b, intro])
	for bar in bars:
		var en: Dictionary = bars[bar]
		if not en["plates"].is_empty():
			var key := "plates:" + String(en["pattern"])
			var intro := int(first_demo.get(key, 0))
			if not en["demo"] and (intro == 0 or int(bar) <= intro):
				push_error("CURRICULUM: plates (%s) live in bar %d before their demo bar %d" % [en["pattern"], bar, intro])
			if not kinds_in_bar.has(bar):
				kinds_in_bar[bar] = []
			kinds_in_bar[bar].append("plates")
		if String(en["pattern"]) in Rules.BEAT_PATTERNS:
			push_error("CURRICULUM: beat-rate pattern %s in bar %d (level 3+ material)" % [en["pattern"], bar])
		if not en["pits"].is_empty():
			if not kinds_in_bar.has(bar):
				kinds_in_bar[bar] = []
			kinds_in_bar[bar].append("pit")
	for bar in kinds_in_bar:
		if kinds_in_bar[bar].size() > int(Rules.level()["types_per_bar"]):
			push_error("CURRICULUM: %d hazard types in bar %d: %s" % [kinds_in_bar[bar].size(), bar, str(kinds_in_bar[bar])])


static func _row_z(z0: float, depth: float, row: int) -> float:
	return z0 + (row + 0.5) * depth / Rules.ROWS


# Plate tiles for level 1's two patterns: a short `row` segment or a
# 2x2 `block`, never more than max_tiles.
static func _plate_tiles(pattern: String, rng: RandomNumberGenerator, max_tiles: int) -> Array:
	var out := []
	match pattern:
		"block":
			var col := rng.randi() % (Rules.COLS - 1)
			var row := rng.randi() % (Rules.ROWS - 1)
			for dc in 2:
				for dr in 2:
					out.append([col + dc, row + dr])
		_:
			var n := mini(max_tiles, 3 + rng.randi() % 2)
			var col := rng.randi() % (Rules.COLS - n + 1)
			var row := rng.randi() % Rules.ROWS
			for dc in n:
				out.append([col + dc, row])
	while out.size() > max_tiles:
		out.pop_back()
	return out


static func _sweeper(bar: int, zc: float, rng: RandomNumberGenerator, phase: float, demo: bool) -> Dictionary:
	return {"kind": "sweeper", "bar": bar, "x": 0.0, "z": zc, "dir": 1 if rng.randi() % 2 == 0 else -1,
		"phase": phase, "seed": bar, "beat": 0, "col": 0, "row": 0, "cycle": 0, "demo": demo}


# Sweeper phase from the bar number alone (so re-rolling one bar never
# shifts another). Consecutive bars differ by ~4-6 units of gap travel.
static func _sweeper_phase(bar: int) -> float:
	return fposmod(bar * 0.2137 + 0.05, 1.0)


static func _gate(bar: int, z: float, rng: RandomNumberGenerator, demo: bool) -> Dictionary:
	return {"kind": "gate", "bar": bar, "x": 0.0, "z": z, "dir": 1, "phase": 0.0,
		"seed": int(rng.randi() % 100000), "beat": 0, "col": 0, "row": 0, "cycle": 0, "demo": demo}


static func _orbiter(bar: int, x: float, zc: float, rng: RandomNumberGenerator, demo: bool) -> Dictionary:
	return {"kind": "orbiter", "bar": bar, "x": x, "z": zc, "dir": 1 if rng.randi() % 2 == 0 else -1,
		"phase": 0.0, "seed": bar, "beat": 0, "col": 0, "row": 0, "cycle": 0, "demo": demo}


# The classic pair: side by side, opposite spin, orbs opposed (level 2+).
static func _orbiter_pair(bar: int, zc: float, demo: bool) -> Array:
	return [
		{"kind": "orbiter", "bar": bar, "x": -4.0, "z": zc, "dir": 1, "phase": 0.0, "seed": bar,
			"beat": 0, "col": 0, "row": 0, "cycle": 0, "demo": demo},
		{"kind": "orbiter", "bar": bar, "x": 4.0, "z": zc, "dir": -1, "phase": PI, "seed": bar,
			"beat": 0, "col": 0, "row": 0, "cycle": 0, "demo": demo},
	]


static func _volley(bar: int, z: float, rng: RandomNumberGenerator, cycle: int, demo: bool) -> Dictionary:
	return {"kind": "volley", "bar": bar, "x": 0.0, "z": z, "dir": 1 if rng.randi() % 2 == 0 else -1,
		"phase": 0.0, "seed": bar, "beat": 0, "col": 0, "row": 0, "cycle": cycle, "demo": demo}


static func _slammer(bar: int, x: float, z: float, cycle: int, demo: bool) -> Dictionary:
	return {"kind": "slammer", "bar": bar, "x": x, "z": z, "dir": 1, "phase": 0.0, "seed": bar,
		"beat": 0, "col": 0, "row": 0, "cycle": cycle, "demo": demo}


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
