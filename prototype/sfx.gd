extends Node
# ============================================================
# SOUND EFFECTS (2026-10-22, roadmap step 4) — autoload `Sfx`.
# Sfx.play("jump") from anywhere. The sounds are synthesised by
# tools/make_sfx.py (one WAV per sound in assets/audio/sfx/); this file
# plays them and owns how loud each one sits against the song.
#
# Two players per sound, used in turn, so a sound can overlap itself
# (a quick double jump, a run of dots) without cutting its own tail, and
# each voice keeps its own pitch. A slight random pitch on the sounds that
# repeat a lot, so the hundredth jump is not the same as the first.
#
# The dot pickup climbs a scale with the streak (pickup(streak)): a run
# of dots plays a little melody in the song's notes, back to the root
# when the streak breaks. The scale is the song's strongest notes, the
# same ones the WAVs are tuned to (make_sfx.py).
#
# On the Master bus, so Settings' SOUND OFF (Progress.sound_on mutes the
# Master bus) silences these with the music.
# ============================================================

const DIR := "res://assets/audio/sfx/"
# Level in the mix (make_sfx.py normalises every file to -3 dBFS and its
# preview reads these numbers: keep the `"name": dB,  # dB` form).
const VOLUME := {
	"jump": -11.0,  # dB  every jump: present, never in front of the song
	"land": -13.0,  # dB  every landing: felt more than heard
	"pickup": -9.0,  # dB  the dots: the melody on top
	"near_miss": -8.0,  # dB  a reward, so it may stand out
	"shield_on": -6.0,  # dB  once in a while, an event
	"shield_pop": -4.0,  # dB  saved your run: the loudest good thing
	"death": -5.0,  # dB
	"tap": -14.0,  # dB  buttons
}
const PITCH_JITTER := {"jump": 0.04, "land": 0.06, "tap": 0.03, "near_miss": 0.05}
# Semitones above the root, climbed one step per dot of the streak.
const PICKUP_SCALE := [0, 2, 4, 6, 11, 12, 14, 16, 18, 23, 24]
const VOICES := 2

var _players := {}            # name -> [AudioStreamPlayer, ...]
var _turn := {}               # name -> the voice to use next


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for name in VOLUME:
		var stream: AudioStream = load(DIR + name + ".wav")
		var voices := []
		for i in VOICES:
			var p := AudioStreamPlayer.new()
			p.stream = stream
			p.volume_db = float(VOLUME[name])
			add_child(p)
			voices.append(p)
		_players[name] = voices
		_turn[name] = 0


func play(name: String, pitch: float = 1.0) -> void:
	var voices: Array = _players.get(name, [])
	if voices.is_empty():
		return
	var i: int = _turn[name]
	_turn[name] = (i + 1) % voices.size()
	var p: AudioStreamPlayer = voices[i]
	var jitter: float = PITCH_JITTER.get(name, 0.0)
	p.pitch_scale = pitch * (1.0 + randf_range(-jitter, jitter))
	p.play()


# A dot taken with `streak` dots in a row (1 = the first).
func pickup(streak: int) -> void:
	var step: int = PICKUP_SCALE[clampi(streak - 1, 0, PICKUP_SCALE.size() - 1)]
	play("pickup", pow(2.0, step / 12.0))
