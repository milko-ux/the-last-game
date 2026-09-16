# Phase R prototype — "an album you survive"

## Overnight report (addendum 4, night of 2026-09-16)

Written as the work went, one line per section; details further down and
in the commits on `phase-r-prototype`.

- **Baseline:** the addendum-3 working tree (gates/pits, volleys/slammers,
  sweepers, orbiters, plates, per-level knobs) plus the intro-carry fix
  were committed first so every section below builds on a clean commit.
- **0. Intro carry:** DONE — validator 0 deaths; human bot 20 seeds: see the table below.
- **1. Camera:** DONE — `camera_rig.gd`: yaw 24° right of the field axis, pitch 54°, distance 26, FOV 48 (`CAMERA_YAW_DEG`, `CAMERA_PITCH_DEG`, `CAMERA_DISTANCE`, `FOV`); input stays world-relative (`INPUT_CAMERA_RELATIVE := false`, flip to test). Fog moved out to 34-58 for the longer camera distance. Screenshot `docs/screenshots/a4-camera-bar1.png` (taken with the new `tools/shot.gd`, since the editor MCP was not connected). Validator bot: see below.
- **2. Pacing:** DONE — `song_offset_s` per level (8 s level 1, 10 s levels 2+) in `BeatClock.start_offset`; run-up to bar 1 is 8.6 s (was 16.6). Breathers are 2 bars (checkpoint, one note, the next wave's word), the rest of each low-energy section is Pressure with the types shown so far; no empty bars after the first checkpoint except those; wave 1 has a gate every bar with a pit on the even bars. Screenshot `docs/screenshots/a4-pacing-bar1.png`.
- **3. In-level ramp:** DONE — `density_curve` per level ([1.0, 1.15, 1.3, 1.5, 1.7] on level 1) multiplies hazards per bar, spent as a fractional budget (a second volley on another row, a second orbiter, a compatible second type once `types_per_bar` allows); level 1 reaches two types per bar in wave 5 and the outro keeps wave-5 density to the goal. Level 1: 99 hazards, 1.27 per bar, 3 empty bars (the second breather bars).
- **4. Orbiters:** DONE — wave 4 carries an orbiter on 7 of its 8 bars (the skipped bars are chosen up front, never the demo); pairs from wave 5 on level 1, free from level 2 (`orbiter_pairs`); `orbiter_period` half_bar for levels 4+ (`speed` 2 in the spec). Orbiters now revolve once per BAR at every hazard rate (they used to follow the level's period, i.e. 4x too fast at beat rate).
- **5. Score:** DONE — `track_test.gd`: distance_points = floor(progress × 1000), death_penalty = deaths × 40, note_bonus = notes × 15 × combo_max, score = max(0, …); live in the HUD, on the goal label (distance %, deaths, notes, score) and on the death screen; best score per level persisted in `Progress.best_score` (`progress.gd`). Not wired to Talo.
- **6. Levels 2-6 + level select:** DONE — `levels/curriculum.json` (30 levels; 1-6 hand-set from the addendum table, 7-30 interpolated), read by `Rules` (`Rules.LEVEL` is now a variable). Levels 2+ use the mixed generator (five waves, 2-bar breathers, incompatible pairs enforced, a demo bar for each pattern new to the level while `demo_bars` is on). Lives from level 2 (3), out of lives = minimal death screen (score, died at N %, retry from level 1). `prototype/level_select.tscn` is the Phase R main scene: 1-6 playable once the previous goal is reached, 7-30 shown locked. Screenshot `docs/screenshots/a4-level-select.png`. Walls at fast rates: sweepers cross once per bar at every rate and gates jump at most once per half bar — the validator proved the faster versions unwinnable.
- **7. Bots:** IN PROGRESS — validator bot: levels 1, 2, 3, 6 = 0 deaths, goal reached (4 and 5 running). Human bot, level 1, first batch on the addendum-4 build: every seed hit the 9-death cap, all back-edge, mostly while staged behind the gates of bars 27-31 and 11-16 — the bot's "arrived" test (0.1 units) was smaller than one frame of movement (0.29), so it jittered at a staging tile for seconds without re-planning while the line closed in, and a held target was never dropped when the line pushed. One fix pass (`tools/autoplay.gd`), batches re-run: tables below.
- **8. Handoff:** pending


Run it (from the repo root):

```
/Users/benim/Downloads/Godot.app/Contents/MacOS/Godot --path . prototype/track_test.tscn
```

Web build for the phone:

```
tools/package_web.sh "Web (Phase R)"     # exports to build/phase-r/ and zips it
tools/serve.py tls build/phase-r         # https://<LAN-IP>:8443, accept the cert once
```

### Bot tables (addendum 4 section 7, night of 2026-09-16)

Validator bot (must be 0 deaths): levels 1, 2, 3, 4, 5, 6 — **0 deaths, goal reached on all six.**

Human bot, 20 seeds each, bots play without lives (rewind to checkpoint on every death):

| Level | median deaths | mean | reach goal | goal within 8 | deaths by kind | verdict |
|---|---|---|---|---|---|---|
| 1 (target: median ≤ 5, 90 % goal within 8) | **2** | 1.9 | 20/20 | **20/20 (100 %)** | sweeper 27, back edge 9, orbiter 1 | PASS |
| 3 (target: median ≤ 10) | **4** | 5.4 | 17/20 | 16/20 | gate 44, sweeper 37, back edge 14, volley 10, orbiter 3 | PASS |
| 6, first run (target: median ≤ 16, ≥ 70 % goal), cap 20 | **20 (cap)** | 20 | 0/20 | 0/20 | sweeper 193, back edge 96, gate 17, plate 4, orbiter 3 | FAIL |
| 6, plate_coverage 0.5 → 0.4 (the addendum's first remedy) | see below | | | | | |

Per-seed deaths, level 1: 3 3 0 2 3 2 1 2 2 0 2 3 0 2 4 0 0 1 6 1. Level 3: 3 4 2 2 3 2 11 8 4 3 13 13 6 13 0 7 6 4 3 1.

**Reading level 6:** the failure is the sweeper, not the plates — 193 of 313
deaths are sweeper walls, 4 are plates. Level 6 has `sweeper_gap` 3 (level 1:
5, levels 2-4: 4) and the bot plans walls with a 0.55 half-width, so a
3-unit gap leaves 1.9 units of slack at 7.3 units/s. The addendum's remedy
order (plate_coverage first, then types_per_bar) does not touch the killer;
the coverage step was applied once as prescribed and re-run (row above).
The decision that would actually move the number — `sweeper_gap` 4 on
levels 5-6 — is Milko's to make; it is one number in `levels/curriculum.json`.

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

## Level 1 is a curriculum (addendum 3: concrete before abstract)

`placement.gd` builds level 1 wave by wave (`Placement.LEVEL1`), shaped by
the level's knobs in `Rules.LEVELS` (printed at level start). Nothing can
kill you before it has shown itself:

| Bars | Wave | What |
|---|---|---|
| intro (0-16.6 s) | rehearsal | the bar-1 gate's opening moves on each bar of the extrapolated grid, warning colour, nothing lethal |
| 1-8 | doorways | a gate in bars 1, 3, 5, 7 (bar 1 = demo, `GATE`), opening 5 units, jumps once per bar; one one-tile pit in each of bars 2, 4, 6, 8; plain rows before and after every gate |
| 9-16 | breather | open floor, notes, checkpoint at 9 |
| 17-24 | thrown | bar 17 volley demo (`VOLLEY`), bar 18 slammer demo (`SLAM`), then one thrown hazard per bar |
| 25-31 | breather | checkpoint at 25 |
| 32-40 | walls | bar 32 sweeper demo (`WALL`); one sweeper per bar at most, gap 5 units, plain rows either side; one gate allowed |
| 41-48 | breather | checkpoint at 41 |
| 49-56 | orbiters | bar 49 demo (`ORBIT`); single orbiters only, gates allowed |
| 57-64 | floor | bar 57 `row` demo (`FLOOR`), bar 59 `block` demo; plates cover at most 4 tiles of a bar, warn a full bar, fire on the downbeat |
| 65-78 | outro | one already-shown hazard every other bar, breather density, ends on the goal |

Hard rules the generator enforces (push_error on violation): never two
hazard types in one bar, plates never before the floor wave, no
beat-rate patterns (`checker`, `spiral`, `column_wave`) in level 1, and
nothing lethal before its demo bar, per type AND per plate pattern.

**Hazard rate.** Hazards act once per PERIOD (`BeatClock.period_beats`,
from the level's `hazard_rate` knob): one bar on level 1 (~2 s at 117
BPM), half a bar or one beat on later levels. The song and the scroll
never change, only how often hazards do something. A hazard warns for
one full period before it fires. Gates jump, sweepers cross, orbiters
revolve and plates fire once per period; volleys and slammers run a
two-period cycle (warn, fire).

**Knobs** (addendum 3 section 4, `Rules.LEVELS`): `hazard_rate`,
`plate_coverage`, `plate_patterns`, `gate_opening`, `sweeper_gap`,
`types_per_bar`, `orbiter_pairs`. Level 1 = bar / 0.12 / [row, block] /
5 / 5 / 1 / false. Gap and opening widths are in world units (a tile is
2 units). Levels 2-30 are meant to be rows in that table.

A demo hazard runs its full behaviour in the warning colour and never
kills; the creature's eye locks onto it and one glass word shows above the
field for that bar.

**Level 1 has no lives** (`Rules.LEVEL`, `Rules.lives_enabled()`): death =
0.25 s freeze, rewind to checkpoint, continue; no death screen, no life
counter. Lives and the share screen start at level 2 (not built).

**Progress bar** (`hud.gd`): glass bar across the top, fill = song time /
duration, amber ticks at checkpoint bars, a white "best" marker at the
furthest point reached, persisted per level in `Progress.best_song_time`.
On death the fill jumps back; the best marker stays.

## The field and its hazards

The floor is a 9 x 4 grid of 2 x 2 tiles per bar (nine columns, one row
per beat). Tiles are **pulse plates**: dark magenta = armed (fires at the
next period start), bright magenta = lethal now, cyan = safe. Level 1
plates are an explicit tile list (`row` segment, 2x2 `block`); the
beat-rate patterns `checker`, `column_wave`, `spiral` are level 3+. The
one plate rule is `Rules.plate_state()`. Plus:

- **Sweeper** — full-height wall with a gap (`sweeper_gap` units) crossing
  the field once per period (and back the next), locked to the period starts.
- **Gate** — full-width wall at the front of a bar with an opening
  (`gate_opening` units) that jumps to a new seeded x at every period
  start. The row before it and the row after it are always plain: nobody
  has attention for plates while threading a gate.
- **Orbiter** — a cyan pillar with a magenta orb circling at radius 3, one
  revolution per period. Level 2+ may use the opposite-spin pair.
- **Volley** — an orb fired from one edge along one tile-row, crossing the
  field in one period; the period before, a dark line along the row and a
  muzzle block at the edge warn you. Lethal only on contact; low enough to
  jump (radius 0.75, so the top sits under the jump apex).
- **Slammer** — one-tile bar that drops at the start of its firing period
  (every other period), bright for the whole period before; jumpable when
  down. Volleys and slammers are the "thrown" family.
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
  godot --headless --path . -s tools/autoplay.gd -- bars=99 mode=human level=6 seed=3 maxdeaths=20
  godot --headless --path . -s tools/autoplay.gd -- bars=5 mode=naive
  ```

  `level=N` picks the level (levels/curriculum.json). Bots always play
  WITHOUT lives (`Rules.LIVES_OVERRIDE = 0`): they measure the level, so
  a run rewinds to the checkpoint on every death like level 1 does.

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
| `rules.gd` | the addendum's constants, the per-level knobs (`LEVELS`), the one plate rule and the death rules |
| `hazard_math.gd` | pure "where is it / is it lethal at time t" for every hazard type — used by the nodes and the validator alike |
| `placement.gd` | deterministic layout from per-bar energy and band |
| `fairness.gd` | the mandatory validator |
| `field.gd` | builds tiles, slabs, hazards, notes, checkpoints, the goal gate; animates the plates; floor/pit queries |
| `hazard3d.gd` + `hazard_slammer/sweeper/gate/orbiter/volley.gd` | hazard nodes (pose only; math lives in hazard_math) |
| `player3d.gd/.tscn` | white capsule with a black eye that looks at the nearest coming danger; free movement + jump |
| `camera_rig.gd` | follows the window centre from (0, 17, -10), FOV 50, punch on downbeats |
| `track_test.gd/.tscn` | the run scene: lives, deaths, notes/score, checkpoints, death/goal |
| `level_select.gd/.tscn` | the Phase R main scene: glass grid of the 30 levels, 1-6 playable, unlock = previous goal reached |
| `../levels/curriculum.json` | one entry per level 1-30: the knobs (`Rules.level()`), see its `_readme` |
| `../tools/plan_stats.gd` | generate + validate levels headlessly in seconds: `godot --headless --path . -s tools/plan_stats.gd -- levels=1,2,3` (`PLAN_BARS=1` prints every bar, `FAIR_DEBUG=1` explains a fairness failure) |
| `../tools/shot.gd` | framing screenshot: `godot --path . --resolution 2400x1080 -s tools/shot.gd -- out=docs/screenshots/x.png bar=1 level=1` (or `scene=select`) |
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

## The intro carry (fixed 2026-09-16)

Level 1's song has ~16.6 s before bar 1 and hazards are inert until then,
but the death line used to be live from t=0: a first-time player who had
not touched the controls yet stood still, the window rolled past them,
and they died about 1.5 s in, over and over, before the first downbeat.

Now, in `rules.gd`: **during the intro the back edge does not kill**
(`Rules.death_line()` is -INF before `hazards_armed_at`) and **the window
carries the player** instead (`Rules.carry_line()`: the player is never
left behind the back edge plus one tile, applied in `player3d.gd`'s tick).
On the first downbeat the death line arms one tile behind an idle player.
`Rules.min_z()` is the lowest z the player can occupy either way; the
validator and the bots plan against it, the death check reads
`death_line()`. The cyan edge line is drawn at `Rules.back_edge()` all
along, so nothing jumps on screen when it arms.
