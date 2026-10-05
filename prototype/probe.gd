extends Node
const BlackBox := preload("res://prototype/blackbox.gd")
const Looks := preload("res://prototype/looks.gd")
# ============================================================
# THE ON-PHONE BENCHMARK (look pass v2, 2026-09-24). Started by ?probe=1
# on the web, or in the app (debug builds) by a long press on the frame
# readout on TAP TO START (step 3 brief 1 section 1, track_test.gd). The
# validator bot plays bars 9-12 of lap 0 of the real run, then the clock
# seeks back and plays the same bars again with the next setup, and at
# the end a table of avg / worst frame time per setup is drawn on
# screen, so one screenshot says which part of the look the phone can
# afford. Setups, each one change against the CURRENT LOOK (looks.gd: a
# setup is applied on top of it, the same mechanism; "today" is the
# shipped look, track_test.FINISH_DEFAULT, glow off since 2026-09-29):
#
#   as is · grain off · glow ON · MSAA off · all post off (tonemap
#   linear too) · no pillars · pillars x0.5 · thin slab (the old 2-unit one)
#   · 3D x1.0 (stress)
#
# "no pillars" against "as is" is what the background costs. Frame times
# only come in whole screen refreshes (see the header's Hz, below), so two
# numbers look past that: the cpu column (the frame meter's cpu: every
# script's update + the engine's frame setup -- not tied to the screen),
# and the stress row, the 3D at full resolution, 1.78x the pixels of the
# app's 0.75: what more pixels cost.
#
# Frame times are the wall clock between two _process calls of this
# node (it runs first), the first SETTLE_S after each switch and seek left
# out (their own hitch). The table is also printed (PROBE lines), written
# to the black box (blackbox.log on the app) and put on the page as
# window.pr_probe for tools/web_shot.py.
#
# MAKING THE ROWS TRUSTWORTHY (2026-10-05, after the phone's first in-app
# table read "pillars x0.5" slower than all the pillars and than the
# full-resolution stress row):
#   - The rows run in a fixed order over ~2 minutes, so anything that
#     drifts with time -- the phone heating up and slowing down -- lands
#     on the later rows. The last row is "as is" AGAIN, the control: if
#     it differs from the first "as is" by more than CONTROL_MAX_MS the
#     table says the run is not reliable.
#   - Background work: while it plays, the run generates and builds the
#     next lap (2 ms a frame each) and the bot validates its own path
#     through every lap (6 ms a frame) -- on the Mac that is done inside
#     the warm-up, on the slower phone it ran into the first rows. The
#     probe now waits for all of it before the warm-up (at most
#     BG_WAIT_MAX_S, then carries on and says so), and the "bg" column
#     counts measured frames that still had some (it should be 0).
#   - The switch itself: rebuilding the pillars or the slab is one long
#     frame ("switch" column, ms). SETTLE_S is now wall time counted from
#     AFTER the switch, not frame time eaten by the switch's own frame.
#   - Leftovers: none found (the Mac, frozen frame and full runs): every
#     row starts from the shipped look and re-applies all of it, and after
#     every pillar rebuild the lap holds the same 63 pillar nodes and draws
#     the same 7.5 pillar meshes per frame as the first "as is". (The
#     engine's draw-call count was tried as a column and dropped: on the
#     Mac it froze when the screen changed its rate.)
#   - The header says the screen's refresh rate: the app may run at 120 Hz
#     (ProMotion), where frame times come in steps of 8.3 ms (8.3, 16.7,
#     25) and a small cost near a step moves a row's average a lot.
# ============================================================

const Rules := preload("res://prototype/rules.gd")
const FROM_BAR := 9
const TO_BAR := 12
const SETTLE_S := 0.7
const CONTROL_MAX_MS := 0.5
const BG_WAIT_MAX_S := 60.0
const SETUPS := [
	["warm-up", {}],           # thrown away: shader compiles and first draws land here, not in "as is"
	["as is", {}],
	["grain off", {"grain": false}],
	["glow ON", {"glow": true}],
	["MSAA off", {"msaa": false}],
	["all post off", {"grain": false, "glow": false, "vignette": false, "msaa": false, "tonemap": "linear"}],
	["no pillars", {"pillars": 0.0}],
	["pillars x0.5", {"pillars": 0.5}],
	["thin slab (2)", {"slab": 2.0}],
	["3D x1.0 (stress)", {"scale": 1.0}],
	["as is (control)", {}],   # the same as "as is", measured last: the drift check
]

var scene: Node = null
var in_app := false              # started from the readout: a tap after the table goes to the menu
var done := false
var _i := -1
var _last_usec := 0
var _settle_until := 0            # usec: frames before this are not measured
var _sum := 0.0
var _worst := 0.0
var _cpu := 0.0
var _bg := 0
var _switch_ms := 0.0
var _n := 0
var _bg_wait := 0.0
var _bg_timed_out := false
var _rows: Array = []
var _label: Label
var _deaths0 := 0
var _retried := false
var _run_up := 0.0


