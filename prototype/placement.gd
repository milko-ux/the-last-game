extends RefCounted
# ============================================================
# PLACEMENT — turns the beatmap's per-bar numbers into a layout.
#
# Nothing here is hand-authored: a different song's beatmap gives
# a different level with zero code changes. Everything is seeded
# by bar number, so the level is identical on every run and device.
#
# Density by bar energy (addendum):
#   >= 0.85       GAUNTLET  pulse-plate pattern + one sweeper or gate, 2-3 notes
#   0.55 .. 0.85  PRESSURE  one hazard type (orbiter pair / sweeper / gate), 1-2 notes
#   0.35 .. 0.55  BREATHER  open floor, maybe one pit, checkpoint if section start, 1 note
#   <  0.35       REST      open floor, nothing
#
# Band -> type BIAS (weighted, not a hard mapping): low favours
# slammer/gate, mid favours sweeper/orbiter, high favours pulse
# patterns. This track's bass dominates almost every bar, so a hard
# mapping would have produced one hazard type for the whole song.
#
# Notes go on the RISKIER route: the tile lethal most often, inside
# the sweeper's gap at mid-bar, between the orbiters, hugging the
# edge beside a gate.
# ============================================================

const Rules := preload("res://prototype/rules.gd")
const HazardMath := preload("res://prototype/hazard_math.gd")


static func density(energy: float) -> String:
	if energy >= 0.85:
		return "gauntlet"
	if energy >= 0.55:
		return "pressure"
	if energy >= 0.35:
		return "breather"
	return "rest"


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


