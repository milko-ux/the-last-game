extends Label
class_name FrameMeter
# ============================================================
# FRAME METER — dev only. A small line in the top-right corner:
# the average and the worst frame time (ms) over the last 2 seconds,
# and next to it the game's own CPU time per frame, same 2 seconds.
# On a phone the frame time sits on the 60 fps cap (16.7) whatever the
# load, so the cpu number is the one that shows headroom: cpu 5 of
# 16.7 ms = plenty, cpu 14 = nearly full.
#
# cpu = (every node's and script's update this frame, timed from this
# node, which runs first, to a tail node, which runs last) + the
# engine's own figure for preparing the frame's drawing on the CPU
# (RenderingServer.get_frame_setup_time_cpu). NOT the engine monitor
# Performance.TIME_PROCESS, which was the first idea: that one is only
# refreshed about once a second with the WORST frame of that second, so
# its "average" read 13 ms while whole frames averaged 8. What neither
# number sees is the GPU: a frame time above the cap with a low cpu
# means the GPU (pixels, shaders) is the limit.
#
# Under it, for LOAD_SHOW_S seconds after a run starts, the LOAD LINE.
# THREE SPANS, each measured on its own, reset on EVERY load (2026-09-20:
# the first version kept counting through a retry, so "scene 72.9 s"
# included the play time, and a second load appended to the first):
#   page    the page was opened -> the first painted frame of the game
#           (on the web: the browser's own clock since navigation; it
#           covers the download and the engine start)
#   tap     a level / the run was tapped -> the first PAINTED frame of
#           the loading label (the label is drawn, a frame is waited for,
#           and only then does any blocking work start)
#   load    that painted label -> TAP TO START, with its steps in
#           brackets (scene file, validation, nodes, prewarm)
# A load that did not start with a tap (the page opens straight into the
# run; a RETRY) shows "tap -". The phone has no console: it is all on
# screen.
# Whenever ONE frame takes longer than SPIKE_MS it also prints a line
# to the console with the bar / beat and everything that spawned or
# fired during that frame, so a hitch can be pinned on its cause:
#
#   FRAME 41.3 ms  bar=12 beat=1 t=34.21  events=[downbeat, gate jump x2]
#
# ON in debug builds and while Progress.UNLOCK_ALL (the dev unlock
# switch) is true, so Milko sees it on the phone in the dev web
# export. OFF in a release with the unlock switch off: the node is
# never created and every note() call is one static bool test.
#
# Cost when on: one clock read and one array write per frame; the
# text is rebuilt four times a second, not per frame.
#
# A frame here is the time from one _process to the next, measured
# with the system clock, so it includes the GPU work (and any shader
# compile) of the frame it reports. The node runs first in the frame
# (process_priority), so every event noted during a frame lands in
# that frame's interval.
# ============================================================

const WINDOW_S := 2.0
const SPIKE_MS := 25.0
# The probe tool lowers this to see more frames; the game never touches it.
static var spike_ms := SPIKE_MS
const REFRESH_S := 0.25
const RING := 512                  # frames kept: 2 s at up to 240 fps
const LOAD_SHOW_S := 10.0          # the load line stays this long after the run starts
const LOAD_MIN_S := 0.2            # steps shorter than this are left out of the line

# True only while a meter node is alive: the guard every caller checks
# before building a string for note().
static var active := false
static var _events := {}           # what -> count, since the last frame tick
static var _window_back := 0.0
# Load timing: recorded always (a handful of clock reads per level load),
# shown only by a live meter. [name, seconds, note, always_show]
static var load_log: Array = []
static var load_info := ""          # a fixed note at the end of the load line (the render size)
static var _load_last := 0
static var _armed := false          # load_begin() was called and no scene has claimed it yet
static var _t_tap := -1             # msec; -1 = this load did not start with a tap
static var _t_label := -1           # msec; the loading label's first painted frame
static var _t_ready := -1           # msec; TAP TO START
static var page_s := -1.0           # the page span, measured once per page
static var label_timed_out := false
# A wait for a PAINTED frame may never last longer than this: if the
# frames do not come (a browser that will not paint, a stalled renderer),
# loading carries on anyway and the line says so. A gate that can wait
# for ever is the bug class; this ceiling is the rule for all of them.
const LABEL_TIMEOUT_MS := 2000

var _ms := PackedFloat32Array()
var _cpu := PackedFloat32Array()
var _load_label: Label
var _span_ms := 0.0               # the last frame's update time, from this node to the tail
var _load_shown := -1
var _load_hide_in := -1.0          # < 0: the run has not started, keep showing
var _head := 0
var _count := 0
var _last_usec := 0
var _refresh := 0.0
# Read by tools/frame_probe.gd.
var worst_ever_ms := 0.0
var spikes := 0


