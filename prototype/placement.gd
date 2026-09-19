extends RefCounted
# ============================================================
# PLACEMENT — turns the beatmap's bars into a layout, shaped by the
# level's knobs (levels/curriculum.json, read through Rules) and, for
# level 1, by the taught curriculum (addendum 3: concrete before
# abstract; addendum 4: pacing and the in-level ramp).
#
# Nothing here is hand-authored: a different song's beatmap gives a
# different level with zero code changes. Everything is seeded by
# level and bar number, so a level is identical on every run and device.
#
# Level 1 (structure "curriculum"), addendum 4 pacing:
#   1-8    doorways   a gate EVERY bar (bar 1 = demo), one pit in the
#                     middle rows of every second bar
#   9-10   breather   open floor, checkpoint, one note, the next wave's word
#   11-16  pressure   Pressure density with the types shown so far
#   17-24  thrown     volleys and slammers (two demo bars)
#   25-26  breather / 27-31 pressure
#   32-40  walls      sweepers (one gate allowed)
#   41-42  breather / 43-48 pressure
#   49-56  orbiters   an orbiter on at least 6 of the 8 bars
#   57-64  floor      plates, row segment / 2x2 block; two types per bar
#                     allowed from here (a compatible pair)
#   65-    outro      wave-5 density, anything already shown, ends on the goal
#
# Density ramps wave by wave: the level's density_curve multiplies the
# hazard count per bar (1.0 -> 1.7 on level 1), applied where a second
# instance can exist (a second volley on another row, a second orbiter,
# a compatible second type once types_per_bar allows it).
#
# Levels 2+ (structure "mixed"): five equal waves, waves 2-5 open with
# a 2-bar breather (checkpoint, note, word); every other bar mixes any
# hazard type at the level's knobs. A pattern new to the level gets a
# demo bar while the level's demo_bars flag is on (levels 2-6).
#
# Hard rules, enforced by _check(): never more hazard TYPES in a bar
# than types_per_bar (pits are floor, not a type, but never share a
# row with plates); the incompatible pairs of addendum 4 section 6;
# nothing lethal before its demo bar (per type AND per plate pattern)
# while demo bars are on; beat-rate patterns only where the level
# allows them; plain rows before and after every gate and either side
# of every sweeper.
# ============================================================

const Rules := preload("res://prototype/rules.gd")
const HazardMath := preload("res://prototype/hazard_math.gd")

const DEMO_WORDS := {"plates": "FLOOR", "sweeper": "WALL", "gate": "GATE", "orbiter": "ORBIT",
	"volley": "VOLLEY", "slammer": "SLAM", "pit": "PIT",
	"row": "FLOOR", "block": "FLOOR", "checker": "CHECKER", "column_wave": "WAVE", "spiral": "SPIRAL"}

# Level 1's waves. "index" is the wave number for the density curve
# (0-based); pressure bars ramp at the density of the wave before them.
const LEVEL1 := [
	{"from": 1, "to": 8, "wave": "doorways", "index": 0},
	{"from": 9, "to": 10, "wave": "breather", "checkpoint": 9, "next": "volley", "index": 0},
	{"from": 11, "to": 16, "wave": "pressure", "index": 0},
	{"from": 17, "to": 24, "wave": "thrown", "index": 1},
	{"from": 25, "to": 26, "wave": "breather", "checkpoint": 25, "next": "sweeper", "index": 1},
	{"from": 27, "to": 31, "wave": "pressure", "index": 1},
	{"from": 32, "to": 40, "wave": "walls", "index": 2},
	{"from": 41, "to": 42, "wave": "breather", "checkpoint": 41, "next": "orbiter", "index": 2},
	{"from": 43, "to": 48, "wave": "pressure", "index": 2},
	{"from": 49, "to": 56, "wave": "orbiters", "index": 3},
	{"from": 57, "to": 64, "wave": "floor", "index": 4},
	{"from": 65, "to": 9999, "wave": "outro", "index": 4},
]

const KINDS := ["gate", "sweeper", "orbiter", "volley", "slammer", "plates"]
# Mixed levels: how often each kind is picked (before compatibility).
const MIX_WEIGHTS := {"gate": 2.0, "sweeper": 2.0, "orbiter": 2.5, "volley": 2.0, "slammer": 1.5, "plates": 3.0}

