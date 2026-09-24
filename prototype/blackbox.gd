extends RefCounted
# ============================================================
# THE BLACK BOX (2026-09-24, the iOS tab kill). When iOS kills the tab
# every log is lost, so the last ~30 events -- loading steps, seeks,
# deaths, the probe's setups, and a heartbeat with the bar, the frame
# time, the deaths and seeks so far, the audio drift, the renderer's
# texture / buffer memory and the window size -- are written to
# localStorage as they happen, with a "session open" marker that a normal
# page exit (pagehide) clears. On the next load, a session that was never
# closed is the one the phone lost, and its lines come back as "LAST
# SESSION ENDED AT: ..." on the readout (frame_meter.gd) and in the
# console.
#
# AND IT PHONES HOME (later the same day): every line is also sent to
# the serving Mac with navigator.sendBeacon (POST /bb?s=<session id>,
# tools/serve.py appends it to ../the-last-game-build/blackbox.log with
# the Mac's clock). A beacon is queued by the browser and sent even while
# the page is going away, so the lines that reached the Mac are the
# record when localStorage did not survive. The page side also reports
# what Godot cannot see: the canvas losing / regaining its WebGL context,
# an uncaught JS error, the tab going hidden / visible, and pagehide.
#
# Every line's time is PAGE time (performance.now(): seconds since the
# page was opened), the same clock as the readout's "page" span and the
# JS-side events, so the boot, the load and the run read as one timeline.
#
# Web only; a few hundred bytes per write, at most a few writes a second;
# never inside a frame callback.
# ============================================================

const KEY := "pr_blackbox"
const LINES := 30
const JS_LINES := 8              # JS-side events kept in localStorage (they go to the Mac too)
const HEARTBEAT_S := 2.0

static var _lines: PackedStringArray = PackedStringArray()
static var _page_offset_ms := 0.0   # performance.now() - Time.get_ticks_msec(), read once
static var _since_beat := 0.0
static var _last_win := Vector2i.ZERO
static var last_session := ""      # what the previous, unclosed session left; "" if it closed cleanly
static var seeks := 0
static var deaths := 0
static var _armed := false

# THE BOOT LINE (2026-09-24, "why does the phone load in 12-15 s"): the
# browser's own Resource Timing for index.js / index.wasm / index.pck
# (start-end in page seconds, bytes over the wire), the HTML's arrival,
# the wasm instantiate (window.pr_wasm, from the wrapper in the export
# preset's head_include; the shell streams it, so download and compile
# overlap and the compile tail is its end minus index.wasm's end), and
# when Godot's main started. Read
# once, at start(); the load steps then follow on the same clock.
const BOOT_JS := """(function(){try{
var o=[];var n=performance.getEntriesByType('navigation')[0];
if(n)o.push('html '+(n.responseEnd/1000).toFixed(2)+'s');
performance.getEntriesByType('resource').forEach(function(e){var f=e.name.split('/').pop().split('?')[0];
 if(f=='index.js'||f=='index.wasm'||f=='index.pck'){var b=e.transferSize||e.encodedBodySize||0;
 o.push(f+' '+(e.startTime/1000).toFixed(1)+'-'+(e.responseEnd/1000).toFixed(1)+'s '+(b?(b/1048576).toFixed(1)+' MB':'size n/a'))}});
if(window.pr_wasm)o.push('wasm '+(window.pr_wasm[2]||'instantiate')+' '+(window.pr_wasm[0]/1000).toFixed(1)+'-'+(window.pr_wasm[1]/1000).toFixed(1)+'s');
return o.join(', ')}catch(e){return 'n/a '+e}})()"""