static func enabled() -> bool:
	# Never in the headless tools (the bots run capped at 30 fps with no display).
	if DisplayServer.get_name() == "headless":
		return false
	return OS.is_debug_build() or Progress.UNLOCK_ALL


# Something spawned, fired or changed this frame. Callers guard with
# `if FrameMeter.active:` so a release build never builds the string.
static func note(what: String, count: int = 1) -> void:
	if active:
		_events[what] = int(_events.get(what, 0)) + count


# Same, for something at field position z: marks it when it is outside
# the strip of field the camera sees (it still costs CPU, not GPU).
static func note_at(what: String, z: float) -> void:
	if active:
		var seen := z > _window_back - 10.0 and z < _window_back + 36.0
		note(what if seen else what + " (off-screen)")


# The FIRST painted frame of the game since the page was opened. Called
# from a scene's _process — NEVER from a frame_post_draw callback.
#
# 2026-09-20, the iPhone hang: this used to be called from inside the
# render step, and its web branch (the one line of the load instrument
# that a Mac never runs, since OS.has_feature("web") is false there) read
# the page clock through JavaScriptBridge from in there. Re-entering JS
# from the render step wedged the engine on iOS Safari; and a bare
# float() of what eval returns raises outright if that is ever Nil
# ("Nonexistent 'float' constructor"). Either way the caller's next line
# — the one that counts the painted frame — never ran, and the loading
# screen waited for a count that could no longer grow. Hence: nothing
# that can raise, and nothing that talks to the browser, runs inside a
# render callback; those callbacks only add 1 to an int.
static func first_frame_painted() -> void:
	if page_s >= 0.0:
		return
	page_s = _page_ms() / 1000.0


# Milliseconds since the page was opened (web), or since the engine
# started (anywhere else). Never raises: a browser that hands back
# something that is not a number falls back to the engine clock.
static func _page_ms() -> float:
	if OS.has_feature("web"):
		var v = JavaScriptBridge.eval("performance.now()")
		if typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT:
			return float(v)
	return float(Time.get_ticks_msec())


# A level / the run was TAPPED: a new load begins (everything is reset).
static func load_begin() -> void:
	_reset()
	_t_tap = Time.get_ticks_msec()
	_load_last = _t_tap
	_armed = true


static func _reset() -> void:
	load_log.clear()
	label_timed_out = false
	_t_tap = -1
	_t_label = -1
	_t_ready = -1
	_load_last = Time.get_ticks_msec()


# The run scene's _ready: claims the load a tap began, or — a page that
# opens straight into the run, a RETRY, a reload — starts a fresh one.
static func load_scene_started() -> void:
	if _armed:
		_armed = false
		load_mark("scene")
	else:
		_reset()


# The loading label has been PAINTED (a frame was drawn with it). Only the
# first call of a load counts: the level select paints its own label before
# it changes scene, the run scene paints another one.
# `timed_out`: the frames never came and the wait gave up (see
# LABEL_TIMEOUT_MS) — the span is still recorded, and says so.
static func load_label_painted(timed_out: bool = false) -> void:
	if _t_label < 0:
		_t_label = Time.get_ticks_msec()
		_load_last = _t_label
		label_timed_out = timed_out


# TAP TO START is on screen.
static func load_done() -> void:
	_t_ready = Time.get_ticks_msec()


# A load step just ended: it took the time since the previous mark.
# `always` keeps it in the line even when it was quick.
static func load_mark(step: String, note: String = "", always: bool = false) -> void:
	var now := Time.get_ticks_msec()
	load_log.append([step, float(now - _load_last) / 1000.0, note, always])
	_load_last = now


static func load_line() -> String:
	var parts := PackedStringArray()
	for e in load_log:
		if float(e[1]) >= LOAD_MIN_S or bool(e[3]):
			parts.append("%s %.1f%s" % [e[0], e[1], "" if String(e[2]).is_empty() else " (%s)" % e[2]])
	var page := "page %.1f s" % page_s if page_s >= 0.0 else "page -"
	var tap := "tap %.2f s%s" % [float(_t_label - _t_tap) / 1000.0, " TIMED OUT" if label_timed_out else ""] if _t_tap >= 0 and _t_label >= 0 else "tap -"
	var end := _t_ready if _t_ready >= 0 else Time.get_ticks_msec()
	var load := "load %.1f s" % (float(end - _t_label) / 1000.0) if _t_label >= 0 else "load -"
	var line := "%s   ·   %s   ·   %s  [%s]" % [page, tap, load, "  ·  ".join(parts)]
	if label_timed_out and _t_tap < 0:
		line += "   ·   label TIMED OUT"
	if load_info != "":
		line += "   ·   " + load_info
	return line


