extends Node
# ============================================================
# ?probe=1 — THE ON-PHONE BENCHMARK (look pass v2, 2026-09-24). The
# validator bot plays bars 9-12 of lap 0 of the real run, then the clock
# seeks back and plays the same bars again with the next setup, and at
# the end a table of avg / worst frame time per setup is drawn on
# screen, so one screenshot says which part of the look the phone can
# afford. Setups, each one change against "all on":
#
#   all on · grain off · glow off · MSAA off · all post off (tonemap
#   linear too) · half the pillars · thin slab (the old 2-unit one)
#
# Frame times are the wall clock between two _process calls of this
# node (it runs first), the first SETTLE_S after each seek left out (the
# seek's own hitch). The table is also printed (PROBE lines) and put on
# the page as window.pr_probe for tools/web_shot.py.
# ============================================================

const Rules := preload("res://prototype/rules.gd")
const FROM_BAR := 9
const TO_BAR := 12
const SETTLE_S := 0.7
const SETUPS := [
	["warm-up", {}],           # thrown away: shader compiles and first draws land here, not in "all on"
	["all on", {}],
	["grain off", {"grain": false}],
	["glow off", {"glow": false}],
	["MSAA off", {"msaa": false}],
	["all post off", {"grain": false, "glow": false, "vignette": false, "msaa": false, "tonemap": "linear"}],
	["half the pillars", {"pillars": 0.5}],
	["thin slab (2)", {"slab": 2.0}],
]

var scene: Node = null
var _i := -1
var _last_usec := 0
var _settle := 0.0
var _sum := 0.0
var _worst := 0.0
var _n := 0
var _rows: Array = []
var _label: Label
var _done := false
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
	if _done or scene == null or scene.state != scene.State.RUN:
		return
	if _i < 0:
		# The run is up: a second for it to settle, then the first setup.
		_run_up += delta
		if _run_up >= 1.0:
			_start(0)
		return
	if _settle > 0.0:
		_settle -= delta
		return
	if ms > 0.0:
		_sum += ms
		_worst = maxf(_worst, ms)
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
			_rows.append([SETUPS[_i][0], _sum / maxf(_n, 1.0), _worst, _n, scene.deaths - _deaths0])
		if _i + 1 < SETUPS.size():
			_start(_i + 1)
		else:
			_finish()


func _start(i: int) -> void:
	_i = i
	_apply(SETUPS[i][1])
	# The way a checkpoint rewind and autoplay's start_bar put the bot in:
	# the player a unit into the bar, the window a lead behind it, so the
	# bot has time to get onto its plan before the window arrives.
	var lead: float = Rules.window_depth(scene.knobs) * 0.45 / BeatClock.track_speed
	var t0: float = maxf(BeatClock.start_offset, BeatClock.bar_start(FROM_BAR) - lead)
	scene.player.reset_to(0.0, BeatClock.z_at(BeatClock.bar_start(FROM_BAR)) + 1.0)
	BeatClock.seek(t0)
	_deaths0 = scene.deaths
	_settle = SETTLE_S
	_sum = 0.0
	_worst = 0.0
	_n = 0
	_label.text = "PROBE %d / %d: %s" % [i, SETUPS.size() - 1, SETUPS[i][0]] if i > 0 else "PROBE warm-up"
	print("PROBE start %s" % SETUPS[i][0])


# Everything back to "all on", then the setup's own change.
func _apply(change: Dictionary) -> void:
	scene.finish = {"tonemap": scene.TONEMAP_DEFAULT, "glow": true, "vignette": true, "grain": true, "msaa": true}
	for k in ["tonemap", "glow", "vignette", "grain", "msaa"]:
		if change.has(k):
			scene.finish[k] = change[k]
	scene.apply_finish()
	scene.field.set_pillar_density(float(change.get("pillars", 1.0)))
	scene.field.set_slab_thickness(float(change.get("slab", scene.field.THICK)))


func _finish() -> void:
	_done = true
	BeatClock.pause()
	var lines := ["PROBE  bars %d-%d of lap 0, %s  mem %d/%d MB" % [FROM_BAR, TO_BAR, FrameMeter.load_info,
		int(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0), int(OS.get_static_memory_peak_usage() / 1048576.0)]]
	lines.append("%-18s %7s %7s %6s %s" % ["setup", "avg ms", "worst", "frames", "deaths"])
	for r in _rows:
		lines.append("%-18s %7.1f %7.1f %6d %d" % [r[0], r[1], r[2], r[3], r[4]])
	var text := "\n".join(lines)
	_label.text = text
	for l in lines:
		print(l)
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.pr_probe=%s" % JSON.stringify(text), true)
