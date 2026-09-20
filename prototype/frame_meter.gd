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
# Under it, for LOAD_SHOW_S seconds after a run starts, the LOAD LINE:
# how long each step between tapping a level and TAP TO START took
# (see load_begin / load_mark). The phone has no console.
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
static var _load_t0 := 0
static var _load_last := 0

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


# The moment a level was picked: the load clock starts.
static func load_begin() -> void:
	load_log.clear()
	_load_t0 = Time.get_ticks_msec()
	_load_last = _load_t0


# A load step just ended: it took the time since the previous mark.
# `always` keeps it in the line even when it was quick.
static func load_mark(step: String, note: String = "", always: bool = false) -> void:
	if _load_last == 0:
		load_begin()
	var now := Time.get_ticks_msec()
	load_log.append([step, float(now - _load_last) / 1000.0, note, always])
	_load_last = now


static func load_line() -> String:
	var parts := PackedStringArray()
	for e in load_log:
		if float(e[1]) >= LOAD_MIN_S or bool(e[3]):
			parts.append("%s %.1f%s" % [e[0], e[1], "" if String(e[2]).is_empty() else " (%s)" % e[2]])
	if load_info != "":
		parts.append(load_info)
	return "load %.1f s:  %s" % [float(_load_last - _load_t0) / 1000.0, "  ·  ".join(parts)]


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
	_load_label.position = Vector2(-380.0, 20.0)
	_load_label.size = Vector2(900.0, 60.0)
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
	if _load_label.visible and load_log.size() != _load_shown:
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