# Called by the run scene when the run starts: the load line goes away
# LOAD_SHOW_S later, and the averages forget the load frames.
func run_started() -> void:
	_load_hide_in = LOAD_SHOW_S
	_count = 0


func _ready() -> void:
	active = true
	_events.clear()
	_ms.resize(RING)
	_cpu.resize(RING)
	process_priority = -1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -640.0
	offset_right = -18.0
	offset_top = 22.0
	offset_bottom = 40.0
	grow_horizontal = Control.GROW_DIRECTION_BEGIN
	horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_theme_font_size_override("font_size", 12)
	add_theme_color_override("font_color", Color(0.66, 0.62, 0.76, 0.75))
	text = "frame — ms"
	BeatClock.beat.connect(func(_i: int) -> void: note("beat"))
	BeatClock.downbeat.connect(func(_b: int) -> void: note("downbeat"))
	note("scene start")
	_load_label = Label.new()
	_load_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_label.position = Vector2(622.0 - 430.0, 20.0)      # right-aligned under the readout, clear of the centre HUD
	_load_label.size = Vector2(430.0, 90.0)
	_load_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_load_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_load_label.add_theme_font_size_override("font_size", 12)
	_load_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.24, 0.9))
	add_child(_load_label)
	var tail := Tail.new()
	tail.meter = self
	add_child(tail)


func _exit_tree() -> void:
	active = false


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec != 0:
		var ms := float(now - _last_usec) / 1000.0
		_ms[_head] = ms
		_cpu[_head] = _span_ms + RenderingServer.get_frame_setup_time_cpu()
		_head = (_head + 1) % RING
		_count = mini(_count + 1, RING)
		if ms > spike_ms:
			_report(ms)
	_last_usec = now
	_events.clear()
	_window_back = BeatClock.z_at(BeatClock.song_time())
	if _load_hide_in >= 0.0:
		_load_hide_in -= delta
		if _load_hide_in < 0.0:
			_load_label.visible = false
			_load_hide_in = -2.0
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_S
		_update_text()


# Runs last in the frame: closes the update-time measurement.
class Tail extends Node:
	var meter: FrameMeter

	func _ready() -> void:
		process_priority = 1000
		process_mode = Node.PROCESS_MODE_ALWAYS

	func _process(_delta: float) -> void:
		meter._span_ms = float(Time.get_ticks_usec() - meter._last_usec) / 1000.0


func _report(ms: float) -> void:
	spikes += 1
	worst_ever_ms = maxf(worst_ever_ms, ms)
	var parts := PackedStringArray()
	for k in _events:
		parts.append(k if int(_events[k]) == 1 else "%s x%d" % [k, _events[k]])
	var ht := BeatClock.hazard_time()
	print("FRAME %.1f ms  bar=%d beat=%d t=%.2f  events=[%s]" % [ms, BeatClock.bar_at(ht),
		BeatClock.beat_in_bar_at(ht) + 1, BeatClock.song_time(), ", ".join(parts)])


# Average and worst over the last WINDOW_S seconds, newest frame first.
func _update_text() -> void:
	var sum := 0.0
	var worst := 0.0
	var cpu_sum := 0.0
	var cpu_worst := 0.0
	var n := 0
	var i := _head
	while n < _count and sum < WINDOW_S * 1000.0:
		i = (i - 1 + RING) % RING
		sum += _ms[i]
		worst = maxf(worst, _ms[i])
		cpu_sum += _cpu[i]
		cpu_worst = maxf(cpu_worst, _cpu[i])
		n += 1
	if n > 0:
		text = "frame %.1f avg · %.1f worst     cpu %.1f avg · %.1f worst ms" % [sum / n, worst, cpu_sum / n, cpu_worst]
		if BeatClock.endless and BeatClock.running():
			# Audio vs clock (ms, - = audio behind) and how much has been slewed to follow it.
			text += "     audio %+.0f (%+.0f)" % [BeatClock.audio_drift_ms(), BeatClock.drift_corrected_ms]
	# Only when a step was added: laying out a wrapped label is not free.
	if _load_label.visible and (load_log.size() != _load_shown or _t_ready < 0):
		_load_shown = load_log.size()
		_load_label.text = load_line()


# Average / worst over everything still in the ring (tools/frame_probe.gd).
func stats() -> Dictionary:
	var sum := 0.0
	var worst := 0.0
	for k in _count:
		var v := _ms[(_head - 1 - k + RING * 2) % RING]
		sum += v
		worst = maxf(worst, v)
	return {"frames": _count, "avg_ms": sum / maxi(_count, 1), "worst_ms": worst}
