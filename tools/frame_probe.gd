extends SceneTree
# ============================================================
# FRAME PROBE — measures the things behind a "the screen jumps"
# report, without anyone playing. Same pattern as tools/shot.gd: it
# opens the run scene, the validator bot carries the player, the
# audio is muted, and it quits by itself at `bars`.
#
#   godot --path . --resolution 1200x540 -s tools/frame_probe.gd -- level=3 bars=24
#   ... --rendering-method gl_compatibility     (the renderer the web build uses)
#   ... spike=12                                 (report frames over 12 ms, not 25)
#
# It prints, besides the frame meter's own FRAME lines (> 25 ms, with
# what fired on that frame):
#   CAMSTEP  every frame where a point that is FIXED relative to the
#            camera rig moved more than `step_px` on screen: the whole
#            picture jumped that much in one frame, by the camera's
#            own doing (nod, FOV punch, kick), not by the scroll.
#   CLOCK    how evenly the song clock (which positions everything)
#            advances compared with the engine's own frame delta: the
#            median / 99th percentile / worst difference per frame, in
#            ms, hitch frames excluded. A clock that advanced in audio
#            chunks would show 10-20 ms here.
#   FIRSTSEEN  the first time each kind of hazard enters the camera's
#            view (the moment its shader is first drawn), to line up
#            with FRAME spikes that have no event.
#   PROBE    the summary: frames, average / worst ms, spikes.
# ============================================================

var level := 1
var endless := false         # endless=1: the endless run instead of one level (start_lap=N: enter at lap N)
var start_lap := 0
var live := false            # live=1: ignore stored verdicts, every lap is generated + validated live
var bars := 16
var step_px := 1.5
var _spike := 25.0            # spike=12: report frames over 12 ms instead of 25
var test: Node = null
var clock: Node = null
var _args_read := false
var _prev_px: Array = []
var _prev_st := -1.0
var _clock_err := PackedFloat32Array()
var _seen := {}
var _worst_cam := 0.0
var _cam_steps := 0
var _cam_steps_on_downbeat := 0
var _downbeat_this_frame := false
var _beat_this_frame := false
var _frames := 0
# Points fixed relative to the rig (the window centre): far-left, near-right, centre-far.
const PROBES := [Vector3(7.0, 0.0, 9.0), Vector3(-7.0, 0.0, -7.0), Vector3(0.0, 0.0, 12.0)]


func _process(_delta: float) -> bool:
	if not _args_read:
		_args_read = true
		for a in OS.get_cmdline_user_args():
			var kv: PackedStringArray = a.split("=")
			if kv.size() == 2:
				match kv[0]:
					"level": level = int(kv[1])
					"endless": endless = kv[1] == "1"
					"live": live = kv[1] == "1"
					"start_lap": start_lap = int(kv[1])
					"bars": bars = int(kv[1])
					"step_px": step_px = float(kv[1])
					"spike": _spike = float(kv[1])
	if test == null:
		_setup()
		return false
	if test.state == test.State.WAIT:
		test.start_now()
		return false
	if test.state != test.State.RUN:
		_prev_px.clear()
		return false
	_measure(_delta)
	if clock.current_bar() > bars:
		_summary()
		return true
	return false


func _measure(delta: float) -> void:
	_frames += 1
	var rig: Node3D = test.rig
	var cam: Camera3D = rig.cam
	var px := []
	for p in PROBES:
		px.append(cam.unproject_position(rig.global_position + p))
	var st: float = clock.song_time()
	for h in test.field.hazards:
		if not _seen.has(h.kind) and cam.is_position_in_frustum(h.global_position):
			_seen[h.kind] = true
			print("FIRSTSEEN %s  t=%.2f bar=%d (its z = bar %d)" % [h.kind, st, clock.current_bar(), int(h.spec["bar"])])
	if not _prev_px.is_empty():
		var worst := 0.0
		for i in px.size():
			worst = maxf(worst, (px[i] - _prev_px[i]).length())
		_worst_cam = maxf(_worst_cam, worst)
		if worst > step_px:
			_cam_steps += 1
			if _downbeat_this_frame:
				_cam_steps_on_downbeat += 1
			print("CAMSTEP %.1f px  bar=%d beat=%d  downbeat_frame=%s fov=%.2f nod=%.2f deg" % [worst, clock.current_bar(),
				clock.beat_in_bar_at(clock.song_time()) + 1, _downbeat_this_frame, cam.fov, rad_to_deg(test.motion.nod())])
	if _prev_st >= 0.0 and delta < 0.025:
		var e := absf((st - _prev_st) - delta) * 1000.0
		_clock_err.append(e)
		if e > 2.0:
			print("CLOCKSTEP %.2f ms off the frame delta (%.2f ms) at t=%.2f" % [e, delta * 1000.0, st])
	_prev_px = px
	_prev_st = st
	_downbeat_this_frame = false
	_beat_this_frame = false


func _summary() -> void:
	var m: Node = test.meter
	var s: Dictionary = m.stats() if m != null else {}
	_clock_err.sort()
	var n := _clock_err.size()
	if n > 0:
		print("CLOCK song-clock step vs frame delta: median %.2f ms, p99 %.2f ms, worst %.2f ms over %d frames (= %.3f units of scroll at the worst)" % [
			_clock_err[n / 2], _clock_err[int(n * 0.99)], _clock_err[n - 1], n, _clock_err[n - 1] / 1000.0 * clock.track_speed])
	print("PROBE level=%d bars=%d frames=%d  last-ring avg=%.2f ms worst=%.2f ms  spikes(>25ms)=%d worst_ever=%.1f ms  camsteps(>%.1fpx)=%d on_downbeat=%d worst_camstep=%.1f px" % [
		level, bars, _frames, s.get("avg_ms", 0.0), s.get("worst_ms", 0.0), m.spikes if m != null else -1,
		m.worst_ever_ms if m != null else -1.0, step_px, _cam_steps, _cam_steps_on_downbeat, _worst_cam])


func _setup() -> void:
	AudioServer.set_bus_volume_db(0, -80.0)
	var Rules: GDScript = load("res://prototype/rules.gd")
	Rules.ENDLESS = endless
	var progress = root.get_node_or_null("Progress")
	if progress != null:
		progress.save_enabled = false
	Rules.START_LAP = start_lap
	load("res://prototype/lap_gen.gd").ignore_verdicts = live
	if level != 1:
		Rules.LEVEL = level
	Rules.LIVES_OVERRIDE = 0
	clock = root.get_node_or_null("BeatClock")
	if clock == null:
		clock = load("res://prototype/beat_clock.gd").new()
		clock.name = "BeatClock"
		root.add_child(clock)
	clock.downbeat.connect(func(_b: int) -> void: _downbeat_this_frame = true)
	clock.beat.connect(func(_i: int) -> void: _beat_this_frame = true)
	test = load("res://prototype/track_test.tscn").instantiate()
	root.add_child(test)
	load("res://prototype/frame_meter.gd").spike_ms = _spike
	var ap: Object = load("res://tools/autoplay.gd").new()   # the validator bot, as in shot.gd
	test.bot = ap
	ap.mode = "validator"
	ap.clock = clock
	ap.Rules = Rules
	ap.HazardMath = load("res://prototype/hazard_math.gd")
	ap.test = test
	if endless:
		ap.attach_endless(test, clock)
	else:
		var fair: Dictionary = test.field.fairness
		if fair.get("cached", false) or fair["path"].is_empty():
			fair = load("res://prototype/fairness.gd").validate(test.field.plan, clock, test.knobs)
		ap.path = fair["path"]
		ap.first_beat = int(fair["first_beat"])
