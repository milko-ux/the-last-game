extends RefCounted
# ============================================================
# LAP GEN — one lap of the endless course: which knobs it uses, how it
# is seeded, and the job that generates it, validates it and makes it
# fair (Phase E brief 1, section 3).
#
# BAND. Lap k (0-based) uses curriculum band min(k + 1, 30): what used
# to be "level k + 1's knobs". The run ignores the band's song_tempo,
# song_offset_s and lives (one track at tempo 1.0; lives are the run's).
#
# SEED. One course per season, the same for every player: SEASON_SEED +
# the lap index seeds the layout. Same seed = same course for everyone,
# so distances compare, the course can be learned, a run can be checked
# later, and the next season is one number.
#
# LAP 0 has two variants. A NEW player (Progress.graduated false) gets
# today's level-1 curriculum, bars 1-72, untouched: same seed as level
# 1, demo bars, words, nothing lethal before its demo. A GRADUATED
# player gets band 1 mixed, no demo bars, seeded like every other lap.
# Every lap after the first opens on a plain bar with a checkpoint and
# the word STAGE n.
#
# FAIR OR EASIER, NEVER UNFAIR, NEVER STUCK. A lap goes through
# fairness.gd exactly as a level does: generate, validate, re-roll the
# failing bars, up to the band's reroll_passes. Bars that are still
# unfair after that are CLEARED to open floor (and logged), then the lap
# is validated again; every round clears at least one more bar, so it
# always ends.
#
# VERDICTS. What a finished job found (the re-rolls and the cleared bars)
# is a verdict. levels/verdicts.json ships the verdicts of laps 0-9 of
# this season for both lap-0 variants (made on the Mac by
# tools/lap_stats.gd), so a phone never validates the first ~25 minutes
# of a run; after that, and when the file is missing, the job runs live,
# time-sliced (Job.step(budget)), and its verdict is cached per device.
# With a verdict the job only has to place the bars.
# ============================================================

const Rules := preload("res://prototype/rules.gd")
const Placement := preload("res://prototype/placement.gd")
const Fairness := preload("res://prototype/fairness.gd")
const LapClock := preload("res://prototype/lap_clock.gd")

const SEASON_SEED := 20260901
const SHIPPED_PATH := "res://levels/verdicts.json"
const SHIPPED_LAPS := 10

static var _shipped := {}
static var _shipped_read := false
# Tools set this to ignore every stored verdict (shipped and cached).
static var ignore_verdicts := false


static func band_for(lap: int) -> int:
	return mini(lap + 1, Rules.level_count())


static func variant(graduated: bool) -> String:
	return "grad" if graduated else "new"


# The knob dictionary of a lap: the band's row plus what the run adds.
static func knobs_for(lap: int, graduated: bool) -> Dictionary:
	var k: Dictionary = Rules.level(band_for(lap)).duplicate(true)
	k["lap"] = lap
	k["stage"] = lap + 1
	k["variant"] = variant(graduated) if lap == 0 else "lap"
	if lap == 0 and not graduated:
		return k                                  # level 1 as it is: its own seed, its curriculum
	k["seed"] = SEASON_SEED + lap
	if lap == 0:
		k["structure"] = "mixed"
		k["demo_bars"] = false
		k.erase("types_per_bar_final")
		k.erase("orbiter_pairs_from_wave")
	else:
		k["plain_bar1"] = true
	return k


# ------------------------------------------------------------
# Verdicts
# ------------------------------------------------------------
static func verdict_key(k: Dictionary) -> String:
	return "v%d_s%d_%s_lap%d" % [Fairness.VERSION, SEASON_SEED, String(k.get("variant", "lap")), int(k.get("lap", 0))]


# A verdict made with other layout code or other data must never be
# trusted: it would skip the validation of a lap that has changed.
#
# This USED to md5 the four layout scripts. That can never match in an
# exported build: the exporter ships GDScript compiled (placement.gdc
# beside the name placement.gd, script_export_mode=2), so the phone
# hashed compiled bytes while tools/lap_stats.gd had stamped the file
# with the hash of the readable sources. Every device rejected
# levels/verdicts.json and validated every lap live -- 4.6 s of a 6.5 s
# load on Milko's iPhone, 2026-09-21, and invisible here because the Mac
# reads the sources and matches itself.
#
# So the shipped hash is built only from things the exporter ships
# BYTE FOR BYTE -- the two JSON data files (verified in the pck) -- plus
# version numbers bumped by hand. LAYOUT_VERSION is that hand:
# ** bump it whenever placement.gd / rules.gd / hazard_math.gd /
#    fairness.gd change what a lap LOOKS like, then re-run
#    tools/lap_stats.gd -- laps=0-9 write=1 **
# Forgetting is caught, not trusted to memory: where the sources are
# readable (the editor and every headless tool, i.e. everywhere a verdict
# is ever MADE) stored_verdict() also checks the scripts themselves and
# refuses the file if they moved without a bump.
const LAYOUT_VERSION := 1
const LAYOUT_SCRIPTS := ["res://prototype/placement.gd", "res://prototype/rules.gd",
		"res://prototype/hazard_math.gd", "res://prototype/fairness.gd"]