const DENSITY_RANK := {"rest": 0, "breather": 1, "pressure": 2, "gauntlet": 3}


static func density(energy: float) -> String:
	if energy >= 0.85:
		return "gauntlet"
	if energy >= 0.55:
		return "pressure"
	if energy >= 0.35:
		return "breather"
	return "rest"


# Working state for one build.
class Ctx:
	var clock
	var rng: RandomNumberGenerator
	var bar: int
	var z0: float
	var z1: float
	var zc: float
	var depth: float
	var entry: Dictionary
	var hazards: Array
	var notes: Array
	var kinds: Array = []        # hazard kinds placed in this bar (plates as "plates:<pattern>")
	var demo := false
	var after_gate := false
	var shown: Array             # kinds / patterns demoed so far (level 1) or usable (mixed)
	var demoed: Array            # kinds / patterns that have had their demo bar in this level
	var max_plates: int
	var allowed_patterns: Array
	var wave_index := 0
	var types_per_bar := 1
	var pairs_ok := false


static func _entry_for(curriculum: Array, bar: int) -> Dictionary:
	for e in curriculum:
		if bar >= int(e["from"]) and bar <= int(e["to"]):
			return e
	return {"from": bar, "to": bar, "wave": "outro", "index": 4}


# Mixed levels: five equal waves; waves 2-5 open with a two-bar breather.
static func _mixed_curriculum(bar_count: int) -> Array:
	var out := []
	var per := int(ceil(float(bar_count) / 5.0))
	for w in 5:
		var from := 1 + w * per
		var to := mini(bar_count, from + per - 1)
		if from > bar_count:
			break
		if w > 0:
			out.append({"from": from, "to": mini(to, from + 1), "wave": "breather", "checkpoint": from, "next": "", "index": w})
			from += 2
		if from <= to:
			out.append({"from": from, "to": to, "wave": "mixed", "index": w})
	return out


