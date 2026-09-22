extends SceneTree
# ============================================================
# TALO CHECK — the section 8 acceptance, end to end, against the REAL
# Talo API, with the game's own client (autoload/talo.gd) and nothing
# else. It registers a throwaway account, posts a distance the way the
# game does (Talo.post_best_distance, with the run's props), reads it
# back under GLOBAL and under its country, deletes the account, and
# reads again to see the entry go. Prints one PASS / FAIL line per step
# and the tally at the end.
#
#   godot --headless --path . -s tools/talo_check.gd -- metres=1234 country=SE
#
# Needs talo.cfg with the real key, and the `distance` board created in
# the dashboard (docs/TALO_SETUP.md, 3b). If the board is missing, the
# post fails with "Leaderboard not found" and the run stops there —
# that is the message to look for.
#
# Nothing here writes the save file (Milko's rule 6) — the flags Talo
# reads (Progress.best_distance / best_run / Consent) are set in memory
# only, and the account is deleted before the script quits. If the run
# is killed half-way the account is left behind: its name starts with
# `lastgame-check-`, delete it in the dashboard.
# ============================================================

var metres := 1234
var country := "SE"
var _step := 0
var _pass := 0
var _fail := 0
var _name := ""
var _password := ""
var _alias := -1


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.split("=")
		if kv.size() != 2:
			continue
		match kv[0]:
			"metres": metres = int(kv[1])
			"country": country = kv[1]
	# The autoloads are reached through the tree: a -s script is compiled
	# before they exist (the same shape as tools/shot.gd).
	var progress = root.get_node("Progress")
	progress.save_enabled = false
	root.get_node("Talo").allow_tool_posts = true   # the one tool that may post (see talo.gd)
	var consent = root.get_node("Consent")
	consent.granted = true
	consent.country = country
	consent.show_country = true


# The autoloads' _ready (Talo reads talo.cfg there) runs after
# _initialize, so the check starts on the first frame, not before it.
var _started := false


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _run() -> void:
	var talo = root.get_node("Talo")
	var progress = root.get_node("Progress")
	var lapgen = load("res://prototype/lap_gen.gd")
	var season: int = lapgen.SEASON_SEED
	if not talo.configured():
		printerr("TALO CHECK: no key in talo.cfg")
		quit(1)
		return
	_name = "lastgame-check-%d" % (Time.get_unix_time_from_system() as int % 1000000)
	_password = "check-%d-pw" % randi()
	print("TALO CHECK season=%d metres=%d country=%s account=%s" % [season, metres, country, _name])

	# 1. register
	var res: Dictionary = await talo.register_account(_name, _password, "")
	_check("register", res.ok, str(res.error))
	if not res.ok:
		_done()
		return
	_alias = talo.alias_id

	# 2. post, exactly as the run does: a best run with its props
	progress.best_distance = {}
	progress.best_run = {}
	progress.record_distance(season, metres, {"laps": 1, "run_seconds": 200, "deaths": 3,
		"build": str(ProjectSettings.get_setting("application/config/version", "dev")),
		"layout": lapgen.LAYOUT_VERSION})
	var line: String = await talo.post_best_distance(season)
	var posted: bool = line.begins_with("#") or line == "POSTED"
	_check("post best (%s)" % line, posted, line)
	if not posted:
		await talo.delete_account(_password)
		_done()
		return
	_check("posted flag set", progress.best_posted(season), "")
	var again: String = await talo.post_best_distance(season)
	_check("second post is a no-op", again == "", again)

	# 3. read GLOBAL, find the row
	var g: Dictionary = await talo.get_entries(talo.DISTANCE_BOARD, 0)
	var row := _find(g, _alias)
	_check("on GLOBAL", not row.is_empty(), str(g.error))
	if not row.is_empty():
		_check("score is the metres", int(float(row.get("score", 0))) == metres, str(row.get("score")))
		var props := {}
		for p in row.get("props", []):
			props[str(p.get("key", ""))] = str(p.get("value", ""))
		_check("props carried (season, country, laps, run_seconds, deaths, build, layout)",
			props.has("season") and props.has("country") and props.has("laps") and props.has("run_seconds")
			and props.has("deaths") and props.has("build") and props.has("layout"), str(props))

	# 4. read MY COUNTRY
	var c: Dictionary = await talo.get_entries(talo.DISTANCE_BOARD, 0, "country", country)
	_check("on MY COUNTRY (%s)" % country, not _find(c, _alias).is_empty(), str(c.error))
	var rank: int = await talo.country_rank(talo.DISTANCE_BOARD, country)
	_check("country rank found (#%d)" % rank, rank > 0, "")

	# 5. delete the account, read again
	var d: Dictionary = await talo.delete_account(_password)
	_check("delete account", d.ok, str(d.error))
	_check("signed out after delete", not talo.logged_in(), "")
	_check("best unposted after sign-out", not progress.best_posted(season), "")
	var g2: Dictionary = await talo.get_entries(talo.DISTANCE_BOARD, 0)
	var gone := _find(g2, _alias).is_empty()
	if not gone:
		# Reads can lag a moment after a delete (docs/TALO_SETUP.md): one more look.
		await create_timer(3.0).timeout
		g2 = await talo.get_entries(talo.DISTANCE_BOARD, 0)
		gone = _find(g2, _alias).is_empty()
	_check("entry gone after delete", gone, "")
	_done()


func _find(res: Dictionary, alias: int) -> Dictionary:
	if not res.ok:
		return {}
	for e in res.data.get("entries", []):
		if int(e.get("playerAlias", {}).get("id", -2)) == alias:
			return e
	return {}


func _check(what: String, ok: bool, detail: String) -> void:
	_step += 1
	if ok:
		_pass += 1
	else:
		_fail += 1
	print("  %s  %d. %s%s" % ["PASS" if ok else "FAIL", _step, what, "" if ok or detail.is_empty() else "  -- " + detail])


func _done() -> void:
	print("TALO CHECK %s: %d passed, %d failed" % ["PASS" if _fail == 0 else "FAIL", _pass, _fail])
	quit(0 if _fail == 0 else 1)