# Installed once: the session id, the beacon sender, and the page-side
# event listeners. `%s` = KEY. No `%` anywhere else in here.
const INSTALL_JS := """(function(){try{
var K='%s';
localStorage.setItem(K+'_open','1');localStorage.setItem(K,'');localStorage.setItem(K+'_js','');
var sid=Date.now().toString(36)+Math.random().toString(36).slice(2,6);
function send(l){try{navigator.sendBeacon('bb?s='+sid,l)}catch(e){}}
function js(w){var l=(performance.now()/1000).toFixed(1)+'s js '+w;send(l);
 try{var j=(localStorage.getItem(K+'_js')||'').split('\\n').filter(Boolean);j.push(l);while(j.length>%d)j.shift();localStorage.setItem(K+'_js',j.join('\\n'))}catch(e){}}
window.pr_bb={sid:sid,send:send,js:js};
var ua=navigator.userAgent;var m=ua.match(/\\((iPhone|iPad|Macintosh|Android)[^)]*\\)/);
js('page '+(m?m[0]:ua.slice(0,60))+(/CriOS|Chrome/.test(ua)?' Chrome':(/Safari/.test(ua)?' Safari':''))+' inner '+innerWidth+'x'+innerHeight+' dpr '+devicePixelRatio+(navigator.standalone?' standalone':''));
var c=document.getElementById('canvas');
if(c){c.addEventListener('webglcontextlost',function(){js('WEBGL CONTEXT LOST')});c.addEventListener('webglcontextrestored',function(){js('webgl context restored')})}
window.addEventListener('error',function(e){js('error '+String(e.message||e).slice(0,140))});
window.addEventListener('unhandledrejection',function(e){js('rejection '+String(e.reason).slice(0,140))});
document.addEventListener('visibilitychange',function(){js('visibility '+document.visibilityState)});
window.addEventListener('pagehide',function(){try{localStorage.setItem(K+'_open','0')}catch(e){};js('pagehide (clean exit)')});
}catch(e){}})()"""


static func start() -> void:
	if not OS.has_feature("web") or _armed:
		return
	_armed = true
	var now = JavaScriptBridge.eval("performance.now()")
	if typeof(now) == TYPE_FLOAT or typeof(now) == TYPE_INT:
		_page_offset_ms = float(now) - float(Time.get_ticks_msec())
	# The previous session: read, and judge by its marker. Its JS-side
	# lines (context lost, errors) come after its own lines.
	var prev := str(JavaScriptBridge.eval("(function(){try{var s=localStorage.getItem('%s')||'';var j=localStorage.getItem('%s_js')||'';var o=localStorage.getItem('%s_open')||'';return o+'|'+s+(j?'\\n'+j:'')}catch(e){return 'err|'}})()" % [KEY, KEY, KEY], true))
	var bar := prev.find("|")
	if bar >= 0:
		var open_marker := prev.substr(0, bar)
		var body := prev.substr(bar + 1)
		if open_marker == "1" and body != "":
			last_session = body
	# This session is open until the page says it is leaving.
	JavaScriptBridge.eval(INSTALL_JS % [KEY, JS_LINES], true)
	_last_win = DisplayServer.window_get_size()
	record("session start %s %dx%d  engine main at %.1fs" % [OS.get_name(), _last_win.x, _last_win.y, _page_offset_ms / 1000.0])
	record("boot " + str(JavaScriptBridge.eval(BOOT_JS, true)))


# Seconds since the page was opened (the same clock as performance.now()).
static func page_s() -> float:
	return (float(Time.get_ticks_msec()) + _page_offset_ms) / 1000.0


static func record(what: String) -> void:
	if not _armed:
		return
	var line := ("%6.1fs %s" % [page_s(), what]).replace("'", "").replace("\\", "")
	_lines.append(line)
	while _lines.size() > LINES:
		_lines.remove_at(0)
	var text := "\\n".join(_lines)
	# One eval: the localStorage write and the beacon to the Mac.
	JavaScriptBridge.eval("try{localStorage.setItem('%s','%s')}catch(e){};try{window.pr_bb&&window.pr_bb.send('%s')}catch(e){}" % [KEY, text, line], true)


# Called from the frame meter's _process. drift_ms: the audio against the
# clock (BeatClock.audio_drift_ms(); a constant offset is normal, a change
# after a seek is the song not following it).
static func heartbeat(delta: float, bar: int, frame_ms: float, drift_ms: float) -> void:
	if not _armed:
		return
	# The window size, whenever it changes (rotation, the browser bars).
	var win := DisplayServer.window_get_size()
	if win != _last_win:
		_last_win = win
		record("resize %dx%d" % [win.x, win.y])
	_since_beat += delta
	if _since_beat < HEARTBEAT_S:
		return
	_since_beat = 0.0
	record("bar %d  %.1f ms  deaths %d seeks %d  drift %+d ms  tex %d MB buf %d MB objs %d  win %dx%d" % [bar, frame_ms,
		deaths, seeks, int(drift_ms),
		int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0),
		int(Performance.get_monitor(Performance.RENDER_BUFFER_MEM_USED) / 1048576.0),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)), win.x, win.y])