# Returns {"bars": {bar: {...}}, "hazards": [...], "notes": [...], "checkpoints": [...],
#          "demo_bars": {bar: type}, "curriculum": [...]}
# bar entry: density, pattern, cols, plates, plain_rows, pits, checkpoint, demo, word
# hazard: kind, bar, x, z, dir, phase, seed, beat, col, row, cycle, speed, demo
static func build(clock, rerolls: Dictionary = {}, curriculum: Array = []) -> Dictionary:
	var level_data := Rules.level()
	var mixed: bool = String(level_data.get("structure", "mixed")) != "curriculum"
	if curriculum.is_empty():
		curriculum = _mixed_curriculum(clock.bar_count()) if mixed else LEVEL1
	var bars := {}
	var hazards := []
	var notes := []
	var checkpoints := []
	var demo_bars := {}
	var curve: Array = level_data.get("density_curve", [1.0, 1.0, 1.0, 1.0, 1.0])
	var acc := 0.0                          # fractional hazard budget carried bar to bar
	var ctx := Ctx.new()
	ctx.clock = clock
	ctx.hazards = hazards
	ctx.notes = notes
	ctx.shown = []
	ctx.demoed = []
	ctx.allowed_patterns = level_data["plate_patterns"]
	ctx.max_plates = maxi(1, int(floor(float(level_data["plate_coverage"]) * Rules.COLS * Rules.ROWS)))
	if mixed:
		# Everything was taught in level 1; only a pattern new to THIS level
		# still needs a demo bar (while demo bars are on for the level).
		ctx.shown = KINDS.duplicate()
		ctx.shown.append("pit")
		for p in ctx.allowed_patterns:
			if not Rules.demo_bars_on() or Rules.pattern_first_level(String(p)) < Rules.LEVEL:
				ctx.shown.append(String(p))
	var gate_in_wave := {}
	var orbiter_bars := {}                   # wave "from" -> orbiter bars so far
	var after_gate := false

	for bar in range(1, clock.bar_count() + 1):
		var rng := RandomNumberGenerator.new()
		# Hashed, not a stride: seeds one stride apart gave correlated first
		# draws (five pit bars in a row on the first build).
		rng.seed = hash(Vector3i(bar, int(rerolls.get(bar, 0)), Rules.LEVEL))
		var e := _entry_for(curriculum, bar)
		var wave := String(e["wave"])
		var k: int = bar - int(e["from"])
		ctx.rng = rng
		ctx.bar = bar
		ctx.z0 = clock.z_at(clock.bar_start(bar))
		ctx.z1 = clock.z_at(clock.bar_end(bar))
		ctx.zc = (ctx.z0 + ctx.z1) * 0.5
		ctx.depth = ctx.z1 - ctx.z0
		ctx.entry = {"density": "rest", "pattern": "none", "cols": [0, Rules.COLS - 1], "plates": [],
			"plain_rows": [], "pits": [], "checkpoint": false, "demo": false, "word": ""}
		ctx.kinds = []
		ctx.demo = false
		ctx.after_gate = after_gate
		ctx.wave_index = clampi(int(e.get("index", 0)), 0, curve.size() - 1)
		ctx.types_per_bar = Rules.types_per_bar_at(ctx.wave_index)
		ctx.pairs_ok = Rules.orbiter_pairs_at(ctx.wave_index)
		var mult := float(curve[ctx.wave_index])

		if wave == "breather":
			_breather(ctx, e, bar, checkpoints)
			acc = 0.0
		else:
			acc += mult
			var n := maxi(1, int(floor(acc)))
			acc -= n
			match wave:
				"doorways":
					# A gate every bar (bar 1 = demo); a one-tile pit in the middle
					# rows of every second bar, where the validator lets it stand.
					_place(ctx, "gate", k == 0)
					if k % 2 == 1:
						_place_pit(ctx)
				"thrown":
					var kind := ""
					match k:
						0: kind = "volley"
						1: kind = "slammer"
						2: kind = "volley"
						3: kind = "slammer"
						_: kind = "volley" if rng.randi() % 2 == 0 else "slammer"
					_place(ctx, kind, k < 2)
					_extra(ctx, n - 1, [kind])
				"walls":
					var kind := "sweeper"
					var wf := int(e["from"])
					if k >= 2 and not gate_in_wave.get(wf, false) and not after_gate and rng.randf() < 0.3:
						kind = "gate"
						gate_in_wave[wf] = true
					_place(ctx, kind, k == 0)
					_extra(ctx, n - 1, ["volley", "slammer"])
				"orbiters":
					# At least 6 of the 8 bars carry an orbiter: the two bars that may
					# skip it are chosen up front, never the demo.
					var wf := int(e["from"])
					var skip: Array = orbiter_bars.get(wf, [])
					if skip.is_empty():
						var r2 := RandomNumberGenerator.new()
						r2.seed = 4242 + wf + 31 * Rules.LEVEL
						skip = [2 + r2.randi() % 3, 5 + r2.randi() % 3]
						orbiter_bars[wf] = skip
					if skip.has(k) and not gate_in_wave.get(wf, false) and not after_gate:
						_place(ctx, "gate", false)
						gate_in_wave[wf] = true
					else:
						_place(ctx, "orbiter", k == 0)
					_extra(ctx, n - 1, ["orbiter"])
				"floor":
					# Each allowed (level-1) pattern gets its own demo bar, then a live bar.
					var pats := []
					for p in ctx.allowed_patterns:
						if not String(p) in Rules.BEAT_PATTERNS:
							pats.append(String(p))
					var pattern := ""
					if k < pats.size() * 2:
						pattern = pats[k / 2]
						_place_plates(ctx, pattern, k % 2 == 0)
					else:
						pattern = pats[rng.randi() % pats.size()]
						_place_plates(ctx, pattern, false)
					_extra(ctx, n - 1, ["orbiter", "volley", "slammer", "gate"])
				"pressure", "outro":
					# Nothing new: already-shown kinds at the ramp's density. A pit
					# alone is not a bar's hazard; pits only come as extras.
					var pool := _shown_pool(ctx)
					var main := pool.filter(func(x): return x != "pit")
					if main.is_empty():
						_open_floor(ctx, e, bar, checkpoints)
					else:
						var tries := 0
						while tries < 6 and not _place(ctx, String(main[rng.randi() % main.size()]), false):
							tries += 1
						_extra(ctx, n - 1, pool)
				"mixed":
					var pool := _mixed_pool(ctx)
					var first := String(pool[rng.randi() % pool.size()])
					var demo_first := Rules.demo_bars_on() and not ctx.shown.has(first) and not ctx.demoed.has(first)
					_place(ctx, first, demo_first)
					if not demo_first:
						_extra(ctx, n - 1, pool)
						if ctx.types_per_bar > 1 and rng.randf() < 0.35:
							_place_pit(ctx)
				_:
					_open_floor(ctx, e, bar, checkpoints)

		var entry := ctx.entry
		if not ctx.kinds.is_empty() or not entry["pits"].is_empty():
			entry["density"] = "pressure"
		if ctx.demo:
			entry["demo"] = true
			entry["density"] = "demo"
			var shown_as := String(entry["pattern"]) if ctx.kinds[0] == "plates" else String(ctx.kinds[0])
			entry["word"] = String(DEMO_WORDS.get(shown_as, ""))
			demo_bars[bar] = String(ctx.kinds[0])
			if not ctx.demoed.has(shown_as):
				ctx.demoed.append(shown_as)
		# Once a bar is over, whatever it demoed (or, on level 1, whatever
		# was live in it) may be used by later bars.
		for kd in ctx.kinds:
			var name := String(entry["pattern"]) if kd == "plates" else String(kd)
			if not ctx.shown.has(name):
				ctx.shown.append(name)
		if not entry["pits"].is_empty() and not ctx.shown.has("pit"):
			ctx.shown.append("pit")

		# Milko, 2026-09-15: a player who has just come through a gate has
		# no attention to spare, so the row after every gate is plain too.
		if after_gate and not entry["plain_rows"].has(0):
			entry["plain_rows"].append(0)
		var kept_plates := []
		for tile in entry["plates"]:
			if not entry["plain_rows"].has(int(tile[1])):
				kept_plates.append(tile)
		entry["plates"] = kept_plates
		if kept_plates.is_empty() and not String(entry["pattern"]) in Rules.BEAT_PATTERNS and String(entry["pattern"]) != "none":
			entry["pattern"] = "none"   # every tile sat on a plain row: no plates after all
			ctx.kinds.erase("plates")
		var kept_pits := []
		for pit in entry["pits"]:
			if not entry["plain_rows"].has(int(pit[1])) and not _row_has_plates(entry, int(pit[1])):
				kept_pits.append(pit)
		entry["pits"] = kept_pits
		after_gate = ctx.kinds.has("gate")
		bars[bar] = entry

	_check(bars, hazards, demo_bars)
	return {"bars": bars, "hazards": hazards, "notes": notes, "checkpoints": checkpoints,
		"demo_bars": demo_bars, "curriculum": curriculum}


