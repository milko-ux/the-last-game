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

A gray-box test of one idea: **each level is a song**. No art, flat colours.
Shape of play per `PHASE_R_ADDENDUM_1.md`, first two minutes per
`PHASE_R_ADDENDUM_2.md` (camera target: `docs/concept/field_monolith.png.png`,
the double extension is how the file arrived):

- **The song drives the world, not the player.** A *window* (the strip of
  field on screen, 2.5 bars deep) scrolls forward at song speed. The player
  runs freely inside it in x and z, faster than the scroll, plus jump.
  The window's back edge is drawn as a thin cyan **death line** across the
  field (`Rules.death_line`); cross behind it and the beat caught you.
- **Field is 18 wide (nine tiles).** Camera high and back from the window
  centre, `(0, 17, -10)`, FOV 50, so the whole width and two-plus bars are
  in frame on a phone in landscape.
- **Position of the window is time.** `z_back = song_time * scroll_speed`.
  One bar of music is 8 units of field, one beat is one tile-row.
- **Death rewinds the song** to the last checkpoint. Window, plates and
  hazards re-derive themselves from the new time; nothing has a timeline.
- **The 16-second intro is the run-up.** Field visible, hazards inert, move
  and jump freely. Everything arms on the first downbeat (16.6 s).
- **Colour meaning is unchanged:** magenta = will kill you, cyan = safe,
  amber = goal / checkpoint / notes.

## Level 1 is a curriculum (addendum 2)

`placement.gd` takes a curriculum (`Placement.LEVEL1`): per bar range,
which hazard types may be live, which patterns, a density cap, and a
**demo bar**. Nothing can kill you before it has shown itself:

| Bars | Role |
|---|---|
| intro (0-16.6 s) | rehearsal: every plate plays its pattern in warning colour on the extrapolated beat grid, nothing lethal |
| 1-8 | plates only (`row`, `checker`); bar 1 = plate demo, bar 2 plates live |
| 9-16 | open floor, checkpoint at 9 |
| 17-24 | + sweepers; bar 17 = sweeper demo (`WALL`), bar 18 sweeper only |
| 25-31 | open floor, checkpoint at 25 |
| 32-40 | + gates; bar 32 = gate demo (`GATE`), bar 33 gate only |
| 41-48 | open floor, checkpoint at 41 |
| 49-56 | + orbiters; bar 49 = orbiter demo (`ORBIT`), at least two orbiter bars |
| 57-78 | any type, density capped at Pressure, no `spiral` |

A demo hazard runs its full behaviour in the warning colour and never
kills; the creature's eye locks onto it and one glass word shows above the
field for that bar. No slammers or pits on level 1. The generator
push_errors if any type is live before its demo bar.

**Level 1 has no lives** (`Rules.LEVEL`, `Rules.lives_enabled()`): death =
0.25 s freeze, rewind to checkpoint, continue; no death screen, no life
counter. Lives and the share screen start at level 2 (not built).

**Progress bar** (`hud.gd`): glass bar across the top, fill = song time /
duration, amber ticks at checkpoint bars, a white "best" marker at the
furthest point reached, persisted per level in `Progress.best_song_time`.
On death the fill jumps back; the best marker stays.

## The field and its hazards

The floor is a 9 x 4 grid of 2 x 2 tiles per bar (nine columns, one row
per beat). Tiles are **pulse plates**: dark magenta = armed (lethal on the
next beat), bright magenta = lethal now, cyan = safe. Patterns per bar:
`checker`, `row`, `column_wave`, `spiral`. Plus:

- **Sweeper** — full-height wall with a 3-unit gap crossing the field once
  per bar (and back the next), locked to the downbeats.
- **Gate** — full-width wall at the front of a bar with a 4-unit opening that
  jumps to a new seeded x on every downbeat. The row before it and the
  row after it are always plain: nobody has attention for plates while
  threading a gate.
- **Orbiter pair** — two cyan pillars, each with a magenta orb circling at
  radius 3, one revolution per bar, opposite spin.
- **Slammer** — one-tile bar that drops on its beat of every bar; jumpable
  when down. A `low`-band accent.
- **Pits** — missing tiles. Jumpable. No side walls: off the edge you fall.
- **Notes** — amber orbs on the riskier route. +1 note each, combo x1..x4
  for consecutive notes without dying. The goal label prints notes / combo /
  deaths / score.

Density per bar comes from the beatmap's energy (gauntlet / pressure /
breather / rest); type choice is a seeded weighted pick biased by the bar's
dominant band. Checkpoints sit on the first breather bar of a section.

