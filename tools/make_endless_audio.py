#!/usr/bin/env python3
"""Cut the looping track for the endless run (Phase E brief 1, section 2).

    python3 tools/make_endless_audio.py            # loop end = bar 73's downbeat
    python3 tools/make_endless_audio.py 65         # ...or another bar (keep it on an 8-bar boundary + 1)

Writes assets/audio/fuffens_endless.ogg = the existing track from 0 s to the
downbeat of the loop-end bar (read from the beatmap, so it always matches
BeatClock.LOOP_END_BAR — change both together). The game plays it with
loop on and loop offset = bar 1's downbeat (set at runtime in
track_test.gd from BeatClock's constants, and in the .import file).
OGG, not MP3: MP3 padding leaves a gap at the seam.

Needs ffmpeg. This Mac's ffmpeg (8.1.2, Homebrew) has no libvorbis, so the
script falls back to ffmpeg's built-in Vorbis encoder (-strict -2). Measured
against the source on 2026-09-20: sample-aligned, SNR 33.9 dB, spectrum
intact to 16 kHz (-1.6 dB above), 22 samples (0.5 ms) of end padding. If
Milko hears it, export the same cut from the DAW instead.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIO = os.path.join(HERE, "..", "assets", "audio")
SRC = os.path.join(AUDIO, "fuffens_instrumental_vers.mp3")
DST = os.path.join(AUDIO, "fuffens_endless.ogg")
BEATMAP = os.path.join(AUDIO, "fuffens_beatmap.json")


def main() -> None:
    end_bar = int(sys.argv[1]) if len(sys.argv) > 1 else 73
    bars = json.load(open(BEATMAP))["bars"]
    loop_start = float(bars[0]["t"])
    loop_end = float(bars[end_bar - 1]["t"])
    encoders = subprocess.run(["ffmpeg", "-hide_banner", "-encoders"], capture_output=True, text=True).stdout
    codec = ["-c:a", "libvorbis"] if "libvorbis" in encoders else ["-c:a", "vorbis", "-strict", "-2"]
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", SRC, "-t", "%.6f" % loop_end,
                    *codec, "-ac", "2", "-q:a", "7", DST], check=True)
    print("%s: 0 -> %.3f s (bar %d), loop offset %.3f s (bar 1), %d KB, encoder %s" % (
        os.path.basename(DST), loop_end, end_bar, loop_start, os.path.getsize(DST) // 1024, codec[1]))


if __name__ == "__main__":
    main()