# --- one bar ---------------------------------------------------------

# Place one hazard of `kind` in the bar (demo = shows, never kills).
# Returns false if the bar cannot take it.
static func _place(ctx: Ctx, kind: String, demo: bool) -> bool:
	if kind == "pit":
		return _place_pit(ctx)
	if kind in Rules.PATTERNS:
		return _place_plates(ctx, kind, demo)
	if kind == "plates":
		var pats := []
		for p in ctx.allowed_patterns:
			if ctx.shown.has(String(p)) or demo:
				pats.append(String(p))
		if pats.is_empty():
			return false
		return _place_plates(ctx, pats[ctx.rng.randi() % pats.size()], demo)
	if not _compatible(ctx, kind):
		return false
	var rng := ctx.rng
	var e := ctx.entry
	match kind:
		"gate":
			if ctx.kinds.has("gate"):
				return false   # one wall line per bar
			ctx.hazards.append(_gate(ctx.bar, ctx.z1 - 0.5, rng, demo))
			if not e["plain_rows"].has(Rules.ROWS - 1):
				e["plain_rows"].append(Rules.ROWS - 1)
			if not demo:
				ctx.notes.append(_gate_note(ctx.z1, rng, ctx.bar))
		"sweeper":
			if ctx.kinds.has("sweeper"):
				return false
			# The rows either side of a wall are where you wait for the gap:
			# nothing may already be shooting or dropping there.
			for h in ctx.hazards:
				if int(h["bar"]) == ctx.bar and String(h["kind"]) in ["volley", "slammer"] and int(h["row"]) in [1, 2]:
					return false
			ctx.hazards.append(_sweeper(ctx.bar, ctx.zc, rng, _sweeper_phase(ctx.bar), demo))
			for r in [1, 2]:
				if not e["plain_rows"].has(r):
					e["plain_rows"].append(r)
			if not demo:
				ctx.notes.append(_sweeper_note(ctx.hazards[-1], ctx.clock, ctx.bar))
		"orbiter":
			var used := []
			for h in ctx.hazards:
				if int(h["bar"]) == ctx.bar and String(h["kind"]) == "orbiter":
					used.append(float(h["x"]))
			if ctx.pairs_ok and used.is_empty() and (demo or rng.randf() < 0.5):
				ctx.hazards.append_array(_orbiter_pair(ctx.bar, ctx.zc, demo))
			else:
				var xs := [-4.0, 0.0, 4.0].filter(func(x): return not used.has(x))
				if xs.is_empty():
					return false
				var x: float = xs[rng.randi() % xs.size()]
				ctx.hazards.append(_orbiter(ctx.bar, x, ctx.zc, rng, demo))
				if not demo and used.is_empty():
					ctx.notes.append({"x": x + (2.0 if x <= 0.0 else -2.0), "z": ctx.zc, "bar": ctx.bar})
		"volley":
			var rows := []
			for r in Rules.ROWS:
				if not e["plain_rows"].has(r):
					rows.append(r)
			for h in ctx.hazards:
				if int(h["bar"]) == ctx.bar and String(h["kind"]) == "volley":
					rows.erase(int(h["row"]))
			if rows.is_empty():
				return false
			var row: int = rows[rng.randi() % rows.size()]
			var v := _volley(ctx.bar, _row_z(ctx.z0, ctx.depth, row), rng, (ctx.bar - 1) % 2, demo)
			v["row"] = row
			ctx.hazards.append(v)
		"slammer":
			var cols := range(Rules.COLS)
			for h in ctx.hazards:
				if int(h["bar"]) == ctx.bar and String(h["kind"]) == "slammer":
					cols.erase(int(h["col"]))
			if cols.is_empty():
				return false
			var col: int = cols[rng.randi() % cols.size()]
			var row := 1 + rng.randi() % 2
			var s := _slammer(ctx.bar, Rules.col_x(col), _row_z(ctx.z0, ctx.depth, row), (ctx.bar - 1) % 2, demo)
			s["col"] = col
			s["row"] = row
			ctx.hazards.append(s)
		_:
			return false
	if not ctx.kinds.has(kind):
		ctx.kinds.append(kind)
	ctx.demo = ctx.demo or demo
	return true