# Returns {"bars": {bar: {...}}, "hazards": [...], "notes": [...], "checkpoints": [...]}
# bar entry: density, pattern, pits [[col,row]], checkpoint
# hazard: kind, bar, x, z, dir, phase, seed, beat, col, row
# note: x, z, bar
# checkpoint: bar, t, resume_t, x, z
# rerolls: {bar: n} — bars the fairness validator rejected get a fresh
# seed per attempt (see Field.build). Still fully deterministic.
static func build(clock, rerolls: Dictionary = {}) -> Dictionary:
	var bars := {}
	var hazards := []
	var notes := []
	var checkpoints := []
	var prev_had_gate := false

	for bar in range(1, clock.bar_count() + 1):
		var rng := RandomNumberGenerator.new()
		rng.seed = 1000003 * bar + 7 + 7919 * int(rerolls.get(bar, 0))
		var dens := density(clock.bar_energy(bar))
		var band := dominant_band(clock, bar)
		var z0: float = clock.z_at(clock.bar_start(bar))
		var z1: float = clock.z_at(clock.bar_end(bar))
		var zc := (z0 + z1) * 0.5
		var depth := z1 - z0
		# plain_rows: tile rows the floor pattern leaves alone. A gate bar
		# keeps its front row plain (a strip to line up the opening); a
		# sweeper bar keeps the two rows either side of the wall plain (the
		# crossing zone). Otherwise the floor and the wall fight and no
		# legal move exists.
		var entry := {"density": dens, "pattern": "none", "pits": [], "checkpoint": false, "plain_rows": []}
		var is_cp: bool = dens == "breather" and clock.is_section_start(bar)

		match dens:
			"gauntlet":
				entry["pattern"] = Rules.PATTERNS[rng.randi() % Rules.PATTERNS.size()]
				var second := _weighted(rng, {"gate": 0.6, "sweeper": 0.4} if band == "low"
					else ({"sweeper": 0.6, "gate": 0.4} if band == "mid" else {"gate": 0.5, "sweeper": 0.5}))
				if prev_had_gate:
					second = "gate"
				if second == "sweeper":
					hazards.append(_sweeper(bar, zc, rng, _sweeper_phase(bar)))
					notes.append(_sweeper_note(hazards[-1], clock, bar))
					entry["plain_rows"] = [1, 2]
				else:
					hazards.append(_gate(bar, z1 - 0.5, rng))
					notes.append(_gate_note(z1, rng, bar))
					entry["plain_rows"] = [Rules.ROWS - 1]
				if band == "low" and rng.randf() < 0.5:
					var col := rng.randi() % Rules.COLS
					var row := 1 + rng.randi() % 2
					hazards.append({"kind": "slammer", "bar": bar, "x": Rules.col_x(col),
						"z": _row_z(z0, depth, row), "beat": rng.randi() % 4, "col": col, "row": row,
						"dir": 1, "phase": 0.0, "seed": bar})
				var n := 1 + rng.randi() % 2   # 1-2 pattern notes + 1 secondary = 2-3
				for tile in _riskiest_tiles(String(entry["pattern"]), rng, n):
					notes.append({"x": Rules.col_x(int(tile.x)), "z": _row_z(z0, depth, int(tile.y)), "bar": bar})
			"pressure":
				var kind := _weighted(rng, {"gate": 0.6, "orbiter": 0.2, "sweeper": 0.2} if band == "low"
					else ({"sweeper": 0.5, "orbiter": 0.5} if band == "mid" else {"orbiter": 0.6, "sweeper": 0.4}))
				if prev_had_gate and kind == "sweeper":
					kind = "gate"
				match kind:
					"sweeper":
						hazards.append(_sweeper(bar, zc, rng, _sweeper_phase(bar)))
						notes.append(_sweeper_note(hazards[-1], clock, bar))
					"gate":
						hazards.append(_gate(bar, z1 - 0.5, rng))
						notes.append(_gate_note(z1, rng, bar))
					"orbiter":
						# The classic pair: side by side, opposite spin, orbs opposed.
						hazards.append({"kind": "orbiter", "bar": bar, "x": -3.5, "z": zc, "dir": 1,
							"phase": 0.0, "seed": bar, "beat": 0, "col": 0, "row": 0})
						hazards.append({"kind": "orbiter", "bar": bar, "x": 3.5, "z": zc, "dir": -1,
							"phase": PI, "seed": bar, "beat": 0, "col": 0, "row": 0})
						notes.append({"x": 0.0, "z": zc, "bar": bar})
				if rng.randf() < 0.5:
					var col := rng.randi() % Rules.COLS
					var row := rng.randi() % Rules.ROWS
					notes.append({"x": Rules.col_x(col), "z": _row_z(z0, depth, row), "bar": bar})
			"breather":
				entry["checkpoint"] = is_cp
				var pit_col := -1
				var pit_row := -1
				if not is_cp and rng.randf() < 0.5:
					pit_col = rng.randi() % Rules.COLS
					pit_row = 1 + rng.randi() % 2
					entry["pits"].append([pit_col, pit_row])
				var col := rng.randi() % Rules.COLS
				var row := (1 + rng.randi() % 3) if is_cp else (rng.randi() % Rules.ROWS)
				if col == pit_col and row == pit_row:
					col = (col + 1) % Rules.COLS
				notes.append({"x": Rules.col_x(col), "z": _row_z(z0, depth, row), "bar": bar})
				if is_cp:
					var t0: float = clock.bar_start(bar)
					# Resume with the marker a third of the window ahead of the
					# back edge, standing on the open checkpoint bar.
					var lead: float = Rules.WINDOW_DEPTH * 0.35 / clock.track_speed
					checkpoints.append({"bar": bar, "t": t0, "resume_t": maxf(0.0, t0 - lead),
						"x": 0.0, "z": z0 + 1.0})
			_:
				pass
		prev_had_gate = false
		for h in hazards:
			if h["bar"] == bar and h["kind"] == "gate":
				prev_had_gate = true
		bars[bar] = entry

	return {"bars": bars, "hazards": hazards, "notes": notes, "checkpoints": checkpoints}


static func _row_z(z0: float, depth: float, row: int) -> float:
	return z0 + (row + 0.5) * depth / Rules.ROWS


static func _sweeper(bar: int, zc: float, rng: RandomNumberGenerator, phase: float) -> Dictionary:
	return {"kind": "sweeper", "bar": bar, "x": 0.0, "z": zc, "dir": 1 if rng.randi() % 2 == 0 else -1,
		"phase": phase, "seed": bar, "beat": 0, "col": 0, "row": 0}


# Sweeper phase from the bar number alone (so re-rolling one bar never
# shifts another). Consecutive bars differ by ~4.7 units of gap travel:
# the gap travels 2 * (FIELD_WIDTH - GAP) units per 2-bar cycle.
static func _sweeper_phase(bar: int) -> float:
	return fposmod(bar * 0.2137 + 0.05, 1.0)


static func _gate(bar: int, z: float, rng: RandomNumberGenerator) -> Dictionary:
	return {"kind": "gate", "bar": bar, "x": 0.0, "z": z, "dir": 1, "phase": 0.0,
		"seed": int(rng.randi() % 100000), "beat": 0, "col": 0, "row": 0}


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
static func _riskiest_tiles(pattern: String, rng: RandomNumberGenerator, n: int) -> Array:
	var scored := []
	for col in Rules.COLS:
		for row in Rules.ROWS:
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
