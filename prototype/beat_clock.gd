extends Node
# ============================================================
# BEAT CLOCK (autoload `BeatClock`) — the one source of truth for
# "where are we in the song?".
#
# Phase R rule: position IS time. The player's forward position,
# every hazard's state and the camera's beat punch are all pure
# functions of song_time(). There is no separate respawn logic:
# death just seeks the song and everything re-derives itself.
#
# It is registered as an autoload so the prototype scripts can
# simply say BeatClock.song_time(), but it stays INERT in the 2D
# game: nothing ticks until a scene calls start().
#
# Sync method is Godot's recommended one for a few-minute track:
# system clock + latency compensation (never the stream's own
# playback position, which only updates per audio chunk).
#
# SMOOTHED (2026-09-20). song_time() is NOT the raw system clock: it
# advances by the engine's frame delta once per frame and is pulled
# gently toward the system-clock time (CLOCK_CORRECT_TAU_S), snapping
# only if it is ever more than CLOCK_SNAP_S off. Why: the raw clock is
# read at whatever moment the script happens to run inside the frame,
# and that moment wanders (measured with tools/frame_probe.gd: the
# raw clock's step differed from the frame delta by 3.5 ms median, 12
# ms worst). Everything on screen is positioned from this clock, so
# that wander was the whole picture trembling along the scroll. The
# value is also constant within a frame now: every reader agrees.
# ============================================================

signal beat(index: int)
signal downbeat(bar: int)
signal section_changed(section_id: int)
signal lap_changed(lap: int)

# ONE beatmap (fuffens_beatmap.json, analysed at the original tempo). The
# level's `song_tempo` knob picks a time-stretched mp3 (_105, _110: the
# only extra audio files) and set_tempo() divides every beatmap time by
# the tempo, which is exactly what a time-stretch does to them.
const BEATMAP_PATH := "res://assets/audio/fuffens_beatmap.json"
const MUSIC_BASE := "res://assets/audio/fuffens_instrumental_vers"
var tempo := 1.0

# ------------------------------------------------------------
# THE ENDLESS RUN (Phase E brief 1, section 2). The song loops: the
# intro plays once, then bars LOOP_START_BAR .. LOOP_END_BAR - 1 repeat
# for ever (bar 73's downbeat is where the audio jumps back to bar 1's).
# Bars 73-78, the fade-out, never play. Milko confirms the seam by ear
# and may move LOOP_END_BAR to another 8-bar boundary (+ 1); re-cut the
# audio with tools/make_endless_audio.py <bar> when he does.
#
# RUN TIME. In an endless run song_time() IS the run time: it starts at
# the start offset and only ever grows (it is the smoothed system clock,
# which knows nothing about the audio wrapping; the audio file loops on
# its own, sample-exact). lap = how many times the loop has been passed.
# Everything that takes a time `t` below folds it back into the loop, so
# beat, bar and period numbers keep COUNTING across laps:
#   run bar  = lap x 72 + bar         (bar_at, bar_start, bar_energy ...)
#   run beat = lap x 288 + beat       (beat_at, beat_time, period_*)
# and z_at(t) keeps growing: z is absolute, no re-origin.
# With `endless` off (the dev level path) nothing here changes anything.
# ------------------------------------------------------------
const LOOP_START_BAR := 1
const LOOP_END_BAR := 73
const ENDLESS_MUSIC := "res://assets/audio/fuffens_endless.ogg"
# The run-up the z axis is measured from (level 1's song offset). Fixed,
# so the course sits at the same z whether the run starts with the full
# run-up or the short retry one.
const ENDLESS_Z_ORIGIN_S := 8.0
var endless := false
var loop_start_t := 0.0
var loop_end_t := 0.0
var loop_len := 0.0
var loop_bars := 0
var loop_first_beat := 0
var loop_beats := 0
var beatmap_path := BEATMAP_PATH   # (read by the verdict cache key)