static func _place_plates(ctx: Ctx, pattern: String, demo: bool) -> bool:
	if not ctx.allowed_patterns.has(pattern):
		return false
	if ctx.kinds.has("plates") or not _compatible(ctx, "plates:" + pattern):
		return false
	var e := ctx.entry
	e["pattern"] = pattern
	if pattern in Rules.BEAT_PATTERNS:
		# A beat-rate pattern covers a column band sized by plate_coverage
		# (checker fills half its band, so the band is twice the coverage).
		var width: int = clampi(int(round(float(Rules.level()["plate_coverage"]) * 2.0 * Rules.COLS)), 3, Rules.COLS)
		var c0: int = ctx.rng.randi() % (Rules.COLS - width + 1)
		e["cols"] = [c0, c0 + width - 1]
		e["plates"] = []
	else:
		e["plates"] = _plate_tiles(pattern, ctx.rng, ctx.max_plates)
	ctx.kinds.append("plates")
	ctx.demo = ctx.demo or demo
	return true


# One one-tile pit in a middle row that is neither plain nor a plate row.
static func _place_pit(ctx: Ctx) -> bool:
	var e := ctx.entry
	if String(e["pattern"]) in Rules.BEAT_PATTERNS:
		return false
	var rows := []
	for r in [1, 2]:
		if not e["plain_rows"].has(r) and not _row_has_plates(e, r):
			rows.append(r)
	if rows.is_empty():
		return false
	var row: int = rows[ctx.rng.randi() % rows.size()]
	var col: int = ctx.rng.randi() % Rules.COLS
	if e["pits"].has([col, row]):
		return false
	e["pits"].append([col, row])
	return true


