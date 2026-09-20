extends Label
class_name FrameMeter
# ============================================================
# FRAME METER — dev only. A small line in the top-right corner:
# the average and the worst frame time (ms) over the last 2 seconds.
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

# True only while a meter node is alive: the guard every caller checks
# before building a string for note().
static var active := false
static var _events := {}           # what -> count, since the last frame tick
static var _window_back := 0.0

var _ms := PackedFloat32Array()
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


func _ready() -> void:
	active = true
	_events.clear()
	_ms.resize(RING)
	process_priority = -1000
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -260.0
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


func _exit_tree() -> void:
	active = false


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_usec != 0:
		var ms := float(now - _last_usec) / 1000.0
		_ms[_head] = ms
		_head = (_head + 1) % RING
		_count = mini(_count + 1, RING)
		if ms > spike_ms:
			_report(ms)
	_last_usec = now
	_events.clear()
	_window_back = BeatClock.z_at(BeatClock.song_time())
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = REFRESH_S
		_update_text()


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
	var n := 0
	var i := _head
	while n < _count and sum < WINDOW_S * 1000.0:
		i = (i - 1 + RING) % RING
		sum += _ms[i]
		worst = maxf(worst, _ms[i])
		n += 1
	if n > 0:
		text = "frame %.1f avg · %.1f worst ms" % [sum / n, worst]


# Average / worst over everything still in the ring (tools/frame_probe.gd).
func stats() -> Dictionary:
	var sum := 0.0
	var worst := 0.0
	for k in _count:
		var v := _ms[(_head - 1 - k + RING * 2) % RING]
		sum += v
		worst = maxf(worst, v)
	return {"frames": _count, "avg_ms": sum / maxi(_count, 1), "worst_ms": worst}
