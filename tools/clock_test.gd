extends SceneTree
# ============================================================
# CLOCK TEST — the endless clock, headless, in a few seconds.
#
#   godot --headless --path . -s tools/clock_test.gd
#
# 1. Counting: over three laps (sampled every 10 ms, no audio) the run
#    beat / run bar / period numbers only ever step by 0 or +1, every
#    time sits inside the bar the clock names, lap 1's beats are lap 0's
#    + one loop length, the beat phase stays in 0..1.
# 2. The seam, live: plays from 1.5 s before the first seam to 1.5 s
#    after it and prints BeatClock's own SEAM line (run time's step per
#    frame: never negative, never more than two frames' worth).
# 3. Rewind across the seam: seek from lap 1 back into lap 0 and forward
#    again; lap, the place in the audio and z must follow.
# ============================================================

var clock: Node = null
var player: AudioStreamPlayer
var phase := 0
var fails := 0
var t_end := 0.0


func _check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
		print("  FAIL: " + what)


func _initialize() -> void:
	clock = root.get_node_or_null("BeatClock")
	if clock == null:
		clock = load("res://prototype/beat_clock.gd").new()
		clock.name = "BeatClock"
		root.add_child(clock)
	if not clock.loaded:
		clock._load()
	clock.set_endless(true)
	print("LOOP bars %d..%d  %.3f -> %.3f s  length %.3f s  %d bars  %d beats  first beat index %d" % [
		clock.LOOP_START_BAR, clock.LOOP_END_BAR, clock.loop_start_t, clock.loop_end_t, clock.loop_len,
		clock.loop_bars, clock.loop_beats, clock.loop_first_beat])

	# --- 1. counting
	var t: float = 8.0
	var end: float = clock.loop_end_t + 2.0 * clock.loop_len + 5.0
	var pb_prev := {4: -99999, 2: -99999, 1: -99999}
	var beat_prev := -99999
	var bar_prev := -99999
	var samples := 0
	while t < end:
		var b: int = clock.beat_at(t)
		var bar: int = clock.bar_at(t)
		if beat_prev != -99999:
			_check(b - beat_prev == 0 or b - beat_prev == 1, "beat index stepped %d at t=%.3f" % [b - beat_prev, t])
			_check(bar - bar_prev == 0 or bar - bar_prev == 1, "bar stepped %d at t=%.3f" % [bar - bar_prev, t])
		if bar >= 1:
			_check(t >= clock.bar_start(bar) - 1e-6 and t < clock.bar_end(bar) + 1e-6, "t=%.3f outside bar %d [%.3f, %.3f)" % [t, bar, clock.bar_start(bar), clock.bar_end(bar)])
		if b >= 0:
			_check(t >= clock.beat_time(b) - 1e-6 and t < clock.beat_time(b + 1) + 1e-6, "t=%.3f outside beat %d" % [t, b])
		var ph: float = clock.beat_phase_at(t)
		_check(ph >= 0.0 and ph <= 1.0, "beat phase %.3f at t=%.3f" % [ph, t])
		for pb in pb_prev:
			var idx: int = clock.period_index_at(t, pb)
			if pb_prev[pb] != -99999:
				_check(idx - pb_prev[pb] == 0 or idx - pb_prev[pb] == 1, "period(%d) stepped %d at t=%.3f" % [pb, idx - pb_prev[pb], t])
			if idx >= 1:
				_check(t >= clock.period_start(idx, pb) - 1e-6 and t < clock.period_end(idx, pb) + 1e-6, "t=%.3f outside period %d (pb %d)" % [t, idx, pb])
			pb_prev[pb] = idx
		beat_prev = b
		bar_prev = bar
		samples += 1
		t += 0.01
	for k in clock.loop_beats:
		var g: int = clock.loop_first_beat + k
		_check(is_equal_approx(clock.beat_time(g + clock.loop_beats), clock.beat_time(g) + clock.loop_len), "lap 1 beat %d is not lap 0 + loop" % k)
	_check(clock.bar_at(clock.loop_end_t + 0.001) == clock.loop_bars + 1, "first bar of lap 1 is run bar %d" % clock.bar_at(clock.loop_end_t + 0.001))
	_check(is_equal_approx(clock.bar_energy(clock.loop_bars + 5), clock.bar_energy(5)), "run bar 77 does not read beatmap bar 5")
	print("COUNTING %d samples over 3 laps: %s" % [samples, "ok" if fails == 0 else "%d FAILS" % fails])

	phase = 1


# --- 2. the seam, live (from the first frame: audio needs the tree running)
func _start_live() -> void:
	player = AudioStreamPlayer.new()
	var stream: AudioStream = load(clock.ENDLESS_MUSIC)
	stream.loop = true
	stream.loop_offset = clock.loop_start_t
	player.stream = stream
	player.volume_db = -80.0
	root.add_child(player)
	clock.start_offset = 8.0
	clock.start(player)
	clock.seek(clock.loop_end_t - 1.5)
	t_end = clock.loop_end_t + 1.6
	phase = 2


func _process(_delta: float) -> bool:
	if phase == 1:
		_start_live()
		return false
	if phase == 2:
		if clock.song_time() < t_end:
			return false
		_check(clock.current_lap() == 1, "lap after the seam is %d" % clock.current_lap())
		# --- 3. rewind across the seam
		var back: float = clock.loop_end_t - 4.0
		clock.seek(back)
		_check(clock.current_lap() == 0 and is_equal_approx(clock.song_time(), back), "rewind into lap 0: lap %d t %.3f" % [clock.current_lap(), clock.song_time()])
		var fwd: float = clock.loop_start_t + 3.0 * clock.loop_len + 7.0
		clock.seek(fwd)
		_check(clock.current_lap() == 3, "seek into lap 3: lap %d" % clock.current_lap())
		_check(is_equal_approx(clock.local_t(fwd), clock.loop_start_t + 7.0), "audio place for lap 3 + 7 s is %.3f" % clock.local_t(fwd))
		_check(is_equal_approx(clock.z_at(fwd), (fwd - clock.z_origin_t) * clock.track_speed), "z does not follow run time")
		print("REWIND across the seam: lap 1 -> lap 0 -> lap 3, audio place %.3f s, z %.1f" % [clock.local_t(fwd), clock.z_at(fwd)])
		print("CLOCK TEST %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
		clock.stop()
		return true
	return false
