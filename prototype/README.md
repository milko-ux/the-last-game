# Phase R prototype — "an album you survive"

## Where we are (2026-09-20, 01:40)

**Done, on `phase-r-prototype`:** Phase R (the gameplay model, levels 1-6 playable, bots, validator) · Phase A brief 1 creature · brief 2 world + colour pass · brief 3 motion · brief 2b materials (procedural stone / concrete / hot glass / gloss, fog, one beatmap scaled by `song_tempo`, pace: tempo 1.0/1.05/1.10, player 2.2/2.3x) · seams as dark grooves · window depth per level (2.5 bars on level 1, 2.2 after; camera 28/26) · level 6 validates with `reroll_passes` 40.

**Asked for, not done yet:**
- Brief 4 (props): built — see the report below; validator rerun on 1-5 pending at the time of writing.
- Level-1 human bot at the current pace (2.5-bar window): validator 0 deaths on 1-5; human bot **median 6, 12/20 — FAIL**, 82 of 100 deaths are orbiters (bars 46-54). Tempo is off the table (Milko); the lever that fits the data is the orbiter wave on level 1 (fewer orbiters, or `orbiter_pairs`/density there) — not applied, Milko's call.
- Level 6 first-play cost: its layout takes 35 validation passes (64 s on the Mac, minutes on a phone) once per device. Shipping the found re-rolls with the game (`levels/verdicts.json`) would remove that — offered, not started.
- Phone frame time has never been measured from here; every brief's "within 1 ms" is unverified.

**LAN build:** `https://172.20.10.2:8443` (phone hotspot; accept the certificate once; `tools/serve.py tls build/phase-r` restarts it). Current export = brief 4.

**Models in `assets/models/`:** all placed — `creature.glb` (the hero), and via their light copies in `assets/models/lod/`: `gate_pillar`, `sweeper_segment`, `slammer`, `orbiter_pillar`, `volley_emitter`, `building_tall`, `building_stacked` (brief 4). Orbs and notes stay the shader spheres.


## Phase A report — brief 4, the props (2026-09-20)

**`rules.gd` untouched. So are `hazard_math.gd`, `fairness.gd`, `placement.gd`: every hit box, timing and position is what it was; only what is drawn there changed.**