# Hazards run this much BEHIND the audio clock so the visual hit lands
# with the transient you actually hear (audio output tends to be later
# than the engine believes). Positive = hazards later, negative = earlier.
# The single knob Milko tunes if things feel late: try 0.030 -> 0.060.
const SYNC_OFFSET_S := 0.030

# The smoothed clock closes this share of its distance to the system
# clock per CLOCK_CORRECT_TAU_S (an exponential pull: gentle enough to
# hide per-frame wander, quick enough to follow real drift), and gives
# up and snaps if it is ever further than CLOCK_SNAP_S away (a long
# hitch, a backgrounded tab).
const CLOCK_CORRECT_TAU_S := 0.5
const CLOCK_SNAP_S := 0.05

# One bar of music is this many world units of field. Everything spatial
# (tile size, window depth, camera distance) was chosen around it.
const BAR_UNITS := 8.0

var loaded := false
var bpm := 0.0
var beat_interval := 0.5
var duration := 0.0
var beats := PackedFloat64Array()
var downbeats := PackedFloat64Array()
var bars: Array = []        # one Dictionary per bar: bar, t, energy, low, mid, high
var sections: Array = []    # id, start_bar, end_bar, start_s, energy
var mean_bar_s := 2.0
# SCROLL_SPEED (addendum): world units per second the window advances.
# = BAR_UNITS / (4 * beat_interval), derived from bpm, never hand-set.
var track_speed := 4.0
var first_bar_beat := 0     # index into beats of bar 1's downbeat
# Addendum 4 section 2: playback starts this far into the track (8 s on
# level 1, 10 s on later levels), so the run-up to bar 1 is short. The
# beatmap's times stay absolute; song_time() is absolute too. Only the
# mapping to the field (z_at / t_at) and the progress fraction subtract
# it, so z = 0 is where the run starts. Set by the scene before start().
var start_offset := 0.0
# The song time at which z = 0. The level path keeps it equal to the start
# offset (set_start_offset); the endless run pins it (ENDLESS_Z_ORIGIN_S).
var z_origin_t := 0.0

var _player: AudioStreamPlayer
var _time_begin := 0
var _time_delay := 0.0
var _base_t := 0.0
var _running := false
var _paused := false
var _paused_t := 0.0
var _smooth_t := 0.0
var _prev_beat := -1
var _prev_bar := 0
var _prev_section := 0
var _prev_lap := 0
# Seam log (section 2 acceptance): run time's per-frame step around a seam.
var _seam_min := INF
var _seam_max := -INF
var _seam_ratio := 0.0
var _seam_frames := 0
var _seam_negative := 0


func _ready() -> void:
	set_process(false)
	_load()


# "" for 1.0, "_105" for 1.05, "_110" for 1.10.
static func tempo_suffix(t: float) -> String:
	var pct := roundi(t * 100.0)
	return "" if pct == 100 else "_%d" % pct


# Called by the scene (and the tools) before the field is built: reloads
# the one beatmap with its times divided by the tempo.
func set_tempo(t: float) -> void:
	if is_equal_approx(t, tempo) and loaded:
		return
	tempo = t
	loaded = false
	_load()


func music_path() -> String:
	return MUSIC_BASE + tempo_suffix(tempo) + ".mp3"


