#!/usr/bin/env python3
"""Cut the looping track for the endless run (Phase E brief 1, section 2).

    python3 tools/make_endless_audio.py            # loop end = bar 73's downbeat
    python3 tools/make_endless_audio.py 65         # ...or another bar (keep it on an 8-bar boundary + 1)

Writes assets/audio/fuffens_endless.wav = the existing track from 0 s to the
downbeat of the loop-end bar (read from the beatmap, so it always matches
BeatClock.LOOP_END_BAR — change both together). The game plays it with
loop on and loop offset = bar 1's downbeat (set at runtime in
track_test.gd from BeatClock's constants, and in the .import file).
WAV (QOA-compressed by Godot's importer), not MP3: MP3 padding leaves a
gap at the seam; not OGG: see the note at the ffmpeg call.

Needs ffmpeg (this Mac's is Homebrew 8.1.2). The cut is a PCM WAV: nothing
is encoded here; Godot's importer compresses it to QOA
(fuffens_endless.wav.import) and bakes the loop points in.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
AUDIO = os.path.join(HERE, "..", "assets", "audio")
SRC = os.path.join(AUDIO, "fuffens_instrumental_vers.mp3")
DST = os.path.join(AUDIO, "fuffens_endless.wav")
BEATMAP = os.path.join(AUDIO, "fuffens_beatmap.json")


def main() -> None:
    end_bar = int(sys.argv[1]) if len(sys.argv) > 1 else 73
    bars = json.load(open(BEATMAP))["bars"]
    loop_start = float(bars[0]["t"])
    loop_end = float(bars[end_bar - 1]["t"])
    # -page_duration: 100 ms Ogg pages (ffmpeg's default is 1 s). A seek
    # decodes from the start of the page its target sits in, and with 1 s
    # pages the rewind's seek cost 53-86 ms on the Mac in Chrome and 75 on
    # the phone -- the death spike (2026-09-24). Same encoder, same
    # settings; only the container's paging changes.
    # WAV, not OGG (2026-09-24): Godot imports it with QOA compression
    # (fuffens_endless.wav.import, compress/mode=2), which seeks in constant
    # time and decodes cheaper than Vorbis every frame. The Vorbis playback's
    # setup was the death spike: a rewind's play(pos) cost 53-86 ms in
    # Chrome on the Mac and 75 on the phone, and 100 ms Ogg pages changed
    # nothing (63 ms). The cut is sample-exact, so the loop seam is too.
    subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", SRC, "-t", "%.6f" % loop_end,
                    "-c:a", "pcm_s16le", "-ac", "2", "-ar", "44100", DST], check=True)
    print("%s: 0 -> %.3f s (bar %d), loop offset %.3f s (bar 1, sample %d), %d KB PCM (Godot compresses it to QOA on import)" % (
        os.path.basename(DST), loop_end, end_bar, loop_start, int(round(loop_start * 44100)), os.path.getsize(DST) // 1024))


if __name__ == "__main__":
    main()