- **Light copies:** the seven GLBs are ~30k triangles each (image-to-3D bakes with hundreds of UV islands). `tools/decimate_models.py` makes `assets/models/lod/*.glb`: vertices welded (decimating the split bake opened a crack at every island), quadric decimation to 1.5-4k triangles, and the bake's colour sampled at each new vertex as a vertex colour (re-projected UVs shattered; the texture-aware decimator stopped at 3-4x). 40-100 KB each, no textures. The originals are untouched and still in the repo. Godot's importer has no base-mesh simplification (only LODs), which is why this is a script.
- **Props helper** (`prototype/props/props.gd`): rest yaw per model (all seven arrive eye-to-+z, so 0), base-centre pivot, model size from the bounds, `make(name, size, pivot, material, yaw, mirror)`. Clay shader: LIT like the creature, vertex colour with the armed (wine, 55 %) or live (magenta, 75 %) tint scaled by the clay's own luminance so the eye recesses stay dark; breathes toward live on `pr_armed_pulse`; fresnel rim when live; the brief 3 white flash still works (it swaps `material_override`). Building shader: unlit, vertex colour, the concrete grain on top (at 1.5k triangles the bake alone is flat), contact shadow, distance fade.
- **Gate:** clay pillars from each edge of the opening out to the field edge (the whole span kills, so the whole span is drawn), the right side mirrored on x. The pillar model's x-bounds are symmetric (±0.56) and each side's root sits at gx ± gap/2, so the inner faces ARE the rules' opening to the unit — 0.0 error by construction, not eyeballed. The brief 3 slide moves both sides.
- **Sweeper:** 2-unit loaf segments, two rows high (a loaf is 1.2 tall, the wall's hit box 3.0 — one row would read as jumpable), rounded ends at the gap, whole segments only so the outer end can overhang the field edge by < 2 units (not lethal there: off the field). The train's inner ends sit exactly on the gap's edges.
- **Slammer:** scaled uniformly to the box's width (1.9); the flat underside sits on the box's bottom plane; the block is taller than the 0.6 box — above it, where nothing can be.
- **Orbiter:** the groove ring is 55 % up the model (measured), so the pillar is scaled until the groove is at `ORB_Y`; the orb is unchanged. The pillar is safe (no tint).
- **Volley:** the egg at the field edge, eye across the field (+90° per `dir`), fitted to the old muzzle's 1.4 height, always visible; 15 % squash on fire.
- **Buildings:** the seeded placer picks tall (60 %) or stacked; far huge ones are tall. One MultiMesh per model per 4-bar chunk, chunks switched off outside the fade range (`Monoliths.set_window`), so ~6 draw calls of buildings per frame instead of the whole level. Gotcha: with `use_colors` off the web renderer multiplied the mesh's vertex colours by zero — instances carry a white colour.
- **Triangles per screenshot** (`RenderingServer` primitives in frame, whole scene incl. tiles and creature): `a-props-bar1.png` **72 662** · `a-props-wave2.png` **37 650** · `a-props-wave3.png` **98 626** · `a-props-wave4.png` **46 406**. All under 150k.
- **Validator:** see the line below (rerun on 1-5 after the change).

## Phase A report — brief 2b, materials and pace (2026-09-20)

**`rules.gd`: one change, the one the brief asks for — `WINDOW_DEPTH` 2.5 → 2.2 bars (§7). Nothing else in it, nor in `fairness.gd` / `hazard_math.gd` / `placement.gd`.**

Everything is procedural in the shaders (`flat_mats.gd`, `monoliths.gd`, `camera_rig.gd`, `creature.gd`): 2-octave value noise from world position, no texture lookups, no generated images. Per-frame uniforms are still the six from brief 3 plus `TIME`.
- **§1 Tiles:** `TILE` face with ±6 % grain at 0.6 units (`GRAIN`, `GRAIN_SCALE`), ±3 % per-tile shade from a hash of the tile's origin (`TILE_VARIATION`), 18 % occlusion within 0.12 of every seam (`AO_*`); seams unchanged; armed plates keep the grain under the wine tint, live plates wash out flat to `LETHAL_LIVE` + bright seam (the 80 ms pre-fire wash is not timed per tile — the armed breathing from brief 3 grows toward the firing beat instead); sides: same shader, `TILE_SIDE`, grain scale 1.2.
- **§2 Monoliths:** triplanar grain ±8 % at 1.5 units + ±4 % at 5 units, formwork bands every 2.5 units (0.05 wide, 2 % darker), top faces still 12 % lighter, a 0.3-unit contact shadow at the foot. Still one draw call.
- **§3 Hazards:** walls, gates, sweepers, slammers, the volley muzzle = hot glass (`GLASS_SHADER`): 55 % / 70 % body armed / live, fresnel rim toward `LETHAL_SEAM` at 0.6 / 1.0 (+0.4 with the beat's armed pulse), base-to-top inner glow 30 %, heat shimmer drifting 0.15 units/s at 4 %, never on the rim. Orbiter and volley orbs = gloss (`GLOSS_SHADER`, LIT by the creature's light): dark magenta body, specular highlight, soft rim, faint inner glow. Pillars and checkpoint markers = the tile's stone shader in `SAFE` tint with the bright rim on every edge. The death line stays the bright bar it was (it is the rim).
- **§4 Notes and goal:** notes = the gloss shader in amber; goal gate = hot glass in `GOAL`, rim 1.0.
- **§5 Background:** the gradient quad carries two noise layers (40-unit / 6 % at 0.05 u/s, 12-unit / 3 % at 0.12 u/s) in a plane that scrolls at 20 % of the window; three huge silhouettes (`FAR_SILHOUETTES`) at 4 % above the background ride the rig at 20 % parallax.
- **§6 Creature:** against the textured world it read a touch flat, so its clay got the same 4 % grain and specular 0.3 → 0.4 (`clay_grain`, `specular` in `creature.gd`).
- **§7 Pace:** ONE beatmap. `BeatClock.set_tempo()` divides every time in `fuffens_beatmap.json` by `song_tempo` and picks the `_105` / `_110` mp3 (the only extra audio files; the `_90`/`_95` files and the per-tempo beatmap code are gone). `song_tempo` 1.0 / 1.05 / 1.10 (levels 1 / 2 / 3+), `player_speed` 2.2 / 2.3, `WINDOW_DEPTH` 2.2 bars, camera distance 26. Layouts 1-5 validate (1-8 passes); **level 6 still does not** (bars 41, 67, 71 unfair after 10 passes at the 0.83 box) — Milko's call remains open. The gate-7 rerun of level 1 from the previous pass was superseded by this pace and stopped.
- **Screenshots (web renderer, stills only):** `docs/screenshots/a-materials-bar1.png`, `a-materials-wave3.png`, `a-materials-vs-concept.png`.
- **Frame time:** not measurable from here (no phone); the cost is fragment-shader noise — 2 octaves per tile pixel, 6 per monolith pixel (triplanar), 1 per glass pixel — and no new draw calls. If the phone drops, the fallback the brief names (bake the noise to one 512² tileable PNG from a script in `tools/`) is the next step.
- **Bots:** see below (filled in when the batch ends).


## Phase A report — brief 3, motion (2026-09-20)

**`rules.gd` was not touched. Neither were `fairness.gd`, `hazard_math.gd`, `placement.gd`, hit boxes or freeze times.** Motion is presentation: `prototype/motion.gd` listens to the BeatClock signals the game already fires, sets six global shader uniforms once per frame (`pr_rim_pulse`, `pr_seam_pulse`, `pr_armed_pulse`, `pr_rim_amber`, `pr_ripple`, `pr_build_front`, declared in `project.godot`) and drives a handful of nodes. No per-tile scripts; every number is a constant at the top of `motion.gd`.

In:
- **1. The world on the beat:** rim +40 % on the downbeat / +15 % on other beats, decaying over a beat; seams +20 % on the downbeat, decaying over half a beat; armed hazards (walls, orbs, slammers, armed plates) breathe 25 % toward `LETHAL_LIVE` on each beat of the level's rate, growing toward the firing beat (tile shader and flat shader `armed` materials); gate openings slide over 120 ms after the rules jump (`hazard_gate.gd`, snaps on a rewind); notes bob ±0.15 at the beat rate, turn once per bar, the nearest within two tiles pulses on the beat; monoliths still.
- **2. Death:** hit-stop — nothing samples time in `State.DEAD` and `motion.frozen` holds the beat visuals, while BeatClock and the music keep running (the old `BeatClock.pause()` on death is gone: no audio stutter; the rewind seek is unchanged); camera kick 0.25 s / 0.35 units biased away from the killer + 4 % FOV punch (`camera_rig.kick`); the killer flashes white for 2 frames (`Mats.white_flat`, restored after); on rewind a rim ripple runs from the death bar back to the checkpoint over 200 ms (`pr_ripple`). Level 1 stays lives-free; no added delay.
- **3. Pickup and combo:** the note collapses onto the player over 80 ms, then 8 amber CPU particles burst (one shared emitter); the HUD counter pops 30 % (150 ms settle); combo step-up pops 50 % and the rim pulses amber for that beat; combo break drops the label to 45 % over 300 ms.
- **4. Checkpoint and goal:** a rim ripple forward over two bars (200 ms), the creature glances at the camera (`play_glance`), the progress-bar tick lights; the goal gate's posts widen 1.5 units over the last bar (`field.widen_goal`); on crossing the rim goes amber and pulses on the beat for 2 bars during the three hops.
- **5. Level start:** tiles rise from 0.5 below as they enter fade range (vertex shader on `pr_build_front`, row by row as the front advances), from the first frame of the run-up and for the rest of the level; monoliths do not; the progress bar fills over the first second.
- **6. Camera:** 2 % downbeat FOV punch kept; a 1.5° forward nod on the downbeat decaying over the bar; death kick as above; nothing on jumps.

Not in / not measured: the 4-second recording and the death-flash still were skipped on Milko's call (motion is judged on the phone). Frame time on the phone not measured from here; particle peak is 12 (death) + 8 per pickup, one emitter each, so well under the 200 budget. Bots: a headless run through deaths and rewinds had no script errors; the human-bot batches from the 0.83 hit box are the ones reported above (motion does not affect them).


## Phase A report — brief 2, the world (2026-09-19)

**Colour and readability pass (Milko's screenshot review, 2026-09-19 evening):**
- Palette: `TILE #1c2830`, `TILE_SEAM #0f5f5a` at 0.03 wide; new `TILE_EDGE #19d3c9`, a 0.1-wide bright line along the slab's outer rim only (top face + top of the outer side faces, all the way round; the tile shader gets an `outer` flag per column). `BG_TOP #14171d`, `BG_BOTTOM #262b34`, `MONOLITH #2a2f37`, `MONOLITH_FAR #3a404a`; monolith top faces 12 % lighter (`TOP_LIGHTER`). Fade unchanged, so far things now go lighter into the grey. Screenshots `docs/screenshots/a-world-v2-bar1.png`, `a-world-v2-vs-concept.png` (web renderer).
- **Hit box = the creature's footprint:** `Rules.PLAYER_HALF_W/D` 0.4 → **0.83** (body ball 0.75 model units wide at its equator, arms excluded, x 1.227 draw scale x 0.9). The shadow ring is now a soft dark blob of that size under the body, no rim, `RING_ON_TOP` 0.
- **What the bigger box did to the validator** (`fairness.gd`, VERSION 10): (a) its single 0.2 margin became two — 0.1 against plates (so a tile next to a live plate is still a place to stand) and 0.25 against moving hazards; (b) it was sampling the wait every 0.08 s while a `speed` 2 orbiter's orb moves 1.5 units in that time — invisible with a 0.4 box, but with 0.83 the validator BOT died 11 times on level 6 and once each on 4 and 5, all orbiters, on tiles the validator had called safe. The orbiter check is now widened by half the orb's travel per sample (`orbiter_sweep`). The human bot's margins are the real box + the old offsets.
- **Level 1:** the validator could not make bar 38 (sweeper wave) fair with the 0.83 box, so `sweeper_gap` 5 → 7 on level 1 (one tile; the gate openings were not the blocker, so they stay at 5 unless the bot's median says otherwise — see below).
- **Level 6 no longer validates** with the 0.83 box + the honest orbiter check: unfair bars 37, 42, 44, 67 after 10 re-roll passes (levels 2-5 pass in 3-10). Milko's call: `sweeper_gap`/`gate_opening` up on level 6, or `orbiter_pairs` off there, or accept it. Bots were run on 1-5: validator 0 deaths on all five. Human bot level 1: median 5.5 (was 2) — the box is twice as wide, and the orbiter wave (bars 46-52) and volleys take it; per Milko's rule `gate_opening` 5 → 7 on level 1 and the batch reruns (the gates were not the killers, so this may not move it).

- **Palette:** `prototype/palette.gd` holds every world colour as a constant, the brief's starting values. It is a global class `WorldPalette`, not an autoload: the 2D game already owns the autoload name `Palette`, which the prototype's HUD still uses for its text colours (UI is brief 4). No 3D world colour is declared anywhere else in `prototype/`.
- **Tiles:** one shader (`flat_mats.gd` `TILE_SHADER`): face `TILE`, a 0.06-unit `TILE_SEAM` line inside every edge drawn from the vertex position (tiles now touch; no gap geometry), side faces `TILE_SIDE` with one seam line along their top edge. Plates: armed = face `LETHAL_ARMED`, live = face `LETHAL_LIVE` + seam `LETHAL_SEAM` (white-magenta). Pits are simply missing tiles, so their walls are the neighbours' side faces in `TILE_SIDE` with the lit lip. Distance fade as before.
- **Slab:** every tile and plain slab is 2.0 units thick (`Field.THICK`), so the near face below the death line is the slab's side.
- **Monoliths:** `prototype/monoliths.gd`, ONE `MultiMeshInstance3D` for the whole level = one draw call (unit box, per-instance transform for size/tilt/yaw, per-instance custom data for taper and the far colour; taper is done in the vertex shader). Seeded per level and bar. 1-3 per side per bar, 3-14 units off the edge (4 on the right, the near-right-corner rule), 3-8 wide/deep, 10-40 tall, base at y -22; 1 in 6 bars adds a far one 20-30 units out, 10-18 wide, 40-60 tall in `MONOLITH_FAR`. Tilt ≤ 6°, half tapered 0.7-0.9, 18 % stacked two-high. Same distance fade as the field. All constants at the top of the file.
- **Background:** a two-stop gradient `BG_TOP` → `BG_BOTTOM` on an unlit quad riding on the camera 600 units back (`camera_rig.gd` `_build_backdrop`), identical on web and native; the environment colour is `BG_BOTTOM` as a fallback.
- **Hazards recoloured:** live = `LETHAL_LIVE`, armed = `LETHAL_ARMED` (walls stay see-through); pillars, checkpoint marker and death line = `SAFE` (checkpoints were amber before; a passed checkpoint is `SAFE` darkened); notes and goal gate = `GOAL`; the creature's shadow-ring rim = `SAFE`.
- **Screenshots:** `docs/screenshots/a-world-bar1.png`, `a-world-wave3.png` (bar 19, volley wave), and `a-world-vs-concept.png` = concept | bar 1 | wave 3 side by side. **Taken with the web renderer (`--rendering-method gl_compatibility`), which is what the phone runs.** The Mac's native renderer draws this scene about half as bright (tile face (1,6,7) instead of (10,41,46)); the web one matches the palette to within a couple of values. Judge colours from the phone or these shots, not from the editor.
- **Honest notes:** (1) the seams read louder and the tile face darker than in the concept at the brief's starting values — `TILE` up and `TILE_SEAM` toward `#0f8f88` would move it closer; not changed, they are Milko's numbers. (2) The near monoliths are big dark planes at the screen edges; the "far, huge" ones give the scale. Densities and distances are the constants in `monoliths.gd`. (3) Frame time on the phone not measured from here; the level's ~330 monolith boxes are one draw call, the tiles are the same count of boxes as before.
- **Bots:** nothing in `rules.gd`, `fairness.gd`, `placement.gd` or `hazard_math.gd` changed. Headless validator smoke run after the change: 0 deaths.


## Phase A report — brief 1, the creature (2026-09-17)

**2026-09-19 playtest follow-up:** pace up ~20 % — `song_tempo` 0.95 on level 1, 1.0 from level 2; `player_speed` 2.0 on levels 1-2 (2.1 from 3 as before). Layouts 1-6 re-validated (1-2 passes). Creature down to **2.3 units (1.15 tiles)**. New **shadow ring** under it: a flat dark disc with a faint cyan rim, exactly the hit box's footprint (0.8 units across), always drawn, never fades, stays on the floor during a jump (`RING_*` constants in `creature.gd`). Because the body is wider than the hit box, a ring under the body was invisible when standing, so it is drawn OVER the body at 40 % — `RING_ON_TOP` below 0.92 puts it under instead. Screenshot `docs/screenshots/a-creature-v2.png`. Bot numbers for the new pace: validator 0 deaths on levels 1-4 and 6; level 5 died ONCE (bar 70, orbiter, `rules_lethal_here=true`) in the batch that ran while screenshots were being rendered on the same Mac (min_fps 29), and 0 deaths when rerun alone (min_fps 30) — a dropped frame in a real-time bot, not a level change (level 5's data did not change). Human bot level 1: median 2, 20/20 within 8 — PASS, see the table.

- **Import:** `assets/models/creature.glb` (30 038 triangles, one 1-material mesh, baked JPEG texture, no skeleton). It arrives centred on its own middle, 1.874 units tall, eye toward +z — which is already down the field, so `MODEL_REST_YAW_DEG = 0`. Scale and pivot are fixed in `prototype/creature.tscn` + the constants at the top of `prototype/creature.gd` (feet on the floor, body centre over the pivot); the GLB is untouched. Godot's importer generates LODs for it, so at gameplay size far fewer triangles are drawn.
- **Size / collision:** 3.0 units tall (1.5 tiles). The hit box is exactly the gray-box capsule's (`Rules.player_box`, 0.8 x 1.6 x 0.8 **at the feet**). The brief's "centred on the visual's feet-to-body centre" was NOT followed literally: lifting the box to the visual's middle would let low hazards pass under it and change both bots. Say if that was meant.
- **Material:** lit by one `CreatureLight` (DirectionalLight3D, no shadows, from the viewer's front-left above) in `track_test.tscn`; the world stays unlit. Never distance-faded. "Drawn on top" is done by squeezing the creature's depth toward the camera (`ON_TOP`) rather than turning the depth test off, because the model is not convex and would draw its arms through its body. `skin` and `base_tint` shader parameters are the swap points for later outfits. Checked under both renderers (native and gl_compatibility / web).
- **Eye:** the baked eye is kept — at phone resolution the white, iris and highlight all read (see the jump screenshot), so look-at turns the whole body.
- **Animation (all in `creature.gd`, one `_process`, constants at the top):** breathing ±2 % at 0.5 Hz; 6 % squash on every downbeat (60 ms in, 180 ms spring out); 12° lean into movement; 3 % run bob at 4 Hz scaled by speed; jump = 15 % stretch in 100 ms + **one full 360° turn over the jump's airtime, eased, ending forward** + 20 % landing squash; look-at up to 35° yaw / 15° pitch at the nearest thing lethal within a beat; alarm = +5 % while that thing is within 1.5 tiles; death = grow to 1.3x over the freeze while snapping to face the camera, pop in 80 ms with 12 clay CPU particles, respawn 0 → 1 in 150 ms; goal = three hops, the last held at its top facing the camera (`GOAL_HOLD_AT_APEX`). One addition not in the brief: `SPIN_TILT_DEG = 32` tips the body back at the middle of the spin — the camera looks down at 54°, and without it a level spin showed only forehead.
- **Screenshots (2400x1080):** `docs/screenshots/a-creature-idle.png`, `docs/screenshots/a-creature-jump.png` (`tools/shot.gd ... jump=1` jumps and shoots when the eye faces the camera).
- **Honest notes for Milko:** (1) standing still you see the creature from BEHIND and above — the eye faces down the field and the camera sits behind it — so at idle it reads as a lilac ball, not as the concept image; the character only shows in the jump spin, the look-at turns, death and goal. If it should read as "someone" at rest, the options are a resting yaw toward the camera (say 150°) or a glance-back idle. (2) The image-to-3D back is invented: the model has TWO tail-like prongs, left and right, not the single tail of the concept. (3) Frame time on the phone was not measured from here; the mesh is one draw call with automatic LODs, and the importer's simplify option is the next step if the phone says otherwise.
- **Bots:** the creature is visual only; hit box, jump physics and freeze times are unchanged. Headless bot run with deaths and rewinds: no script errors.


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
- **7. Bots:** DONE (level 6 fails, see the tables) — validator bot: levels 1, 2, 3, 6 = 0 deaths, goal reached (4 and 5 running). Human bot, level 1, first batch on the addendum-4 build: every seed hit the 9-death cap, all back-edge, mostly while staged behind the gates of bars 27-31 and 11-16 — the bot's "arrived" test (0.1 units) was smaller than one frame of movement (0.29), so it jittered at a staging tile for seconds without re-planning while the line closed in, and a held target was never dropped when the line pushed. One fix pass (`tools/autoplay.gd`), batches re-run: tables below.
- **8. Handoff:** DONE — exported with `tools/package_web.sh "Web (Phase R)"`, served on the LAN: **https://172.20.10.2:8443** (accept the certificate warning once; `tools/serve.py tls build/phase-r` restarts it). The build opens on the level select. Camera constants (`prototype/camera_rig.gd`): `CAMERA_YAW_DEG = 24.0`, `INPUT_CAMERA_RELATIVE = false` (plus `CAMERA_PITCH_DEG = 54.0`, `CAMERA_DISTANCE = 26.0`, `FOV = 48.0`). Not done: nothing skipped, but level 6 does not meet its acceptance numbers (the 3-unit sweeper gap; the addendum's plate-coverage remedy was applied once and did not move it). Milko's decision: `sweeper_gap` 4 on levels 5-6 in `levels/curriculum.json`, or accept level 6 as the wall.

### Follow-up, 2026-09-17 (Milko's screenshot review)

- **Camera v2:** DONE — `camera_rig.gd`: still yaw 24° / pitch 54°, now `CAMERA_DISTANCE = 32`, `FOV = 55` (was 26 / 48). The camera orbits the window centre and looks straight at it (it already did in v1; what made v1 read as "offset" was the unfogged field running off the top-right and the near-right corner being off screen). By projection the window's corners land at x 757-1562, y 268-979 of 2400x1080: ~100 px margin at the near edge, clear of both controls. Screenshot `docs/screenshots/a4-camera-v2-bar1.png`.
- **Fog:** Godot's depth fog does NOTHING in the gl_compatibility renderer the web export uses (checked with a screenshot under `--rendering-method gl_compatibility`: every row in full colour), so it is switched off and replaced by a distance fade inside the materials (`flat_mats.gd`): every world material lerps to the background colour by its distance from the window along z, identical on web and native. Knobs: `FADE_AHEAD_START/END` = 14 / 27 units ahead of the death line (a bar is 8, so everything past ~3 bars is gone), `FADE_BEHIND_START/END` = 2 / 10 behind it. The rig publishes the window position as the global shader uniform `pr_window_back` (declared in `project.godot`). Fully faded pixels are discarded, because the web renderer rounds the near-black background to pure black and a black silhouette showed. The player and the death line never fade.
- **Sweeper gap:** `sweeper_gap` 4 on levels 5-9, gap 3 starts at level 10. Level-6 human-bot rerun: see the bot table (still FAIL, but for a different reason).

### Tuning pass from the phone playtest (2026-09-17, evening)

- **Song tempo:** `song_tempo` per level (0.90 level 1, 0.95 level 2, 1.0 from 3). `BeatClock.set_tempo()` picks `fuffens_instrumental_vers[_90|_95].mp3` with its own pre-scaled `fuffens_beatmap[_90|_95].json`; nothing is rescaled in code. `song_offset_s` stays written for tempo 1.0 and is divided by the tempo, so the song starts at the same musical spot (level 1: 8.9 s).
- **Player speed:** `PLAYER_SPEED_FACTOR` 2.2 → 1.8, **but only levels 1-2 run at 1.8** (`player_speed` knob); levels 3+ carry 2.1. Reason, from the validator: below ~2.1 the player covers 3.44 units per beat and a two-row step is 4.02, so at 1.8 levels 3-4 need ~20 re-roll passes to become fair (the game allows 10) and levels 5-6 are still unfair after 40. At 2.1 all six validate in 1-2 passes. A true 1.8 on levels 3+ needs the generator to space hazards for the slower player — Milko's call.
- **Joystick:** there was no smoothing to remove (the touch offset was already read raw every frame), but the dead zone was 13 % of the stick radius and the stick was digital. Now (`track_test.gd`): dead zone 6 % (`STICK_DEADZONE_FRAC`), analog, full speed at 30 % of the radius (`STICK_FULL_FRAC`). The 2D game's `ui.gd` is untouched.
- **iOS Safari / home-screen web app:** the export has no threads (so no cross-origin-isolation headers are needed, which is what usually breaks standalone mode) and the canvas already had `touch-action: none`. Added to the "Web (Phase R)" preset's head: `apple-mobile-web-app-capable`, black-translucent status bar, `viewport-fit=cover`, a fixed non-scrolling body with selection / callout / tap-highlight off, and non-passive `touchmove` / `gesturestart` / `dblclick` blockers so Safari never waits to see whether a touch is a scroll, pinch or double-tap. No service worker on purpose (it would cache `index.pck`, the stale-build trap). Not verifiable from here: whether iOS honours the self-signed certificate inside a home-screen app.
- **Camera:** `CAMERA_DISTANCE` 32 → 28, FOV 55 and angles unchanged; the window spans x 686-1608 of 2400 (about 40 % of the width), the near-right corner sits just inside the bottom edge.
- **Bots after the pass:** validator bot 0 deaths, goal reached, on all six levels. Human bot on level 1 (tempo 0.90, 1.8x): median 3, 18/20 within 8 — still PASS, but it slipped from median 2 / 20/20; see the table.
- **Dev unlock:** `Progress.UNLOCK_ALL := true` (`autoload/progress.gd`) opens levels 1-6 in the level select. Set to false before anything ships.


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
| 6, first run (target: median ≤ 16, ≥ 70 % goal), cap 20 | **20 (cap)** | 20 | 0/20 | 0/20 | sweeper 257, back edge 111, gate 22, plate 5, orbiter 5 (400 deaths) | FAIL |
| 6, plate_coverage 0.5 → 0.4 (the addendum's first remedy), cap 20 | **20 (cap)** | 20 | 0/20 | 0/20 | sweeper 239, back edge 103, gate 30, orbiter 21, plate 6, volley 1 (400 deaths) | FAIL — unchanged, as the death profile predicted |
| 6, `sweeper_gap` 3 → 4 (2026-09-17, speed still 2.2x), cap 20 | **20 (cap)** | 19.95 | 1/20 | 0/20 | back edge 256, sweeper 68, gate 40, orbiter 28, volley 6, plate 1 (399 deaths) | FAIL — sweeper deaths fell 257 → 68, but back-edge deaths rose 111 → 256 |
| 1 after the tuning pass (tempo 0.90, player 1.8x, gap 4), cap 9 | **3** | 3.3 | 18/20 | **18/20 (90 %)** | back edge 49, sweeper 13, volley 4 (66 deaths) | PASS — on the line: median 2 → 3, 36 of the 49 back-edge deaths at bar 32 (the sweeper demo), the slower player staging late at the first wall |
| 1 at the 2026-09-19 pace (tempo 0.95, player 2.0x), cap 9 | **2** | 2.05 | 20/20 | **20/20 (100 %)** | back edge 28, sweeper 13 (41 deaths) | PASS — bars 52 and 39 take 35 of the 41 |
| 1 with the 0.83 hit box (sweeper_gap 7, gate 5), cap 9 | **5.5** | 5.8 | 11/20 | 11/20 (55 %) | back edge 59, volley 35, orbiter 21 (115 deaths) | FAIL — bars 52 and 46 (orbiter wave) and 12; gate openings → 7 per Milko's rule, rerun below |
| 1 at brief 2b pace + 2.5-bar window (tempo 1.0, 2.2x, gate 7, 0.83 box), cap 9 | **6** | 5.0 | 12/20 | 12/20 (60 %) | orbiter 82, volley 18 (100 deaths) | FAIL — bimodal: 9 seeds ≤ 2 deaths, 9 seeds at the cap; all at the orbiter wave (bars 46-54): orb 0.6 + box 0.83 = a 1.43 kill radius on a 3-unit orbit |

Per-seed deaths, level 1: 3 3 0 2 3 2 1 2 2 0 2 3 0 2 4 0 0 1 6 1; after the tuning pass: 0 3 2 2 6 1 6 3 9 6 0 9 3 1 5 4 3 1 1 1; at the 2026-09-19 pace: 2 1 1 5 3 2 4 3 1 0 0 3 0 4 4 3 2 2 0 1. Level 3: 3 4 2 2 3 2 11 8 4 3 13 13 6 13 0 7 6 4 3 1.

**Reading level 6:** the failure is the sweeper, not the plates — 257 of 400
deaths are sweeper walls, 5 are plates. Level 6 has `sweeper_gap` 3 (level 1:
5, levels 2-4: 4) and the bot plans walls with a 0.55 half-width, so a
3-unit gap leaves 1.9 units of slack at 7.3 units/s. The addendum's remedy
order (plate_coverage first, then types_per_bar) does not touch the killer;
the coverage step was applied once as prescribed and re-run (row above).
The decision that would actually move the number — `sweeper_gap` 4 on
levels 5-6 — is Milko's to make; it is one number in `levels/curriculum.json`.

**Reading level 6 after gap 4:** the wall is no longer the killer. 205 of
the 399 deaths are the death line at three bars (40: 84, 19: 69, 10: 52),
the same spot after every rewind — by the rule learned on level 1
("an identical death after every rewind means the BOT is wrong") that
points at the bot's staging, not the layout; the validator bot clears the
level with 0 deaths. No further bot pass was made (one-pass rule).

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