func _load() -> void:
	var f := FileAccess.open(beatmap_path, FileAccess.READ)
	if f == null:
		push_error("BeatClock: cannot open %s" % beatmap_path)
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("BeatClock: %s is not valid JSON" % beatmap_path)
		return
	# Every time in the file is at the original tempo: divide by `tempo`.
	var k := 1.0 / maxf(tempo, 0.01)
	bpm = float(data.get("bpm", 120.0)) * tempo
	beat_interval = float(data.get("beat_interval_s", 60.0 / float(data.get("bpm", 120.0)))) * k
	duration = float(data.get("duration_s", 0.0)) * k
	beats = PackedFloat64Array(data.get("beats_s", []))
	downbeats = PackedFloat64Array(data.get("downbeats_s", []))
	for i in beats.size():
		beats[i] *= k
	for i in downbeats.size():
		downbeats[i] *= k
	bars = []
	for b in data.get("bars", []):
		var bb: Dictionary = b.duplicate()
		bb["t"] = float(bb["t"]) * k
		bars.append(bb)
	sections = []
	for sec in data.get("sections", []):
		var ss: Dictionary = sec.duplicate()
		if ss.has("start_s"):
			ss["start_s"] = float(ss["start_s"]) * k
		if ss.has("end_s"):
			ss["end_s"] = float(ss["end_s"]) * k
		sections.append(ss)
	if bars.size() >= 2:
		mean_bar_s = (float(bars[-1]["t"]) - float(bars[0]["t"])) / float(bars.size() - 1)
	else:
		mean_bar_s = beat_interval * 4.0
	track_speed = BAR_UNITS / (4.0 * beat_interval)
	if not downbeats.is_empty():
		first_bar_beat = maxi(0, beats.bsearch(downbeats[0], false) - 1)
	if bars.size() >= LOOP_END_BAR:
		loop_start_t = float(bars[LOOP_START_BAR - 1]["t"])
		loop_end_t = float(bars[LOOP_END_BAR - 1]["t"])
		loop_len = loop_end_t - loop_start_t
		loop_bars = LOOP_END_BAR - LOOP_START_BAR
		loop_first_beat = maxi(0, beats.bsearch(loop_start_t, false) - 1)
		loop_beats = maxi(0, beats.bsearch(loop_end_t, false) - 1) - loop_first_beat
	loaded = true


# The level path: playback starts at `t`, and z = 0 is there.
func set_start_offset(t: float) -> void:
	start_offset = t
	z_origin_t = t


# The endless run: the looped track, tempo 1.0, z measured from the
# standard run-up whatever this run's own start offset is.
func set_endless(on: bool) -> void:
	endless = on
	if on:
		set_tempo(1.0)
		z_origin_t = ENDLESS_Z_ORIGIN_S


# ------------------------------------------------------------
# Folding run time back into the loop
# ------------------------------------------------------------
func lap_at(t: float) -> int:
	if not endless or t < loop_end_t or loop_len <= 0.0:
		return 0
	return int(floor((t - loop_start_t) / loop_len))


# The position inside the track that run time t corresponds to.
func local_t(t: float) -> float:
	return t - lap_at(t) * loop_len


func current_lap() -> int:
	return lap_at(song_time())


# Run time IS song_time() in an endless run; the alias is for readers.
func run_time() -> float:
	return song_time()


# Time of beat i, where i keeps counting across laps.
func beat_time(i: int) -> float:
	if not endless or i < loop_first_beat + loop_beats:
		return beats[clampi(i, 0, beats.size() - 1)]
	var j := i - loop_first_beat
	return beats[loop_first_beat + j % loop_beats] + float(j / loop_beats) * loop_len


# A run bar -> [lap, bar inside the loop (1-based)].
func _fold_bar(bar: int) -> Vector2i:
	if not endless or bar < LOOP_END_BAR:
		return Vector2i(0, bar)
	var j := bar - LOOP_START_BAR
	return Vector2i(j / loop_bars, LOOP_START_BAR + j % loop_bars)


# How far the audio really is from where the clock says it is (ms, +
# = audio ahead). Dev read-out only; nothing is corrected with it.
func audio_drift_ms() -> float:
	if _player == null or not _player.playing:
		return 0.0
	var heard := _player.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	var d := heard - local_t(_raw_time())
	if loop_len > 0.0 and endless:
		d = fposmod(d + loop_len * 0.5, loop_len) - loop_len * 0.5
	return d * 1000.0


# ------------------------------------------------------------
# Transport
# ------------------------------------------------------------
func start(stream_player: AudioStreamPlayer) -> void:
	_player = stream_player
	_base_t = start_offset
	_smooth_t = start_offset
	_paused = false
	_time_begin = Time.get_ticks_usec()
	_time_delay = AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
	_player.play(local_t(start_offset))
	_running = true
	_resync_indices()
	set_process(true)


