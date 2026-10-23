#!/usr/bin/env python3
# ============================================================
# MAKE SFX (2026-10-22, roadmap step 4) — every sound effect in the game,
# synthesised here from sines, noise and envelopes. Milko's call: "I make
# them in code" (Code), so there is no sample library and no recording:
# this file IS the sound design, and re-running it rebuilds every WAV.
#
#   python3 tools/make_sfx.py                 # writes assets/audio/sfx/*.wav
#   python3 tools/make_sfx.py preview=PATH    # also a mix over the song, to listen to
#
# One file per sound (assets/audio/sfx/<name>.wav, mono, 44.1 kHz, 16 bit);
# prototype/sfx.gd plays them and owns their volumes. The dot pickup is
# ONE note: the game climbs a scale with the streak by pitch (sfx.gd).
#
# Tuned to the song: fuffens' strongest notes are Bb C D E A (a chroma
# count over fuffens_endless.wav, 2026-10-22; Bb major / lydian, not
# certain). The pitched sounds use only those notes. If the key is
# corrected, ROOT_HZ is the one line to change.
#
# The world is clay, stone and cloud: everything soft, rounded and short,
# nothing chiptune or harsh. A little synthetic room (ROOM_MIX) on each
# so they sit in the same space.
# ============================================================
import sys
import os
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, sosfilt

SR = 44100
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio", "sfx")
ROOT_HZ = 466.16          # Bb4
PEAK = 10 ** (-3 / 20)    # every file normalised to -3 dBFS; sfx.gd sets the level in the mix
ROOM_MIX = 0.12
rng = np.random.default_rng(20261022)   # fixed: the same files every run


def note(semitones_from_root: float, octave: int = 0) -> float:
	return ROOT_HZ * 2 ** (semitones_from_root / 12 + octave)


def t_of(dur: float) -> np.ndarray:
	return np.arange(int(dur * SR)) / SR


def env(t: np.ndarray, attack: float, decay: float) -> np.ndarray:
	# A short linear attack, then an exponential decay (decay = time constant).
	a = np.clip(t / max(attack, 1e-4), 0, 1)
	return a * np.exp(-np.maximum(t - attack, 0) / decay)


def glide(t: np.ndarray, f0: float, f1: float, dur: float) -> np.ndarray:
	# The phase of an exponential pitch glide from f0 to f1 over dur.
	k = np.log(f1 / f0) / dur
	tt = np.minimum(t, dur)
	ph = f0 * (np.exp(k * tt) - 1) / k + f1 * np.maximum(t - dur, 0)
	return 2 * np.pi * ph


def noise(n: int) -> np.ndarray:
	return rng.standard_normal(n)