# The ramp: up to `extra` more instances in this bar, from `pool`. A
# second instance of a kind already here (another volley on another
# row, another orbiter) never counts as a new type; a different kind
# needs room under types_per_bar and must be compatible.
static func _extra(ctx: Ctx, extra: int, pool: Array) -> void:
	if ctx.demo:
		return   # a demo bar shows one thing, alone
	var tries := 0
	while extra > 0 and tries < 8:
		tries += 1
		var kind := String(pool[ctx.rng.randi() % pool.size()])
		if kind == "pit":
			if _place_pit(ctx):
				extra -= 1
			continue
		var kname := kind if not kind in Rules.PATTERNS else "plates"
		if not ctx.kinds.has(kname) and ctx.kinds.size() >= ctx.types_per_bar:
			continue
		if _place(ctx, kind, false):
			extra -= 1


# Kinds this level-1 bar may draw on: everything shown so far.
static func _shown_pool(ctx: Ctx) -> Array:
	var out := []
	for s in ctx.shown:
		var s2 := String(s)
		if s2 in Rules.PATTERNS:
			if not out.has("plates"):
				out.append("plates")
		else:
			out.append(s2)
	return out


static func _mixed_pool(ctx: Ctx) -> Array:
	var out := []
	for kind in KINDS:
		var w := float(MIX_WEIGHTS.get(kind, 1.0))
		for i in int(round(w * 2.0)):
			out.append(kind)
	# Patterns new to this level, by name, so their demo bar can happen.
	if Rules.demo_bars_on():
		for p in ctx.allowed_patterns:
			if not ctx.shown.has(String(p)) and not ctx.demoed.has(String(p)):
				for i in 3:
					out.append(String(p))
	return out


# Addendum 4 section 6: pairs that never share a bar.
static func _compatible(ctx: Ctx, kind: String) -> bool:
	var here := ctx.kinds.duplicate()
	if ctx.kinds.has("plates"):
		here.append("plates:" + String(ctx.entry["pattern"]))
	for other in here:
		if Rules.incompatible(kind, String(other)):
			return false
	return true


static func _row_has_plates(entry: Dictionary, row: int) -> bool:
	if String(entry["pattern"]) in Rules.BEAT_PATTERNS:
		return true
	for tile in entry["plates"]:
		if int(tile[1]) == row:
			return true
	return false


# Breather (addendum 4 section 2): open floor, the checkpoint, one note,
# and the word for whatever the next wave introduces.
static func _breather(ctx: Ctx, e: Dictionary, bar: int, checkpoints: Array) -> void:
	_open_floor(ctx, e, bar, checkpoints)
	ctx.entry["density"] = "breather"
	var next := String(e.get("next", ""))
	if next != "" and bar == int(e["from"]):
		ctx.entry["word"] = String(DEMO_WORDS.get(next, ""))
	if bar == int(e["from"]) + 1 or int(e["to"]) == int(e["from"]):
		var col := ctx.rng.randi() % Rules.COLS
		ctx.notes.append({"x": Rules.col_x(col), "z": _row_z(ctx.z0, ctx.depth, 1 + ctx.rng.randi() % 2), "bar": bar})


# Open floor: a checkpoint where the curriculum says.
static func _open_floor(ctx: Ctx, e: Dictionary, bar: int, checkpoints: Array) -> void:
	var entry := ctx.entry
	entry["density"] = "breather" if density(ctx.clock.bar_energy(bar)) != "rest" else "rest"
	if int(e.get("checkpoint", -1)) == bar:
		entry["checkpoint"] = true
		var lead: float = Rules.window_depth() * 0.45 / ctx.clock.track_speed
		var t0: float = ctx.clock.bar_start(bar)
		checkpoints.append({"bar": bar, "t": t0, "resume_t": maxf(ctx.clock.start_offset, t0 - lead), "x": 0.0, "z": ctx.z0 + 1.0})


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
	var demos_on := Rules.demo_bars_on()
	var kinds_in_bar := {}
	for h in hazards:
		var b := int(h["bar"])
		var kind := String(h["kind"])
		if not kinds_in_bar.has(b):
			kinds_in_bar[b] = []
		if not kinds_in_bar[b].has(kind):
			kinds_in_bar[b].append(kind)
		if demos_on and not h["demo"] and Rules.LEVEL == 1:
			var intro := int(first_demo.get(kind, 0))
			if intro == 0 or b <= intro:
				push_error("CURRICULUM: %s live in bar %d before its demo bar %d" % [kind, b, intro])
	for bar in bars:
		var en: Dictionary = bars[bar]
		var pattern := String(en["pattern"])
		if pattern != "none":
			var key := "plates:" + pattern
			if demos_on and Rules.pattern_first_level(pattern) == Rules.LEVEL:
				var intro := int(first_demo.get(key, 0))
				if not en["demo"] and (intro == 0 or int(bar) <= intro):
					push_error("CURRICULUM: plates (%s) live in bar %d before their demo bar %d" % [pattern, bar, intro])
			if not Rules.level()["plate_patterns"].has(pattern):
				push_error("CURRICULUM: pattern %s in bar %d is not allowed on level %d" % [pattern, bar, Rules.LEVEL])
			if not kinds_in_bar.has(bar):
				kinds_in_bar[bar] = []
			kinds_in_bar[bar].append(key)
		for pit in en["pits"]:
			if _row_has_plates(en, int(pit[1])):
				push_error("CURRICULUM: pit and plates share row %d in bar %d" % [int(pit[1]), bar])
	for bar in kinds_in_bar:
		var ks: Array = kinds_in_bar[bar]
		var wave_types := Rules.types_per_bar_max()
		if ks.size() > wave_types:
			push_error("CURRICULUM: %d hazard types in bar %d: %s" % [ks.size(), bar, str(ks)])
		for i in ks.size():
			for j in range(i + 1, ks.size()):
				if Rules.incompatible(String(ks[i]), String(ks[j])):
					push_error("CURRICULUM: incompatible %s + %s in bar %d" % [ks[i], ks[j], bar])