func _ready() -> void:
	process_priority = -2000
	var layer := CanvasLayer.new()
	layer.layer = 5
	add_child(layer)
	_label = Label.new()
	_label.position = Vector2(60, 60)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	_label.text = "PROBE: waiting for the run"
	layer.add_child(_label)


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	var ms := float(now - _last_usec) / 1000.0 if _last_usec != 0 else 0.0
	_last_usec = now
	if done or scene == null or scene.state != scene.State.RUN:
		return
	if _i < 0:
		# The run is up: a second for it to settle, and the background work
		# done (or BG_WAIT_MAX_S gone), then the first setup.
		_run_up += delta
		var bg := _background_work()
		if bg != "" and _run_up >= 1.0:
			_bg_wait += delta
			_label.text = "PROBE: waiting for background work (%s) %.0f s" % [bg, _bg_wait]
		if _run_up >= 1.0 and (bg == "" or _bg_wait >= BG_WAIT_MAX_S):
			_bg_timed_out = bg != ""
			BlackBox.record("probe background wait %.1f s%s" % [_bg_wait, " TIMED OUT (%s)" % bg if _bg_timed_out else ""])
			_start(0)
		return
	if now < _settle_until:
		return
	if ms > 0.0:
		_sum += ms
		_worst = maxf(_worst, ms)
		_cpu += scene.meter.last_cpu_ms() if scene.meter != null else 0.0
		_bg += 1 if _background_work() != "" else 0
		_n += 1
	if BeatClock.current_bar() >= TO_BAR:
		# A death inside the window (a rewind frame, a freeze) is not the
		# setup's cost: the setup is played once more, then kept whatever.
		if scene.deaths != _deaths0 and not _retried:
			_retried = true
			_start(_i)
			return
		_retried = false
		if _i > 0:
			_rows.append([SETUPS[_i][0], _sum / maxf(_n, 1.0), _worst, _cpu / maxf(_n, 1.0), _switch_ms, _n, _bg, scene.deaths - _deaths0])
		if _i + 1 < SETUPS.size():
			_start(_i + 1)
		else:
			_finish()


func _start(i: int) -> void:
	_i = i
	var t_switch := Time.get_ticks_usec()
	Looks.apply(scene, SETUPS[i][1])
	_switch_ms = float(Time.get_ticks_usec() - t_switch) / 1000.0
	# The way a checkpoint rewind and autoplay's start_bar put the bot in:
	# the player a unit into the bar, the window a lead behind it, so the
	# bot has time to get onto its plan before the window arrives.
	var lead: float = Rules.window_depth(scene.knobs) * 0.45 / BeatClock.track_speed
	var t0: float = maxf(BeatClock.start_offset, BeatClock.bar_start(FROM_BAR) - lead)
	scene.player.reset_to(0.0, BeatClock.z_at(BeatClock.bar_start(FROM_BAR)) + 1.0)
	BeatClock.seek(t0)
	_deaths0 = scene.deaths
	_settle_until = Time.get_ticks_usec() + int(SETTLE_S * 1_000_000.0)
	_sum = 0.0
	_worst = 0.0
	_cpu = 0.0
	_bg = 0
	_n = 0
	_label.text = "PROBE %d / %d: %s" % [i, SETUPS.size() - 1, SETUPS[i][0]] if i > 0 else "PROBE warm-up"
	print("PROBE start %s" % SETUPS[i][0])
	BlackBox.record("probe %s" % SETUPS[i][0])


# What the run is still doing besides playing, "" = nothing: the next
# lap's generation, building its nodes, the bot validating its paths.
func _background_work() -> String:
	if scene._job != null:
		return "next lap"
	if scene.field.pending_items() > 0:
		return "building"
	if scene.bot != null and not scene.bot.paths_ready():
		return "bot paths"
	return ""


func _finish() -> void:
	done = true
	BeatClock.pause()
	Looks.apply(scene, scene._url_look)   # the look as it was, without the last setup
	var heap: String = str(JavaScriptBridge.eval("performance.memory ? Math.round(performance.memory.usedJSHeapSize / 1048576) + ' MB' : 'n/a'", true)) if OS.has_feature("web") else "-"
	var lines := ["PROBE  look: %s  bars %d-%d of lap 0, %s  heap %s  %s  screen %.0f Hz" % [Looks.name_of(), FROM_BAR, TO_BAR,
		FrameMeter.load_info, heap, BlackBox.renderer_name(), DisplayServer.screen_get_refresh_rate()]]
	lines.append("%-18s %7s %7s %6s %7s %6s %4s %s" % ["setup", "avg ms", "worst", "cpu", "switch", "frames", "bg", "deaths"])
	for r in _rows:
		lines.append("%-18s %7.1f %7.1f %6.1f %7.0f %6d %4d %d" % [r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7]])
	var first: Array = _rows[0]
	var control: Array = _rows[-1]
	var drift: float = float(control[1]) - float(first[1])
	if absf(drift) > CONTROL_MAX_MS:
		lines.append("WARNING: the control row differs from the first \"as is\" by %+.1f ms (more than %.1f): this run is NOT reliable" % [drift, CONTROL_MAX_MS])
	else:
		lines.append("control: %+.1f ms against the first \"as is\" (within %.1f): the rows can be compared" % [drift, CONTROL_MAX_MS])
	if _bg_timed_out:
		lines.append("WARNING: the background work was not done after %.0f s: see the bg column" % BG_WAIT_MAX_S)
	var text := "\n".join(lines)
	_label.text = text + ("\n\ntap anywhere: back to the menu" if in_app else "")
	for l in lines:
		print(l)
		BlackBox.record(l)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.pr_probe=%s" % JSON.stringify(text), true)
