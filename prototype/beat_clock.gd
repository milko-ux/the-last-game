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
# ============================================================

signal beat(index: int)
signal downbeat(bar: int)
signal section_changed(section_id: int)

const BEATMAP_PATH := "res://assets/audio/fuffens_beatmap.json"

# Hazards run this much BEHIND the audio clock so the visual hit lands
# with the transient you actually hear (audio output tends to be later
# than the engine believes). Positive = hazards later, negative = earlier.
# The single knob Milko tunes if things feel late: try 0.030 -> 0.060.
const SYNC_OFFSET_S := 0.030

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

var _player: AudioStreamPlayer
var _time_begin := 0
var _time_delay := 0.0
var _base_t := 0.0
var _running := false
var _paused := false
var _paused_t := 0.0
var _prev_beat := -1
var _prev_bar := 0
var _prev_section := 0


func _ready() -> void:
	set_process(false)
	_load()


func _load() -> void:
	var f := FileAccess.open(BEATMAP_PATH, FileAccess.READ)
	if f == null:
		push_error("BeatClock: cannot open %s" % BEATMAP_PATH)
		return
	var data = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("BeatClock: %s is not valid JSON" % BEATMAP_PATH)
		return
	bpm = float(data.get("bpm", 120.0))
	beat_interval = float(data.get("beat_interval_s", 60.0 / bpm))
	duration = float(data.get("duration_s", 0.0))
	beats = PackedFloat64Array(data.get("beats_s", []))
	downbeats = PackedFloat64Array(data.get("downbeats_s", []))
	bars = data.get("bars", [])
	sections = data.get("sections", [])
	if bars.size() >= 2:
		mean_bar_s = (float(bars[-1]["t"]) - float(bars[0]["t"])) / float(bars.size() - 1)
	else:
		mean_bar_s = beat_interval * 4.0
	track_speed = BAR_UNITS / (4.0 * beat_interval)
	if not downbeats.is_empty():
		first_bar_beat = maxi(0, beat_at(downbeats[0]))
	loaded = true


# ------------------------------------------------------------
# Transport
# ------------------------------------------------------------
func start(stream_player: AudioStreamPlayer) -> void:
	_player = stream_player
	_base_t = start_offset
	_paused = false
	_time_begin = Time.get_ticks_usec()
	_time_delay = AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
	_player.play(start_offset)
	_running = true
	_resync_indices()
	set_process(true)


# Checkpoint rewind: the song jumps to t and song_time() returns t.
func seek(t: float) -> void:
	if _player == null:
		return
	_base_t = t
	_paused = false
	_time_begin = Time.get_ticks_usec()
	_time_delay = AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
	if _player.playing and not _player.stream_paused:
		_player.seek(t)
	else:
		_player.stream_paused = false
		_player.play(t)
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
	var t := (Time.get_ticks_usec() - _time_begin) / 1_000_000.0
	return _base_t + max(0.0, t - _time_delay)


# The clock hazards read. Same clock, shifted by the sync offset.
func hazard_time() -> float:
	return song_time() - SYNC_OFFSET_S


# Index into beats of the last beat at or before t. -1 during the intro.
func beat_at(t: float) -> int:
	return beats.bsearch(t, false) - 1


func current_beat() -> int:
	return beat_at(song_time())


# 1-based bar number of the last downbeat at or before t. 0 during the intro.
func bar_at(t: float) -> int:
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
	return float(bars[bar - 1]["t"])


func bar_end(bar: int) -> float:
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
	var s := bar_start(bar)
	var e := bar_end(bar)
	var out := PackedFloat64Array()
	for b in beats:
		if b >= s - 0.02 and b < e - 0.02:
			out.append(b)
	if out.size() != 4:
		out.clear()
		for k in 4:
			out.append(s + (e - s) * k / 4.0)
	return out


func bar_energy(bar: int) -> float:
	return float(bars[bar - 1].get("energy", 0.0))


func bar_band(bar: int, band: String) -> float:
	return float(bars[bar - 1].get(band, 0.0))


func section_of_bar(bar: int) -> int:
	for s in sections:
		if bar >= int(s["start_bar"]) and bar <= int(s["end_bar"]):
			return int(s["id"])
	return 0


func is_section_start(bar: int) -> bool:
	for s in sections:
		if int(s["start_bar"]) == bar:
			return true
	return false


# ------------------------------------------------------------
# Hazard periods (addendum 3). Hazards act once per PERIOD, which is
# period_beats beats long: 4 ("bar", level 1), 2 ("half_bar") or 1
# ("beat"). Period 1 starts on bar 1's downbeat; before that the grid
# is extrapolated backwards (periods 0, -1, ...) so the intro can
# rehearse. The scene sets period_beats from the level's knobs.
# ------------------------------------------------------------
var period_beats := 4


func period_s() -> float:
	return beat_interval * period_beats


func _anchor() -> float:
	if not downbeats.is_empty():
		return downbeats[0]
	return beats[0] if not beats.is_empty() else 0.0


func period_index_at(t: float) -> int:
	var i := beat_at(t)
	if i < first_bar_beat or downbeats.is_empty():
		return int(floor((t - _anchor()) / period_s())) + 1
	return (i - first_bar_beat) / period_beats + 1


func period_start(idx: int) -> float:
	var b := first_bar_beat + (idx - 1) * period_beats
	if idx >= 1 and b < beats.size():
		return beats[b]
	return _anchor() + (idx - 1) * period_s()


func period_end(idx: int) -> float:
	return period_start(idx + 1)


func period_progress_at(t: float) -> float:
	var idx := period_index_at(t)
	var s := period_start(idx)
	var e := period_end(idx)
	return clampf((t - s) / maxf(e - s, 0.001), 0.0, 1.0)


# Continuous period count, e.g. 12.37 = 37 % through period 12.
func period_float_at(t: float) -> float:
	return float(period_index_at(t)) + period_progress_at(t)


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
	return (t - start_offset) * track_speed


func t_at(z: float) -> float:
	return z / track_speed + start_offset


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
	_prev_beat = current_beat()
	_prev_bar = current_bar()
	_prev_section = section_of_bar(_prev_bar) if _prev_bar > 0 else 0


func _process(_delta: float) -> void:
	if not _running or _paused:
		return
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