# Checkpoint rewind: the song jumps to t and song_time() returns t.
func seek(t: float) -> void:
	if _player == null:
		return
	_base_t = t
	_smooth_t = t
	_paused = false
	_time_begin = Time.get_ticks_usec()
	_time_delay = AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
	# Across the seam too: the audio goes to the place INSIDE the loop, the
	# clock (and with it the lap) to the run time asked for.
	if _player.playing and not _player.stream_paused:
		_player.seek(local_t(t))
	else:
		_player.stream_paused = false
		_player.play(local_t(t))
	_resync_indices()


# Death freeze: time stands still, hazards hold their pose, music stops.
func pause() -> void:
	if not _running or _paused:
		return
	_paused_t = song_time()
	_paused = true
	_player.stream_paused = true


func stop() -> void:
	_running = false
	set_process(false)
	if _player != null:
		_player.stop()


func running() -> bool:
	return _running


# ------------------------------------------------------------
# Time queries
# ------------------------------------------------------------
func song_time() -> float:
	if not _running:
		return start_offset
	if _paused:
		return _paused_t
	return _smooth_t


# The system clock with latency compensation: what the smoothed clock
# follows. Nothing positions itself from this directly.
func _raw_time() -> float:
	var t := (Time.get_ticks_usec() - _time_begin) / 1_000_000.0
	return _base_t + max(0.0, t - _time_delay)


func _advance(delta: float) -> void:
	var raw := _raw_time()
	if raw <= _base_t:
		_smooth_t = raw          # still waiting out the output latency
		return
	_smooth_t += delta
	var err := raw - _smooth_t
	if absf(err) > CLOCK_SNAP_S:
		_smooth_t = raw
	else:
		_smooth_t += err * (1.0 - exp(-delta / CLOCK_CORRECT_TAU_S))


# The clock hazards read. Same clock, shifted by the sync offset.
func hazard_time() -> float:
	return song_time() - SYNC_OFFSET_S


# Index into beats of the last beat at or before t. -1 during the intro.
func beat_at(t: float) -> int:
	if endless and t >= loop_end_t:
		var lap := lap_at(t)
		return beats.bsearch(t - lap * loop_len, false) - 1 + lap * loop_beats
	return beats.bsearch(t, false) - 1


func current_beat() -> int:
	return beat_at(song_time())


# 1-based bar number of the last downbeat at or before t. 0 during the intro.
func bar_at(t: float) -> int:
	if endless and t >= loop_end_t:
		var lap := lap_at(t)
		return downbeats.bsearch(t - lap * loop_len, false) + lap * loop_bars
	return downbeats.bsearch(t, false)


func current_bar() -> int:
	return bar_at(song_time())


# 0..1 progress through the current beat. During the intro the grid is
# extrapolated backwards from the first beat so the camera can still pulse.
func beat_phase() -> float:
	return beat_phase_at(song_time())


func beat_phase_at(t: float) -> float:
	var i := beat_at(t)
	if beats.is_empty():
		return 0.0
	if i < first_bar_beat:
		var anchor: float = downbeats[0] if not downbeats.is_empty() else beats[0]
		return fposmod((t - anchor) / beat_interval, 1.0)
	if endless:
		var b0 := beat_time(i)
		return clampf((t - b0) / maxf(beat_time(i + 1) - b0, 0.001), 0.0, 1.0)
	if i >= beats.size() - 1:
		return clampf((t - beats[i]) / beat_interval, 0.0, 1.0)
	return clampf((t - beats[i]) / (beats[i + 1] - beats[i]), 0.0, 1.0)