def band(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
	return sosfilt(butter(2, [lo, hi], btype="band", fs=SR, output="sos"), x)


def low(x: np.ndarray, hz: float) -> np.ndarray:
	return sosfilt(butter(2, hz, btype="low", fs=SR, output="sos"), x)


def high(x: np.ndarray, hz: float) -> np.ndarray:
	return sosfilt(butter(2, hz, btype="high", fs=SR, output="sos"), x)


def swept_band(x: np.ndarray, centres: np.ndarray, q: float = 1.6, block: int = 256) -> np.ndarray:
	# Noise through a band-pass whose centre moves: block by block.
	out = np.zeros_like(x)
	for i in range(0, len(x), block):
		c = float(centres[min(i, len(centres) - 1)])
		lo, hi = c / (1 + 1 / q), c * (1 + 1 / q)
		out[i:i + block] = band(x[max(0, i - 512):i + block], lo, hi)[-len(x[i:i + block]):]
	return out


def mallet(f: float, dur: float, decay: float = 0.09) -> np.ndarray:
	# A soft marimba-ish note: the fundamental, a quick 4x partial for the
	# strike, a whisper of the octave.
	t = t_of(dur)
	return (np.sin(2 * np.pi * f * t) * env(t, 0.002, decay)
		+ 0.35 * np.sin(2 * np.pi * f * 3.93 * t) * env(t, 0.001, decay * 0.18)
		+ 0.1 * np.sin(2 * np.pi * f * 2 * t) * env(t, 0.002, decay * 0.5))


def room(x: np.ndarray, length: float = 0.25) -> np.ndarray:
	# A tiny synthetic room: the dry sound plus a decaying-noise reverb.
	n = int(length * SR)
	ir = noise(n) * np.exp(-np.arange(n) / (n / 5))
	ir = low(ir, 5000)
	ir /= np.sqrt(np.sum(ir ** 2))
	wet = np.convolve(x, ir)              # len(x) + n - 1
	dry = np.concatenate([x, np.zeros(n - 1)])
	return dry + ROOM_MIX * wet


def finish(x: np.ndarray, dry: bool = False) -> np.ndarray:
	if not dry:
		x = room(x)
	# A 3 ms fade at both ends, so no file starts or stops with a click.
	f = int(0.003 * SR)
	x[:f] *= np.linspace(0, 1, f)
	x[-f:] *= np.linspace(1, 0, f)
	# Trim the silent tail.
	keep = np.nonzero(np.abs(x) > np.abs(x).max() * 0.002)[0]
	x = x[:keep[-1] + 1] if len(keep) else x
	return x / np.abs(x).max() * PEAK


# ------------------------------------------------------------
# The sounds
# ------------------------------------------------------------
def jump() -> np.ndarray:
	# A soft upward "fwup": a rounded tone gliding Bb3 -> F4, and air.
	dur = 0.22
	t = t_of(dur)
	ph = glide(t, note(0, -1), note(7, -1), 0.12)
	tone = (np.sin(ph) + 0.25 * np.sin(2 * ph)) * env(t, 0.006, 0.06)
	air = swept_band(noise(len(t)), np.geomspace(700, 2600, len(t))) * env(t, 0.01, 0.05)
	return tone + 0.5 * air


def land() -> np.ndarray:
	# A soft clay thump: a sine dropping, and a puff of dust. Pitched where
	# a phone speaker still plays it (330 -> 165 Hz: the iPhone's speaker
	# gives little below ~200 Hz, and at 120 -> 58 Hz most of the sound was
	# under it), with a little sub under it for headphones.
	dur = 0.16
	t = t_of(dur)
	thud = np.sin(glide(t, 330, 165, 0.06)) * env(t, 0.002, 0.035)
	sub = np.sin(glide(t, 110, 60, 0.08)) * env(t, 0.002, 0.04)
	puff = low(noise(len(t)), 1500) * env(t, 0.001, 0.02)
	return thud + 0.25 * sub + 0.6 * puff


def pickup() -> np.ndarray:
	# One mallet note on Bb5. sfx.gd raises its pitch up the scale as the
	# streak grows, so a run of dots plays a melody.
	return mallet(note(0, 1), 0.4, 0.1)


def near_miss() -> np.ndarray:
	# Something brushed past: a breathy whoosh that rises and falls, panned
	# nowhere (mono), with a faint high glint at its peak.
	dur = 0.34
	t = t_of(dur)
	shape = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2
	centres = 900 * 3.2 ** np.sin(np.pi * np.clip(t / dur, 0, 1))
	whoosh = swept_band(noise(len(t)), centres, q=2.2) * shape
	glint = np.sin(2 * np.pi * note(11, 1) * t) * env(np.maximum(t - dur * 0.45, 0), 0.004, 0.05) * (t > dur * 0.45)
	return whoosh + 0.12 * glint


def shield_on() -> np.ndarray:
	# The shield is charged: a quick upward arpeggio on Bb D A Bb and a
	# soft shimmering swell under it.
	dur = 0.75
	t = t_of(dur)
	x = np.zeros(len(t))
	for i, (semi, octv) in enumerate([(0, 1), (4, 1), (11, 1), (0, 2)]):
		start = int(i * 0.055 * SR)
		m = mallet(note(semi, octv), dur, 0.14) * (0.85 ** i)
		x[start:] += m[:len(x) - start]
	pad_env = np.clip(t / 0.25, 0, 1) * np.exp(-np.maximum(t - 0.25, 0) / 0.18)
	pad = sum(np.sin(2 * np.pi * note(0, 0) * d * t) for d in (1.0, 1.004, 2.0, 2.997)) * pad_env
	return x + 0.12 * pad


def shield_pop() -> np.ndarray:
	# The shield takes a hit: a bubble pop (a fast upward chirp), a click,
	# and glassy bits falling away.
	dur = 0.45
	t = t_of(dur)
	bubble = np.sin(glide(t, 380, 1500, 0.025)) * env(t, 0.001, 0.03)
	click = high(noise(len(t)), 2500) * env(t, 0.0005, 0.004)
	glass = np.zeros(len(t))
	for i, (semi, octv) in enumerate([(11, 2), (4, 2), (0, 2), (6, 1)]):
		start = int((0.02 + i * 0.045) * SR)
		g = np.sin(2 * np.pi * note(semi, octv) * t) * env(t, 0.001, 0.05)
		glass[start:] += g[:len(t) - start] * (0.8 ** i)
	return bubble + 0.4 * click + 0.35 * glass


def death() -> np.ndarray:
	# A soft clay squelch and a sad little fall: noise squashed low, then a
	# tone gliding D5 -> Bb3 with a wobble. Never harsh: it plays a lot.
	dur = 0.8
	t = t_of(dur)
	squelch = low(noise(len(t)), 700) * env(t, 0.002, 0.05)
	thump = np.sin(glide(t, 140, 55, 0.12)) * env(t, 0.002, 0.08)
	wobble = 1 + 0.03 * np.sin(2 * np.pi * 7 * t)
	ph = np.cumsum(2 * np.pi * np.geomspace(note(4), note(0, -1), len(t)) * wobble) / SR
	fall = (np.sin(ph) + 0.2 * np.sin(2 * ph)) * env(t, 0.03, 0.22)
	return 0.7 * squelch + 0.8 * thump + 0.6 * fall


def tap() -> np.ndarray:
	# A button: a dry, crisp click, like a phone keyboard's. Round 1 was a
	# pitched wooden tick (D6) with the room on it -- Milko: "the menu
	# buttons get a bit annoying" -- a note on every tap is a melody
	# nobody asked for. Now no pitch to hear and no tail: a snap of
	# bright noise and a tiny knock under it, 25 ms, played dry.
	dur = 0.025
	t = t_of(dur)
	snap = band(noise(len(t)), 2500, 7000) * env(t, 0.0002, 0.0015)
	knock = band(noise(len(t)), 500, 1400) * env(t, 0.0004, 0.004)
	return snap + 0.6 * knock


def best() -> np.ndarray:
	# NEW BEST (the end screen, 2026-10-23): a bright run up the song's
	# notes -- Bb C D E A Bb -- with a shimmer under it, the one fanfare.
	dur = 1.1
	t = t_of(dur)
	x = np.zeros(len(t))
	for i, (semi, octv) in enumerate([(0, 1), (2, 1), (4, 1), (6, 1), (11, 1), (0, 2)]):
		start = int(i * 0.065 * SR)
		m = mallet(note(semi, octv), dur, 0.16 if i < 5 else 0.3)
		x[start:] += m[:len(x) - start] * (0.8 + 0.04 * i)
	pad_env = np.clip(t / 0.35, 0, 1) * np.exp(-np.maximum(t - 0.35, 0) / 0.3)
	pad = sum(np.sin(2 * np.pi * note(0, 1) * d * t) for d in (1.0, 1.003, 1.5, 2.0)) * pad_env
	return x + 0.1 * pad


DRY = {"tap"}          # no room on these
SOUNDS = {"jump": jump, "land": land, "pickup": pickup, "near_miss": near_miss,
	"shield_on": shield_on, "shield_pop": shield_pop, "death": death, "tap": tap, "best": best}


def write_all() -> dict:
	os.makedirs(OUT, exist_ok=True)
	made = {}
	for name, fn in SOUNDS.items():
		x = finish(fn().astype(np.float64), dry=name in DRY)
		wavfile.write(os.path.join(OUT, name + ".wav"), SR, (x * 32767).astype(np.int16))
		made[name] = x
		print("%-11s %.2f s" % (name, len(x) / SR))
	return made


# A listening mix: 16 s of the song with each sound placed over it at the
# level sfx.gd gives it, so the balance can be judged by ear on the Mac.
def preview(path: str, made: dict) -> None:
	import re
	src = open(os.path.join(os.path.dirname(OUT), "..", "..", "prototype", "sfx.gd")).read()
	vol = {k: float(v) for k, v in re.findall(r'"(\w+)":\s*(-?[\d.]+),\s*#\s*dB', src)}
	sr, song = wavfile.read(os.path.join(os.path.dirname(OUT), "fuffens_endless.wav"))
	song = song.astype(np.float64).mean(axis=1) / 32768.0
	start = int(40 * SR)
	mix = song[start:start + 16 * SR].copy()
	beat = 0.5108
	plan = [("tap", 0.5), ("jump", 2 * beat * 2), ("land", 2 * beat * 2 + 0.55)]
	for i in range(6):
		plan.append(("pickup", 4.0 + i * beat / 2))
	plan += [("near_miss", 7.5), ("shield_on", 9.0), ("jump", 10.2), ("land", 10.75),
		("shield_pop", 12.0), ("death", 14.0)]
	scale = [0, 2, 4, 6, 11, 12, 14, 16]
	n_pick = 0
	for name, at in plan:
		x = made[name]
		if name == "pickup":
			# The streak's pitch climb, as sfx.gd does it (resampled here).
			r = 2 ** (scale[min(n_pick, len(scale) - 1)] / 12)
			n_pick += 1
			x = np.interp(np.arange(0, len(x), r), np.arange(len(x)), x)
		g = 10 ** (vol.get(name, -6.0) / 20)
		i = int(at * SR)
		mix[i:i + len(x)] += g * x[:len(mix) - i]
	mix /= max(1.0, np.abs(mix).max() / 0.98)
	wavfile.write(path, SR, (mix * 32767).astype(np.int16))
	print("preview", path)


if __name__ == "__main__":
	made = write_all()
	for a in sys.argv[1:]:
		if a.startswith("preview="):
			preview(a.split("=", 1)[1], made)
