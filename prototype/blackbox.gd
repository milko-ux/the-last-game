extends RefCounted
# ============================================================
# THE BLACK BOX (2026-09-24, the iOS tab kill). When iOS kills the tab
# every log is lost, so the last ~30 events -- loading steps, seeks,
# deaths, the probe's setups, and a heartbeat with the bar, the frame
# time, the deaths and seeks so far and the renderer's texture / buffer
# memory -- are written to localStorage as they happen, with a "session
# open" marker that a normal page exit (pagehide) clears. On the next
# load, a session that was never closed is the one the phone lost, and
# its lines come back as "LAST SESSION ENDED AT: ..." on the readout
# (frame_meter.gd) and in the console. Web only; a few hundred bytes per
# write, at most a few writes a second; never inside a frame callback.
# ============================================================

const KEY := "pr_blackbox"
const LINES := 30
const HEARTBEAT_S := 2.0

static var _lines: PackedStringArray = PackedStringArray()
static var _t0 := 0
static var _since_beat := 0.0
static var last_session := ""      # what the previous, unclosed session left; "" if it closed cleanly
static var seeks := 0
static var deaths := 0
static var _armed := false


static func start() -> void:
	if not OS.has_feature("web") or _armed:
		return
	_armed = true
	_t0 = Time.get_ticks_msec()
	# The previous session: read, and judge by its marker.
	var prev := str(JavaScriptBridge.eval("(function(){try{var s=localStorage.getItem('%s')||'';var o=localStorage.getItem('%s_open')||'';return o+'|'+s}catch(e){return 'err|'}})()" % [KEY, KEY], true))
	var bar := prev.find("|")
	if bar >= 0:
		var open_marker := prev.substr(0, bar)
		var body := prev.substr(bar + 1)
		if open_marker == "1" and body != "":
			last_session = body
	# This session is open until the page says it is leaving.
	JavaScriptBridge.eval("try{localStorage.setItem('%s_open','1');localStorage.setItem('%s','');window.addEventListener('pagehide',function(){try{localStorage.setItem('%s_open','0')}catch(e){}})}catch(e){}" % [KEY, KEY, KEY], true)
	record("session start %s %s" % [OS.get_name(), "%dx%d" % [DisplayServer.window_get_size().x, DisplayServer.window_get_size().y]])


static func record(what: String) -> void:
	if not _armed:
		return
	var line := "%6.1fs %s" % [float(Time.get_ticks_msec() - _t0) / 1000.0, what]
	_lines.append(line)
	while _lines.size() > LINES:
		_lines.remove_at(0)
	var text := "\\n".join(_lines).replace("'", "")
	JavaScriptBridge.eval("try{localStorage.setItem('%s','%s')}catch(e){}" % [KEY, text], true)


# Called from the frame meter's _process.
static func heartbeat(delta: float, bar: int, frame_ms: float) -> void:
	if not _armed:
		return
	_since_beat += delta
	if _since_beat < HEARTBEAT_S:
		return
	_since_beat = 0.0
	record("bar %d  %.1f ms  deaths %d seeks %d  tex %d MB buf %d MB objs %d" % [bar, frame_ms,
		deaths, seeks,
		int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0),
		int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0),
		int(Performance.get_monitor(Performance.OBJECT_COUNT))])
