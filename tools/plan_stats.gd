extends SceneTree
# ============================================================
# PLAN STATS — generate and validate a level's layout headlessly and
# print what is in it, bar by bar. Seconds, not minutes: the quick
# check before the real-time bots.
#
#   godot --headless --path . -s tools/plan_stats.gd -- levels=1,2,3
#
# Prints a HASH line per level: the fingerprint of the generated layout,
# for proving that a refactor changed nothing.
# ============================================================

func _initialize() -> void:
	var levels := [1]
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() == 2 and kv[0] == "levels":
			levels = []
			for x in kv[1].split(","):
				levels.append(int(x))
	var Rules: GDScript = load("res://prototype/rules.gd")
	var Placement: GDScript = load("res://prototype/placement.gd")
	var Fairness: GDScript = load("res://prototype/fairness.gd")
	var clock = root.get_node_or_null("BeatClock")
	if clock == null:
		clock = load("res://prototype/beat_clock.gd").new()
		clock.name = "BeatClock"
		root.add_child(clock)
	if not clock.loaded:
		clock._load()
	for L in levels:
		var knobs: Dictionary = Rules.level(int(L))
		clock.set_tempo(Rules.song_tempo(knobs))
		clock.start_offset = Rules.song_offset(knobs)
		print(Rules.knobs_line(knobs))
		var rerolls := {}
		var fair := {}
		var plan := {}
		var passes := 0
		for attempt in Rules.reroll_passes(knobs):
			passes += 1
			plan = Placement.build(clock, rerolls, knobs)
			fair = Fairness.validate(plan, clock, knobs)
			if fair["ok"]:
				break
			for prob in fair["problems"]:
				var bar := int(String(prob).get_slice("bar ", 1).get_slice(",", 0))
				rerolls[bar] = int(rerolls.get(bar, 0)) + 1
				if bar > 1:
					rerolls[bar - 1] = int(rerolls.get(bar - 1, 0)) + 1
				rerolls[bar + 1] = int(rerolls.get(bar + 1, 0)) + 1
		var per_bar := {}
		for h in plan["hazards"]:
			var b := int(h["bar"])
			if not per_bar.has(b):
				per_bar[b] = []
			per_bar[b].append(String(h["kind"]) + ("*" if h["demo"] else ""))
		var empty := 0
		var total := 0
		var lines := []
		for bar in range(1, clock.bar_count() + 1):
			var e: Dictionary = plan["bars"][bar]
			var items: Array = per_bar.get(bar, []).duplicate()
			if String(e["pattern"]) != "none":
				items.append("plates:%s%s(%d)" % [e["pattern"], "*" if e["demo"] else "", e["plates"].size()])
			for p in e["pits"]:
				items.append("pit")
			total += items.size()
			if items.is_empty() and not e["checkpoint"]:
				empty += 1
			var tag := ""
			if e["checkpoint"]:
				tag += " CP"
			if String(e["word"]) != "":
				tag += " [" + String(e["word"]) + "]"
			lines.append("  bar %2d %-9s%s %s" % [bar, e["density"], tag, " ".join(items)])
		print("LEVEL %d: fairness_ok=%s passes=%d rerolls=%s hazards=%d per_bar=%.2f empty_bars=%d checkpoints=%d notes=%d demo_bars=%s run_up=%.1fs" % [
			L, fair["ok"], passes, str(rerolls), total, float(total) / clock.bar_count(), empty,
			plan["checkpoints"].size(), plan["notes"].size(), str(plan["demo_bars"]),
			clock.bar_start(1) - clock.start_offset])
		# The layout's fingerprint: the whole plan (hazards, plates, pits, notes,
		# checkpoints, words, densities) and the re-rolls it settled on, keys
		# sorted, floats at full precision. Same hash = the same level, to the bit.
		print("HASH level=%d %s" % [L, JSON.stringify({"plan": plan, "rerolls": rerolls}, "", true, true).sha256_text()])
		for p in fair["problems"]:
			print("  PROBLEM: " + String(p))
		if OS.get_environment("PLAN_BARS") != "":
			for l in lines:
				print(l)
	quit()