const LAYOUT_DATA := ["res://levels/curriculum.json", "res://assets/audio/fuffens_beatmap.json"]


static func source_hash() -> String:
	var src := "L%d_F%d" % [LAYOUT_VERSION, Fairness.VERSION]
	for f in LAYOUT_DATA:
		src += FileAccess.get_md5(f)
	return src.md5_text().substr(0, 12)


# The layout scripts as they read on disk. Only meaningful where the
# sources are readable: an exported build has the compiled .gdc instead,
# and get_md5 there hashes something else entirely (see above).
static func script_hash() -> String:
	var src := ""
	for f in LAYOUT_SCRIPTS:
		src += FileAccess.get_md5(f)
	return src.md5_text().substr(0, 12)


# True in the editor and in every headless tool run, false in an export.
static func sources_readable() -> bool:
	return OS.has_feature("editor")


static func fairness_version() -> int:
	return Fairness.VERSION


static func _device_path(k: Dictionary) -> String:
	return "user://lap_%s_%s.json" % [verdict_key(k), source_hash()]


static func _parse(data) -> Dictionary:
	if typeof(data) != TYPE_DICTIONARY or not bool(data.get("ok", false)):
		return {}
	var rerolls := {}
	for b in data.get("rerolls", {}):
		rerolls[int(b)] = int(data["rerolls"][b])
	var cleared := {}
	for b in data.get("cleared", []):
		cleared[int(b)] = true
	return {"rerolls": rerolls, "cleared": cleared}


static func stored_verdict(k: Dictionary) -> Dictionary:
	if ignore_verdicts:
		return {}
	if not _shipped_read:
		_shipped_read = true
		var f := FileAccess.open(SHIPPED_PATH, FileAccess.READ)
		var data = JSON.parse_string(f.get_as_text()) if f != null else null
		if typeof(data) == TYPE_DICTIONARY and String(data.get("source", "")) == source_hash():
			# The hash above cannot see the layout scripts in an export.
			# Where it CAN (here, and in every tool that makes a verdict)
			# check them for real: a script that moved without a
			# LAYOUT_VERSION bump would otherwise ship a lap that was
			# validated as a different lap.
			var rec := String(data.get("scripts", ""))
			if sources_readable() and rec != "" and rec != script_hash():
				push_error("LapGen: levels/verdicts.json was made with DIFFERENT layout scripts (%s, now %s) but the same LAYOUT_VERSION %d. Bump LapGen.LAYOUT_VERSION and re-run: godot --headless --path . -s tools/lap_stats.gd -- laps=0-9 write=1" % [rec, script_hash(), LAYOUT_VERSION])
			else:
				_shipped = data.get("verdicts", {})
		elif typeof(data) == TYPE_DICTIONARY:
			push_warning("LapGen: levels/verdicts.json was made with other data / another version; ignoring it (re-run tools/lap_stats.gd)")
	var key := verdict_key(k)
	if _shipped.has(key):
		var v := _parse(_shipped[key])
		if not v.is_empty():
			v["from"] = "shipped"
			return v
	var df := FileAccess.open(_device_path(k), FileAccess.READ)
	if df != null:
		var v := _parse(JSON.parse_string(df.get_as_text()))
		if not v.is_empty():
			v["from"] = "device"
			return v
	return {}


static func verdict_json(rerolls: Dictionary, cleared: Dictionary) -> Dictionary:
	var rr := {}
	for b in rerolls:
		rr[str(b)] = rerolls[b]
	var cl := cleared.keys()
	cl.sort()
	return {"ok": true, "rerolls": rr, "cleared": cl}


# ------------------------------------------------------------
# The job
# ------------------------------------------------------------
class Job:
	var lap := 0
	var knobs: Dictionary
	var clock                         # LapClock
	var rerolls := {}
	var cleared := {}
	var passes := 0
	var rounds := 0                   # validate rounds after the passes ran out (each clears bars)
	var from := "live"                # "shipped" / "device" / "live" / "forced"
	var plan := {}
	var fairness := {}
	var done := false
	var work_usec := 0                # CPU time spent, all steps
	var _builder
	var _validator
	var _last_validator               # the pass before: the next one resumes from it
	var _first_changed := 1           # the earliest bar the coming pass differs in
	var incremental := true           # tools turn it off to prove it changes nothing
	var _trusted := false             # a stored verdict: place the bars, do not validate


static func begin(base_clock: Node, lap: int, graduated: bool) -> Job:
	var job := Job.new()
	job.lap = lap
	job.knobs = knobs_for(lap, graduated)
	job.clock = LapClock.new(base_clock, lap)
	var v := stored_verdict(job.knobs)
	if not v.is_empty():
		job.rerolls = v["rerolls"]
		job.cleared = v["cleared"]
		job.from = String(v["from"])
		job._trusted = true
	return job