static func _row_z(z0: float, depth: float, row: int) -> float:
	return z0 + (row + 0.5) * depth / Rules.ROWS


# Plate tiles for the concrete patterns: a short `row` segment or a
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
		"phase": phase, "seed": bar, "beat": 0, "col": 0, "row": 0, "cycle": 0, "speed": 1, "demo": demo}


# Sweeper phase from the bar number alone (so re-rolling one bar never
# shifts another). Consecutive bars differ by ~4-6 units of gap travel.
static func _sweeper_phase(bar: int) -> float:
	return fposmod(bar * 0.2137 + 0.05, 1.0)


static func _gate(bar: int, z: float, rng: RandomNumberGenerator, demo: bool) -> Dictionary:
	return {"kind": "gate", "bar": bar, "x": 0.0, "z": z, "dir": 1, "phase": 0.0,
		"seed": int(rng.randi() % 100000), "beat": 0, "col": 0, "row": 0, "cycle": 0, "speed": 1, "demo": demo}


static func _orbiter(bar: int, x: float, zc: float, rng: RandomNumberGenerator, demo: bool) -> Dictionary:
	return {"kind": "orbiter", "bar": bar, "x": x, "z": zc, "dir": 1 if rng.randi() % 2 == 0 else -1,
		"phase": 0.0, "seed": bar, "beat": 0, "col": 0, "row": 0, "cycle": 0, "speed": Rules.orbiter_speed(), "demo": demo}


# The classic pair: side by side, opposite spin, orbs opposed.
static func _orbiter_pair(bar: int, zc: float, demo: bool) -> Array:
	var sp := Rules.orbiter_speed()
	return [
		{"kind": "orbiter", "bar": bar, "x": -4.0, "z": zc, "dir": 1, "phase": 0.0, "seed": bar,
			"beat": 0, "col": 0, "row": 0, "cycle": 0, "speed": sp, "demo": demo},
		{"kind": "orbiter", "bar": bar, "x": 4.0, "z": zc, "dir": -1, "phase": PI, "seed": bar,
			"beat": 0, "col": 0, "row": 0, "cycle": 0, "speed": sp, "demo": demo},
	]


static func _volley(bar: int, z: float, rng: RandomNumberGenerator, cycle: int, demo: bool) -> Dictionary:
	return {"kind": "volley", "bar": bar, "x": 0.0, "z": z, "dir": 1 if rng.randi() % 2 == 0 else -1,
		"phase": 0.0, "seed": bar, "beat": 0, "col": 0, "row": 0, "cycle": cycle, "speed": 1, "demo": demo}


static func _slammer(bar: int, x: float, z: float, cycle: int, demo: bool) -> Dictionary:
	return {"kind": "slammer", "bar": bar, "x": x, "z": z, "dir": 1, "phase": 0.0, "seed": bar,
		"beat": 0, "col": 0, "row": 0, "cycle": cycle, "speed": 1, "demo": demo}


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
