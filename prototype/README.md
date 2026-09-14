# Phase R prototype — "an album you survive"

Run it (from the repo root):

```
/Users/benim/Downloads/Godot.app/Contents/MacOS/Godot --path . prototype/track_test.tscn
```

Web build for the phone:

```
tools/package_web.sh "Web (Phase R)"     # exports to build/phase-r/ and zips it
tools/serve.py tls build/phase-r         # https://<LAN-IP>:8443, accept the cert once
```

## What this is

A gray-box test of one idea: **each level is a song**. The player runs
forward at a speed locked to the track, hazards act on the beat, the
camera sits behind and above. No art, flat colours only.

- **Position is time.** `z = song_time * track_speed`. One bar of music is
  8 units of track, one beat is 2 units.
- **Death rewinds the song** to the last checkpoint. Player and hazards
  re-derive themselves from the new time; nothing has its own timeline.
- **The 16-second intro is the run-up.** Track visible, no hazards, move and
  jump freely. Hazards start on the first downbeat (16.6 s).
- Colour meaning is unchanged: magenta = will kill you, cyan = safe, amber = goal.

## Files

| File | Role |
|---|---|
| `beat_clock.gd` | autoload `BeatClock`. Loads the beatmap, owns song time, beat/bar/section signals, `SYNC_OFFSET_S`. Inert in the 2D game. |
| `placement.gd` | deterministic hazard placement from per-bar energy and dominant band |
| `track_builder.gd` | builds segments, hazards, checkpoint strips and the goal gate |
| `hazard3d.gd` + `hazard_slammer/pulser/sweeper.gd` | hazards; each is a pure function of song time |
| `player3d.gd/.tscn` | white capsule; left/right + jump, z from the clock |
| `camera_rig.gd` | behind/above camera, x-lag only, FOV punch on downbeats |
| `track_test.gd/.tscn` | the run scene: lives, deaths, checkpoints, death/goal |
| `flat_mats.gd` | the handful of unlit materials |

## Tuning knobs

- `BeatClock.SYNC_OFFSET_S` (beat_clock.gd) — if hazards feel late, raise it
  (0.030 → 0.060). Positive delays the hazards relative to the audio.
- Density thresholds and type rules: `placement.gd`.
- Jump: `player3d.gd` reuses the 2D numbers; `WORLD_PER_PX` sets the apex height.

## Input to the level

`assets/audio/fuffens_beatmap.json` + `assets/audio/fuffens_instrumental_vers.mp3`.
Hazard placement is generated from the JSON, never hand-authored. Swap in a
different song's beatmap and you get a different level with no code changes.