## Death rules, death log, validator, autoplayer

- **One place decides death:** `Rules.death_cause()` in `rules.gd`. Plates,
  hazard boxes, gate crossings (a gate is a zero-thickness plane in the
  rules: you die by crossing it outside the opening, never by "being inside"
  the wall, so the opening jumping can never catch you), the back edge and
  falling. Meshes are visual only.
- **Death log:** every death prints one `DEATH ...` line (song time, bar,
  beat, phase, player position, killer type and position, whether the rules
  call that spot lethal, the window's back edge, and any hazard between the
  camera and the player). Kept in every build; on the web build it lands in
  the browser console.
- **Fairness validator:** `fairness.gd` runs on the generated layout in
  `Field.build()`. For every beat there must be a safe tile in the window
  that a player can actually reach from a safe tile of the previous beat:
  stand, walk at player speed, wait — every sample checked against the plates
  and hazards at that exact time, with a wider-than-real player box. A bar
  that fails is re-rolled (with the bar before it). Failures go to the error
  log AND the on-screen bottom line. The verdict is cached per device
  (`user://fairness_v*.json`); bump `Fairness.VERSION` when rules change.
- **Headless autoplayers** (`tools/autoplay.gd`, real time, 30 fps cap):

  ```
  godot --headless --path . -s tools/autoplay.gd -- bars=99 mode=validator
  godot --headless --path . -s tools/autoplay.gd -- bars=99 mode=human seed=3
  godot --headless --path . -s tools/autoplay.gd -- bars=5 mode=naive
  ```

  `validator` follows the validator's plan and must finish with `deaths=0`;
  any death is a place where the runtime and the rules disagree.
  `human` is the addendum-2 "five deaths" bot: notices a state change
  (a plate going dark, a gate jumping) 200 ms late but tracks moving
  walls and orbs like a person would, steps to the nearest tile that is
  safe when it lands by a walk that is clear all the way, 10 % of the
  time the second-nearest, waits in front of a wall and goes through
  the moment the gap fits, never goes for notes; seeded. Set
  `HUMAN_DEBUG=1` in the environment to print every plan it makes (`2` also explains every hold). `start_bar=N` jumps in at bar N the way a
  checkpoint rewind would, so one spot can be replayed in seconds. Acceptance: over 20 seeds, median deaths
  <= 5 and 90 % reach the goal within 8 deaths. `naive` replays the first
  phone report. Add `maxdeaths=N` to stop early. The summary line carries
  `min_fps`: if it is far below 30 the results are CPU starvation, not
  play — run fewer bots at once.

## Files

| File | Role |
|---|---|
| `beat_clock.gd` | autoload `BeatClock`. Loads the beatmap, owns song time, seek/pause, beat/downbeat/section signals, `SYNC_OFFSET_S`, scroll speed. Inert in the 2D game. |
| `rules.gd` | the addendum's constants and the pulse-plate pattern functions |
| `hazard_math.gd` | pure "where is it / is it lethal at time t" for every hazard type — used by the nodes and the validator alike |
| `placement.gd` | deterministic layout from per-bar energy and band |
| `fairness.gd` | the mandatory validator |
| `field.gd` | builds tiles, slabs, hazards, notes, checkpoints, the goal gate; animates the plates; floor/pit queries |
| `hazard3d.gd` + `hazard_slammer/sweeper/gate/orbiter.gd` | hazard nodes (pose only; math lives in hazard_math) |
| `player3d.gd/.tscn` | white capsule with a black eye that looks at the nearest coming danger; free movement + jump |
| `camera_rig.gd` | follows the window centre from (0, 17, -10), FOV 50, punch on downbeats |
| `track_test.gd/.tscn` | the run scene: lives, deaths, notes/score, checkpoints, death/goal |
| `flat_mats.gd` | the handful of unlit materials |

## Tuning knobs

- `BeatClock.SYNC_OFFSET_S` — if hazards feel late, raise it (0.030 → 0.060).
- `rules.gd`: `FIELD_WIDTH` (drop to 12 if patterns are unreadable on a phone),
  `WINDOW_DEPTH`, `PLAYER_SPEED_FACTOR`, `LETHAL_BEAT_FRACTION`.
- Density thresholds, band weights, note placement: `placement.gd`.
- Camera offset / FOV: `camera_rig.gd`.

## Input to the level

`assets/audio/fuffens_beatmap.json` + `assets/audio/fuffens_instrumental_vers.mp3`.
Placement is generated from the JSON, never hand-authored. A different song's
beatmap gives a different level with no code changes.