# Works for at most `budget_usec` microseconds (-1 = to the end).
# Returns true when the lap is ready: job.plan, job.fairness.
static func step(job: Job, budget_usec: int) -> bool:
	var started := Time.get_ticks_usec()
	var until := started + budget_usec
	while not job.done:
		if job._builder == null and job._validator == null:
			job._builder = Placement.begin(job.clock, job.rerolls, job.knobs, [], job.cleared)
		if job._builder != null:
			if not job._builder.done():
				Placement.step(job._builder)
			else:
				job.plan = Placement.finish(job._builder)
				job._builder = null
				if job._trusted:
					job.fairness = {"ok": true, "problems": [], "path": [], "first_beat": job.clock.first_bar_beat, "cached": true}
					job.done = true
				else:
					job.passes += 1
					if job._last_validator != null and job.incremental:
						job._validator = Fairness.begin_from(job._last_validator, job.plan, job._first_changed)
					else:
						job._validator = Fairness.begin(job.plan, job.clock, job.knobs)
		elif Fairness.step(job._validator, maxi(0, until - Time.get_ticks_usec()) if budget_usec >= 0 else -1):
			job.fairness = Fairness.finish(job._validator)
			job._last_validator = job._validator
			job._validator = null
			if job.fairness["ok"]:
				job.done = true
				_save_device(job)
			else:
				_next_attempt(job)
		if budget_usec >= 0 and Time.get_ticks_usec() >= until:
			break
	job.work_usec += Time.get_ticks_usec() - started
	return job.done


# Not fair yet: re-roll the failing bars while the band's passes last (the
# failing bar, the one before it — the block is usually the pair — and the
# one after it, as field.gd always did); after that, clear them.
static func _next_attempt(job: Job) -> void:
	var clearing := job.passes >= Rules.reroll_passes(job.knobs)
	if clearing:
		job.rounds += 1
	var newly := 0
	job._first_changed = job.clock.bar_count() + 1
	for prob in job.fairness["problems"]:
		job._first_changed = mini(job._first_changed, maxi(1, int(String(prob).get_slice("bar ", 1).get_slice(",", 0)) - 3))
	for prob in job.fairness["problems"]:
		var bar := int(String(prob).get_slice("bar ", 1).get_slice(",", 0))
		if clearing:
			bar = clampi(bar, 1, job.clock.bar_count())
			# The bar itself; if it is already clear, the block is what leads
			# into it or what the window shows beyond it (widening if need be,
			# so a round always clears something and the job always ends).
			for b in [bar, bar + 1, bar - 1, bar + 2, bar - 2, bar + 3, bar - 3]:
				if b >= 1 and b <= job.clock.bar_count() and not job.cleared.has(b):
					job.cleared[b] = true
					newly += 1
					print("LAPGEN lap %d: bar %d still unfair after %d passes -> cleared to open floor" % [job.lap, b, job.passes])
					break
		else:
			job.rerolls[bar] = int(job.rerolls.get(bar, 0)) + 1
			if bar > 1:
				job.rerolls[bar - 1] = int(job.rerolls.get(bar - 1, 0)) + 1
			job.rerolls[bar + 1] = int(job.rerolls.get(bar + 1, 0)) + 1
	if clearing and newly == 0:
		force_finish(job)


# Out of time (the lap is needed NOW): every bar the validator has not
# walked yet, and every bar it has already found unfair, becomes open
# floor. Never a stall, never an unfair bar. Blocks for one build.
static func force_finish(job: Job) -> void:
	if job.done:
		return
	var from_bar := 1
	if job._validator != null:
		from_bar = maxi(1, job._validator.bar_reached() - 1)
		for prob in job._validator.problems:
			job.cleared[clampi(int(String(prob).get_slice("bar ", 1).get_slice(",", 0)), 1, job.clock.bar_count())] = true
	elif not job.fairness.is_empty():
		for prob in job.fairness.get("problems", []):
			job.cleared[clampi(int(String(prob).get_slice("bar ", 1).get_slice(",", 0)), 1, job.clock.bar_count())] = true
	for b in range(from_bar, job.clock.bar_count() + 1):
		job.cleared[b] = true
	print("LAPGEN lap %d: FORCED at pass %d, bars %d-%d cleared unvalidated (%d cleared in all)" % [
		job.lap, job.passes, from_bar, job.clock.bar_count(), job.cleared.size()])
	job._validator = null
	job.plan = Placement.build(job.clock, job.rerolls, job.knobs, [], job.cleared)
	job.fairness = {"ok": true, "problems": [], "path": [], "first_beat": job.clock.first_bar_beat, "forced": true}
	job.from = "forced"
	job.done = true


static func _save_device(job: Job) -> void:
	if ignore_verdicts:
		return
	var f := FileAccess.open(_device_path(job.knobs), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(verdict_json(job.rerolls, job.cleared)))