# Which beat of the bar (0..3) time t falls in. Before the first downbeat
# the grid is extrapolated backwards at the beat interval, so the intro
# rehearsal runs on the same grid the song will use.
func beat_in_bar_at(t: float) -> int:
	var i := beat_at(t)
	if i < first_bar_beat:
		if downbeats.is_empty():
			return 0
		return posmod(int(floor((t - downbeats[0]) / beat_interval)), 4)
	return (i - first_bar_beat) % 4


# Hazards are inert during the run-up and arm on the first downbeat.
func hazards_armed_at(t: float) -> bool:
	return loaded and not bars.is_empty() and t >= bar_start(1)


func bar_count() -> int:
	return bars.size()


func bar_start(bar: int) -> float:
	if endless:
		var f := _fold_bar(bar)
		return float(bars[f.y - 1]["t"]) + f.x * loop_len
	return float(bars[bar - 1]["t"])


func bar_end(bar: int) -> float:
	if endless:
		return bar_start(bar + 1)
	if bar < bars.size():
		return float(bars[bar]["t"])
	return bar_start(bar) + mean_bar_s


# 0..1 progress of time t through the given bar (clamped).
func bar_progress(bar: int, t: float) -> float:
	var s := bar_start(bar)
	var e := bar_end(bar)
	return clampf((t - s) / (e - s), 0.0, 1.0)


# Timestamps of the four beats inside a bar, taken from the real beat
# list where possible so hazards sit on the drummer's beats, not a grid.
func bar_beats(bar: int) -> PackedFloat64Array:
	var f := _fold_bar(bar)
	var shift := f.x * loop_len
	var s := bar_start(bar)
	var e := bar_end(bar)
	var out := PackedFloat64Array()
	for b in beats:
		if b + shift >= s - 0.02 and b + shift < e - 0.02:
			out.append(b + shift)
	if out.size() != 4:
		out.clear()
		for k in 4:
			out.append(s + (e - s) * k / 4.0)
	return out


func bar_energy(bar: int) -> float:
	return float(bars[_fold_bar(bar).y - 1].get("energy", 0.0))


func bar_band(bar: int, band: String) -> float:
	return float(bars[_fold_bar(bar).y - 1].get(band, 0.0))


func section_of_bar(bar: int) -> int:
	bar = _fold_bar(bar).y
	for s in sections:
		if bar >= int(s["start_bar"]) and bar <= int(s["end_bar"]):
			return int(s["id"])
	return 0


func is_section_start(bar: int) -> bool:
	bar = _fold_bar(bar).y
	for s in sections:
		if int(s["start_bar"]) == bar:
			return true
	return false


# ------------------------------------------------------------
# Hazard periods (addendum 3). Hazards act once per PERIOD, which is
# `pb` beats long: 4 ("bar", level 1), 2 ("half_bar") or 1 ("beat").
# Period 1 starts on bar 1's downbeat; before that the grid is
# extrapolated backwards (periods 0, -1, ...) so the intro can rehearse.
#
# `pb` is an ARGUMENT (Phase E section 1): it comes from the knobs of
# the lap the asking hazard / plate belongs to (Rules.period_beats(k)).
# It used to be one global, which cannot work once two laps with
# different rates exist at the same time.
# ------------------------------------------------------------
func period_s(pb: int) -> float:
	return beat_interval * pb


func _anchor() -> float:
	if not downbeats.is_empty():
		return downbeats[0]
	return beats[0] if not beats.is_empty() else 0.0


func period_index_at(t: float, pb: int) -> int:
	var i := beat_at(t)
	if i < first_bar_beat or downbeats.is_empty():
		return int(floor((t - _anchor()) / period_s(pb))) + 1
	return (i - first_bar_beat) / pb + 1


func period_start(idx: int, pb: int) -> float:
	var b := first_bar_beat + (idx - 1) * pb
	if idx >= 1 and endless:
		return beat_time(b)
	if idx >= 1 and b < beats.size():
		return beats[b]
	return _anchor() + (idx - 1) * period_s(pb)


func period_end(idx: int, pb: int) -> float:
	return period_start(idx + 1, pb)


