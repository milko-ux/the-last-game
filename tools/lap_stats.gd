extends SceneTree
# ============================================================
# LAP STATS — generates and validates the laps of the endless course on
# the Mac, reports them, and writes the shipped verdicts.
#
#   godot --headless --path . -s tools/lap_stats.gd -- laps=0-9 write=1
#
# For both lap-0 variants (new player / graduated) and every lap asked
# for: the band, time to generate + validate (no stored verdict is used),
# validation passes, bars that had to be cleared to open floor, hazards,
# notes, checkpoints, and the layout HASH. write=1 stores what was found
# in levels/verdicts.json (laps 0-9 of this SEASON_SEED): with that file
# in the build a phone never validates the first ~25 minutes of a run.
# Re-run it whenever placement.gd, rules.gd, hazard_math.gd, fairness.gd,
# the curriculum or the beatmap change -- and when it is one of the four
# SCRIPTS, bump LapGen.LAYOUT_VERSION first: an exported build cannot
# hash the scripts (it ships them compiled), so that number is the only
# thing that tells a phone the layout moved. Change a script without
# bumping it and the next run of this tool refuses the old file loudly
# instead of trusting it.
# ============================================================

func _initialize() -> void:
	var lo := 0
	var hi := 9
	var write := false
	var incremental := true      # incremental=0: every pass walks the whole lap (to prove the shortcut changes nothing)
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() == 2 and kv[0] == "laps":
			var r: PackedStringArray = kv[1].split("-")
			lo = int(r[0])
			hi = int(r[r.size() - 1])
		if kv.size() == 2 and kv[0] == "write":
			write = kv[1] == "1"
		if kv.size() == 2 and kv[0] == "incremental":
			incremental = kv[1] == "1"
	var LapGen: GDScript = load("res://prototype/lap_gen.gd")
	var clock = root.get_node_or_null("BeatClock")
	if clock == null:
		clock = load("res://prototype/beat_clock.gd").new()
		clock.name = "BeatClock"
		root.add_child(clock)
	if not clock.loaded:
		clock._load()
	clock.set_endless(true)
	clock.start_offset = clock.ENDLESS_Z_ORIGIN_S
	LapGen.ignore_verdicts = true
	var verdicts := {}
	var jobs := []
	for lap in range(lo, hi + 1):
		if lap == 0:
			jobs.append([0, false])
		jobs.append([lap, true])
	for j in jobs:
		var lap: int = j[0]
		var t0 := Time.get_ticks_msec()
		var job = LapGen.begin(clock, lap, j[1])
		job.incremental = incremental
		LapGen.step(job, -1)
		var ms := Time.get_ticks_msec() - t0
		var plan: Dictionary = job.plan
		var cl: Array = job.cleared.keys()
		cl.sort()
		print("LAP %d (%s) band %d: %.1f s, passes %d (+%d clearing rounds), cleared %d %s, hazards %d, notes %d, checkpoints %d, %s  HASH %s" % [
			lap, job.knobs["variant"], LapGen.band_for(lap), ms / 1000.0, job.passes - job.rounds, job.rounds, cl.size(), str(cl),
			plan["hazards"].size(), plan["notes"].size(), plan["checkpoints"].size(), "FAIR" if job.fairness["ok"] else "UNFAIR",
			JSON.stringify({"plan": plan, "rerolls": job.rerolls}, "", true, true).sha256_text().substr(0, 16)])
		verdicts[LapGen.verdict_key(job.knobs)] = LapGen.verdict_json(job.rerolls, job.cleared)
	if write:
		var f := FileAccess.open(LapGen.SHIPPED_PATH, FileAccess.WRITE)
		f.store_string(JSON.stringify({"_readme": "Shipped fairness verdicts of the endless course (tools/lap_stats.gd). Ignored when `source` does not match this build: LapGen.LAYOUT_VERSION + Fairness.VERSION + the JSON data (the only things an export ships byte for byte). `scripts` is the md5 of the four layout scripts as they read on disk -- checked wherever the sources are readable, so a changed script with no LAYOUT_VERSION bump is refused instead of trusted.",
			"season_seed": LapGen.SEASON_SEED, "source": LapGen.source_hash(),
			"layout_version": LapGen.LAYOUT_VERSION, "fairness_version": LapGen.fairness_version(),
			"scripts": LapGen.script_hash(), "verdicts": verdicts}, "\t"))
		print("WROTE %s (%d verdicts, source %s)" % [LapGen.SHIPPED_PATH, verdicts.size(), LapGen.source_hash()])
	quit()
