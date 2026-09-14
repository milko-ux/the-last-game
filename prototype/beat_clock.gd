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

# One bar of music is this many world units of track. Everything spatial
# (lane spacing, hazard depth, camera distance) was chosen around it.
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
var track_speed := 4.0      # world units per second, = BAR_UNITS / mean_bar_s

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
	track_speed = BAR_UNITS / mean_bar_s
	loaded = true


# ------------------------------------------------------------
# Transport
# ------------------------------------------------------------
func start(stream_player: AudioStreamPlayer) -> void:
	_player = stream_player
	_base_t = 0.0
	_paused = false
	_time_begin = Time.get_ticks_usec()
	_time_delay = AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
	_player.play()
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
		return 0.0
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
	var t := song_time()
	var i := beat_at(t)
	if beats.is_empty():
		return 0.0
	if i < 0:
		return fposmod((t - beats[0]) / beat_interval, 1.0)
	if i >= beats.size() - 1:
		return clampf((t - beats[i]) / beat_interval, 0.0, 1.0)
	return clampf((t - beats[i]) / (beats[i + 1] - beats[i]), 0.0, 1.0)


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
# Space <-> time
# ------------------------------------------------------------
func z_at(t: float) -> float:
	return t * track_speed


func t_at(z: float) -> float:
	return z / track_speed


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