func period_progress_at(t: float, pb: int) -> float:
	var idx := period_index_at(t, pb)
	var s := period_start(idx, pb)
	var e := period_end(idx, pb)
	return clampf((t - s) / maxf(e - s, 0.001), 0.0, 1.0)


# Continuous period count, e.g. 12.37 = 37 % through period 12.
func period_float_at(t: float, pb: int) -> float:
	return float(period_index_at(t, pb)) + period_progress_at(t, pb)


# Continuous count in units of `beats_per` beats (4 = bars) from the
# first downbeat, extrapolated backwards through the intro. Hazards whose
# speed is fixed in bars (the orbiter) and the slowest a wall or a shot
# may move read this instead of the level's period.
func beats_float_at(t: float, beats_per: int) -> float:
	var i := beat_at(t)
	if i < first_bar_beat or downbeats.is_empty():
		return (t - _anchor()) / (beat_interval * beats_per) + 1.0
	var b := i - first_bar_beat
	return float(b / beats_per) + 1.0 + float(b % beats_per) / beats_per + beat_phase_at(t) / beats_per


# ------------------------------------------------------------
# Space <-> time
# ------------------------------------------------------------
func z_at(t: float) -> float:
	return (t - z_origin_t) * track_speed


func t_at(z: float) -> float:
	return z / track_speed + z_origin_t


# 0..1: how far through the run (from the start offset to the end of the
# track) time t is. The progress bar, the best marker and the distance
# score all read this.
func progress_of(t: float) -> float:
	var span := maxf(duration - start_offset, 0.001)
	return clampf((t - start_offset) / span, 0.0, 1.0)


# ------------------------------------------------------------
# Signals, driven from _process by comparing indices frame to frame.
# Never from a Timer: timers drift from the audio clock.
# ------------------------------------------------------------
func _resync_indices() -> void:
	_prev_lap = current_lap()
	_prev_beat = current_beat()
	_prev_bar = current_bar()
	_prev_section = section_of_bar(_prev_bar) if _prev_bar > 0 else 0


func _process(delta: float) -> void:
	if not _running or _paused:
		return
	var before := _smooth_t
	_advance(delta)
	if endless:
		_watch_seam(_smooth_t - before, delta)
	var b := current_beat()
	if b != _prev_beat:
		if b > _prev_beat:
			beat.emit(b)
		_prev_beat = b
	var bar := current_bar()
	if bar != _prev_bar:
		if bar > _prev_bar:
			downbeat.emit(bar)
		_prev_bar = bar
		var sec := section_of_bar(bar) if bar > 0 else 0
		if sec != _prev_section:
			_prev_section = sec
			section_changed.emit(sec)


# Around every lap seam (a second either side): run time's per-frame step
# must never be negative and never more than two frames' worth. One line
# per seam, printed when the zone is left.
func _watch_seam(step: float, delta: float) -> void:
	var into := fposmod(_smooth_t - loop_start_t, loop_len)
	var near := _smooth_t > loop_end_t - 1.0 and (into < 1.0 or into > loop_len - 1.0)
	if near:
		_seam_frames += 1
		_seam_min = minf(_seam_min, step)
		_seam_max = maxf(_seam_max, step)
		_seam_ratio = maxf(_seam_ratio, step / maxf(delta, 0.0001))
		if step < 0.0:
			_seam_negative += 1
	elif _seam_frames > 0:
		print("SEAM into lap %d: %d frames, run_time step min %.2f ms max %.2f ms (at most %.2f frames' worth), negative steps %d, audio drift %+.1f ms" % [
			current_lap(), _seam_frames, _seam_min * 1000.0, _seam_max * 1000.0, _seam_ratio, _seam_negative, audio_drift_ms()])
		_seam_frames = 0
		_seam_min = INF
		_seam_max = -INF
		_seam_ratio = 0.0
		_seam_negative = 0
	var lap := current_lap()
	if lap != _prev_lap:
		_prev_lap = lap
		lap_changed.emit(lap)
