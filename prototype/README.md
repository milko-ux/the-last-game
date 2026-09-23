# Phase R prototype — "an album you survive"

## Where we are (2026-09-23) — start here

**The game is ONE ENDLESS RUN** (`PHASE_E_BRIEF_1_ENDLESS.md`): how far can you get. **Stage 1 (the run) is built and accepted. Stage 2 is DONE: the menu passed on the phone, the leaderboard is live-checked against the real Talo API end to end.** 2026-09-23, morning: the foot bug found and fixed, brief 6 sections 1 + 2 built — **phone verdict: feet, shadows and 16.7 ms ACCEPTED.** Afternoon (the second brief, below): the cold-start tap offset, the monolith gap (measured, not reproduced), the pit loophole, brief 6 §3 (fog, Milko's corrected version) and §4 (the stone floor and the thick slab). Exported and served. Everything below is newest first; this section is the whole state, the rest is the detail behind it.

### 2026-09-23 (evening) — two engineering jobs, no visual change

**1. The 2D game is out of the way** (tag `archive/2d-game` on `b5c54dd` holds it). `run/main_scene` is `prototype/menu.tscn` for every start; the `.phase_r` override is gone. A dependency scan (roots: `menu.tscn`, the autoloads, `tools/`, the export preset; followed by `res://` path and by `class_name`, plus a hand check of the paths built at runtime — the lod models, the tempo MP3s, the model sources the decimator reads) found 124 reachable files and these not: `entities/` (22 files), `main.gd/.tscn`, `levels.json`, four 2D textures, `tools/check_levels.py`, `autoload/iso.gd` — all deleted, with the `Iso` autoload line, the dead `move_dir()` in `ui/ui.gd` that was its last caller, and the 2D `"Web"` export preset (`"Web (Phase R)"` is now `preset.0` and `tools/package_web.sh`'s default; its `levels.json` freshness branch is gone). `autoload/profile.gd` STAYS: the menu's nickname is `Profile`. The finished briefs moved to `docs/briefs/done/` (PHASE_R + addenda, PHASE_A 1–5); `CLAUDE.md` follows. **Proof:** `index.pck` 22 853 544 → **20 243 864 bytes**, no 2D path left in it; layout hashes 1–6 identical to the morning baseline; `tools/talo_check.gd` **13 of 13 PASS** (the deleted entry showed gone after 585 s — Talo's 600 s listing cache). One thing the check caught on the way: last night's guest-profile guard returned from `_sync_profile` before `Progress.unpost_best()`, so a tool's sign-out left the best marked posted (step 12 FAIL); the guard now covers the profile NAME only — its own commit.

**2. The bots jump pits** (`tools/autoplay.gd`, `_jump_if_pit`). Both bots look ahead along their own velocity for the next `Field.floor_at` gap, and when a one-tile pit lies there they launch the player's real `jump()` timed from the real constants (airtime 2·JUMP_VELOCITY/GRAVITY = 0.674 s × the bot's speed = a 5.8-unit reach at band 1), so the pit sits centred in the jump. Only pits: the trigger is the floor, never a hazard; the look-ahead stops at the field's side and the built course, which are not pits. A pit the jump cannot clear with 0.3 units to spare on both sides is reported as a LAYOUT PROBLEM, not worked around. **Acceptance: level 1 `deaths=0` (1 jump), endless laps 0–2 `deaths=0` (5 jumps); narrowest landing margin 1.90 units, narrowest take-off 1.00.** No LAYOUT PROBLEM anywhere in laps 0–2: every pit the bots met was one tile and clearable. (The first version reported five, all "gap ∞": its look-ahead stopped one jump from the player, so a pit first seen 5 units out had no far edge inside the scan. It now looks a further jump past a near edge; the reports went, the numbers did not move.)

### 2026-09-23 (night) — LOOK PASS v2, from "2005" toward the concept: seven commits, exported, served

Every look screenshot now comes from **`tools/web_shot.py`**: the SERVED web build in headless Chromium at the iPhone's size (852×393 CSS px at 3× = 2556×1179), the real run driven by `?autoplay=1`, a PNG at a given bar (the game publishes `window.pr_bar` four times a second in dev builds). Renderer: ANGLE Metal on the M3 — a real GPU, not software. **Honest limit:** it renders like the Mac's own renderer (carved monoliths where the phone showed flat slabs); Playwright's WebKit loses its WebGL context headless (black). The phone stays the judge.

1. **Monoliths on the web** (`8be42b3`) — reasoned, not reproduced: a uniformly grey slab means the derivative-based facet normal and the world-position noise collapsed to constants, and NaN normals are what makes one vanish; both happen when the fragment stage runs an unqualified varying at half precision (0.5 units coarse at z 700+), which iOS does and the M3 never. Every world varying is `highp` now and the facet normal comes from a camera-relative position. `?detail=0` / `?detail=2` for the phone to rule the mesh swap in or out. (Then section 3 replaced the carved monoliths in the run anyway.)
2. **The background like the concept** (`a7ac3a9`): `monoliths.gd` rewritten — three bands per side per 64-unit strip, each band ONE MultiMesh of the measured 108-triangle hull of the tall model (no carvings; a silhouette cannot show one), near ones dark (`NEAR_PILLAR #141a20`, gap 2–9), mid (`#222a34`), far (`#2f3744`, gap 24–46, a skyline with its own long fade). The far huge ones and the rig's silhouette boxes are gone. In view 25/28 where it was 8/7. **Bar 11: triangles 107 888 → 62 936, draw calls 382 → 369.**
3. **Brightness order and the floor** (`6483d87`): seams thinner and softer (no more graph paper), ±9 % per-tile value with a slight hue shift, the bevel a highlight toward the light and 40 % of that as shade away from it, sheen 0.09. Fog lightest, floor brightest in the play area, near pillars darkest.
4. **Hazards as matte clay** (`a9001b2`, brief 6 §6): live wash 75 → 45 %, armed 55 → 35 %, roughness 0.95 / specular 0.12 on the clay, 0.5 / 0.4 on the orbs; the live rim 1.0 → 1.3 so live still reads first.
5. **The finishing layer** (`2e2132b`, brief 6 §7–8): ACES tonemapping (AgX greyed the magenta and cyan — picked with web shots), glow only on emissives (threshold 0.82), a 25 % vignette, 2 % grain, MSAA 2x — `prototype/finish.gd` + `apply_finish()` in the run scene. **Switches for the phone: `?tonemap=0|aces|agx`, `?glow=0`, `?vignette=0`, `?grain=0`, `?msaa=0`.** If over 16.7 ms on the phone the cut order is grain → glow → MSAA. The menu scene has none of this yet (its own environment).

**Hand-off:** `docs/screenshots/w-bar1-vs-concept.png`, `w-bar11-vs-concept.png` (web build, real run), the singles `w-bar1.png` / `w-bar11.png`. Exported and served on 8443; `index.pck` 20 248 232 bytes.

**What still does not match the concept:** the pillars are boxy hulls, not carved stone (a bake from our own models is the next brief); the hero has no warm rim (§5); the floor's stone grain is noise, not relief; the far fog is one gradient, no volume.

### 2026-09-24 — PART 1 (back to 16.7) and STAGE B (baked stone with Blender): nine commits, exported, served

**Part 1a, `?probe=1` (`0236868`):** the on-phone benchmark. The bot plays bars 9–12 of lap 0, the clock seeks back, the same bars play with the next setup — all on · grain off · glow off · MSAA off · all post off · half the pillars · thin slab — and a table of avg / worst / frames / deaths per setup ends it on screen. On the Mac every row is vsync-capped at 16.7; **the phone's table is what sets the defaults** (waiting on it).

**Part 1b, the death spike (`578945b`):** found in the shipped shell. With `thread_support=false` Godot plays every stream as a Web Audio sample, and `Sample.getAudioBuffer()` returns `_duplicateAudioBuffer()` — every start (play, seek, unpause) copies the whole 165-s buffer, 35–60 ms here, 75 on the phone, whatever the codec (proved with Vorbis, 100 ms Ogg pages, QOA, a spare player). So `BeatClock.preroll()` at death seeks the muted song to the rewind time minus the freeze, in the freeze's first frame where nothing moves, and the rewind only unmutes: **rewind frame 68–104 ms → 10 ms.** A quarter-second of silence at death is the audible change. The track is a QOA-compressed WAV now (sample-exact loop; +3.2 MB).

**Stage B — baked stone, everything under `tools/blender/` (headless, `bake_all.sh` regenerates it all; Blender 5.2.2 on the M3's Metal):**
1. **The pillar kit (`f1877ac`):** six variants (panels, the circle motif, stacked blocks with joints, carved symbols, a slab, a capped one) and a lintel, each a low mesh (26–130 triangles) and a high mesh with the recesses cut in; a node stone material (grain, weathering, edge wear, grime) lit by OUR light plus a soft sky, baked high → low into one 2048 atlas, the light in the colour. Carvings face the lens; nothing is ever turned or tilted in the game. `monoliths.gd` merges kit variants into ONE mesh per band per strip, a pillar pair with the bridge every fifth bar. Fewer per bar and wider gaps than before: air between the towers.
2. **The floor (`0a6658f`):** eight slate tiles with relief, bevelled edges, grain and seam occlusion, baked into a 2048×1024 atlas; the tile shader samples a variant per tile on the top face, armed / live magenta and the cyan rim stay in the shader; sides and pit walls stay procedural.
3. **Hazards (`cfd6c06`):** AO baked into the clay's vertex colours (75 %), recesses get depth with no shader change; `LETHAL_LIVE` #ff2d95 → **#d8267f**, deeper and muted like the concept's walls, live still reads through the rim under ACES and glow.
4. **Tuning (`fabd88b`):** the far band a little lighter and more fog; no leaning pillars.
5. **Texture format:** the project imports ETC2/ASTC, the web preset ships ETC2/ASTC only (the phone's format; desktop Chrome decodes it through ANGLE), the atlases VRAM-compressed with mipmaps. **Pack: 23 496 556 → 27 741 728 bytes (+4.2 MB for the two atlases; the +3.2 MB audio of Part 1b is on top of that), under the +8 MB limit.** Whether iOS WebGL2 takes the ETC2 textures is the phone's to confirm — nothing here can.
6. **Hand-off:** `docs/screenshots/b-bar1-vs-concept.png`, `b-bar11-vs-concept.png` (web build, real run). Bar 1: 62 266 triangles / 350 draw calls; bar 11: 65 622 / 370 (the Mac renderer's counts; before Stage B: 62 936 / 369 at bar 11 — the kit costs no triangles over the hulls).

**What still does not match the concept:** the pillar carvings are shallow reliefs in a bake, not the concept's deep architectural cuts; the floor tiles' relief is soft; no warm rim on the hero; the fog is one gradient. And the phone's frame time with all of this on is unmeasured until the probe table arrives.

### 2026-09-24 (later) — the iOS tab kill, the probe's warm-up, a polish round: five commits

**1. The crash (`452253c`).** Safari reloaded the page at `?probe=1`'s first seek, twice, then "a problem repeatedly occurred": a memory kill. The cause was on record: the shell's `Sample.getAudioBuffer()` returns `_duplicateAudioBuffer()` — every start of the song copies 58 MB. The probe seeks right after loading, at the memory peak; a run's deaths come later, after the transients are collected (why 6–8 deaths did not kill it). **`tools/package_web.sh` patches the exported `index.js`** so the sample hands out the one buffer it decoded (Web Audio allows any number of source nodes on one buffer); the pattern must match exactly once or the script refuses. Measured on the Mac in Chrome: the probe's eight seeks, **JS heap 109 MB → 49 MB**; twenty deaths in a row, 53 MB at the end — no growth. The rest of the budget, measured or reasoned: the atlases ship ETC2/ASTC only and the readout now prints which formats the GPU took (`tex etc2 astc s3tc` on the Mac; **if the phone shows no `etc2`, it is unpacking them to RGBA: 21 + 10 MB instead of 2.8 + 1.4**); the merged pillar strips are ~40 KB each and 9 exist at a time; the prewarm rack is freed after loading. Peak estimate on the phone, before: wasm heap ~250 MB + the decoded song 58 MB + one duplicate per start 58 MB (two or three alive before Safari's GC ran) + the 3D buffers ~20 MB ≈ 450–500 MB at a seek burst; after: ~330 MB, and flat across seeks. `?kill_bar=N&kill_count=20` makes the bot die twenty times for the check; **the 20-death run and the full probe on the phone are Milko's to confirm.**

**2. The probe's warm-up (`ff0a226`):** a thrown-away first pass, so compiles land nowhere in the table. The readout's memory line is the JS heap on the web (Chrome; Safari shows n/a — a release template tracks no engine allocations).

**3. Polish (`4ebec4d`):** live plates muted (LETHAL_LIVE darkened 30 % on the slate, the SEAM bright and pulsing carries "live", the floor capped so it never blooms, glow threshold 0.9 / intensity 0.35); the hero's warm rim (`HERO_RIM #ffb9a0`, 0.5, tight, away from the light); pillar carvings cut three times deeper in the bake with more grime, the near band a step lighter. Pack 27 742 992 bytes.

### NEXT, in this order (2026-09-24)

0. **Milko, on the phone:** (a) `?probe=1` all the way to the table — send it; (b) a normal run with 20 deaths in a row; (c) the `tex` and `heap` words on the readout; (d) the polish against the concept. Then the defaults get set from the table.

0. **Milko: run `?probe=1` on the phone and send the table**; then the defaults get set so the phone holds 16.7 with as much of the look as possible. Then the look against the concept (`b-*-vs-concept.png`), and whether the ETC2 textures show on iOS.

0. **Phone test of the look pass** at `?level=1` bar 11 and in the real run: the look against the concept, the frame time with everything on, then `?grain=0`, `?glow=0`, `?msaa=0` one at a time if it is over 16.7; `?tonemap=agx` for a second opinion on the tonemapper; and whether the pillars now draw properly on the phone (they are the same shader family as the monoliths were, with the highp fix).

**Phone verdict on the afternoon build (Milko, 2026-09-23 evening):** taps on a cold start FIXED, every button works from the first tap · `mono L/R` read 8/7 and 6/7 while the screen showed one or two big, flat, uncarved grey slabs and empty background — so the monoliths are built and counted and **the web renderer does not draw them properly** (that is section 2 of the look pass below) · pits kill, jumping works · frame time in the real run 16.6–16.7 avg, 17–21 worst.

1. **LOOK PASS v2** (the brief of 2026-09-23 night, from "2005" toward the concept), one commit per section: (1) `tools/web_shot.py` — every look screenshot comes from the served WEB build in headless Chromium from now on; (2) the monoliths on the web; (3) the background like the concept, slim pillars at graduated distances; (4) the brightness order and the floor; (5) hazards, brief 6 §6; (6) the finishing layer, brief 6 §7–8 with URL switches; (7) hand-off. Rules: colour meaning stays, the world stays stone/clay/fog, 16.7 ms average at bar 11 in the real run.
2. **The next brief after that: baking in Blender** (`/Applications/Blender.app/Contents/MacOS/Blender`, always headless `-b`) from our own models — the texture rule changed today, see `CLAUDE.md`. Nothing is baked yet.
3. **Brief 6 §5** (the hero rim) if the look pass does not fold it in.
4. **The UI pass** — the backlog below, with the references in `docs/concept/UI/`.

### 2026-09-23 (afternoon) — the second brief, five sections, five commits

**1. Taps land one button too high on a cold start (blocker).** Read in the shipped web shell (`index.js`), not guessed: the canvas size is re-read from the window EVERY FRAME (`godot_js_display_size_update` → `updateSize`) and every touch is mapped as `(clientY − rect.y) × canvas.height / rect.height` with a live `getBoundingClientRect()`. So a stale canvas size cannot do this; the one term that can is `clientY − rect.y`, and those two disagree by the status-bar height exactly when iOS's visual viewport sits scrolled off the layout viewport — which a standalone (home-screen) cold start does until a gesture settles it. 47 pt is 65 canvas units; the menu's button pitch is 66; RETRY/MENU and PAUSE/none fit the same offset. **Fix, in the page head** (`export_presets.cfg` → `head_include`): pin the visual viewport — `scrollTo(0,0)` + a synthetic `resize` at load (again at 250 ms, 1 s, 2.5 s), on `pageshow`, after an orientation change, and on every `visualViewport` scroll or resize. **`?taps=1`** draws a dot and a cross where the game received each tap and prints Godot's window size next to the browser's own numbers (inner size, canvas rect, visual-viewport offset, dpr), once a second — the phone confirms the cause with it. Not a menu-skipping switch. **Untested here by construction** (iOS only); the shell facts are.

**2. Monoliths through the whole run — measured, NOT reproduced.** `tools/autoplay.gd` now samples every frame how many monoliths are in the fade-visible range on each side (`Monoliths.in_view`, visible nodes only) and reports the longest stretch with none: level 1 headless **196 m, gap 0.0** either side; endless laps 0–2 headless **1 784 m, gap 0.0**; endless lap 0 RENDERED through the real LOADING path **617 m, gap 0.1 m**; 5–10 in view per side throughout. The strips, the per-lap queue, the seed, the detail swap and the `_hi` meshes in the pack all check out. The 50 m period equals `FAR_EVERY` (one huge far monolith per 6 bars = 48 units), i.e. the phone shows only the far ones — and nothing on this Mac says why, so nothing was changed blind. The count is on the phone's readout (`mono L/R`); that reading decides the next step.

**3. The pit loophole.** `Rules.LAND_GRACE_Y := −0.3`: a player deeper than that below the floor can no longer land on it by walking sideways — the pit keeps them (a 1.18-unit fall was measured surviving that way yesterday, and the validator bot relied on it without knowing). A landing that CROSSES the floor from above (a jump coming down) is exempt whatever its overshoot: touchdown is 11.9 units/s, 0.2 units per 60 fps frame, 0.4 at 30 fps, more on a hitch — a fixed −0.3 alone would have killed a normal landing on a long frame. `LAYOUT_VERSION` 1 → 2, verdicts regenerated (`levels/verdicts.json`, laps 0–9 all FAIR). **Validator deaths, level 1 / laps 0–2: before 0 / 0 → after 9 in 200 s / 30 in the time it got — and BOTH runs are the SAME death, forever: level 1 bar 6, `killer=fall` at x −6, z 95.6, the one-tile pit between z 92.5 and 94.5. The plan steps from (−6, 91.4) to (−6, 95.5) straight through it.** **Why, before anything else is changed:** the validator (`fairness.gd`) never TARGETS a pit tile, but it does not check the straight line between two waypoints, and a one-tile pit is jumpable by design (`PIT_MAX_Z` 3.0: a jump covers 3.9 units), so the path crosses it on purpose; the bots never jump (they only set `move_dir`), and until today the loophole carried a non-jumping walk across — yesterday's trace showed exactly that fall and snap at this pit. So the bot is wrong, not the level: a human jumps here. The remedy is in the BOT (`tools/autoplay.gd`: jump when the next step crosses a pit), not in the rules — and it is not made yet, on Milko's instruction to report first. Until it is, the validator bot cannot clear level 1 or lap 0, so every bot acceptance is blocked on that call.

**4. Brief 6 §3, the fog — Milko's corrected version.** The backdrop is four stops measured from the concept (`BG_TOP #556173`, `BG_THIRD #38404e`, `BG_MIDDLE #1b2029`, `BG_BOTTOM #0c1016`: light at the top, near-black below), painted by ONE function, `fog_colour(screen height)`, that every world material also fades toward — at the pixel's own screen height (`fog_sy`, the vertex's clip y). So a far floor and a far hazard LIGHTEN into the fog; nothing goes black. Height fog (`low_fog`): below the slab's underside everything sinks toward `BG_BOTTOM` with depth (2 → 24 units, 92 %), which dissolves the monoliths' feet. Far monoliths lose contrast before colour (`far_flatten`). The far silhouettes behind everything are now the fog at their height × 0.93. The `background` uniform is gone from every material. Two things found with screenshots: the clip-space y is DOWN in this renderer (the first version was upside down), and a vertex above the frame must be clamped (it extrapolated past the top stop to white). Screenshots: `docs/screenshots/l-fog-vs-concept.png` (bar 11) — taken with §4 in as well. Cost: no draw calls; a handful of ALU per pixel. Magenta / cyan / amber: unchanged inside the window (the fade starts 14 units ahead, beyond where a player reacts); a far plate lightens toward blue-grey, never toward another meaning colour.

**5. Brief 6 §4, the floor becomes stone — plus the slab body.** `TILE` → `#243141` (the concept's blue slate), per-tile variation ±8 %, seams 35 % darker, a 0.08-unit **bevel** band inside every tile edge shaded by the light (the two edges facing it lighter, the two facing away darker), a faint sheen toward the light (one `pow(dot)`), and a live plate keeps its grain and bevel — stone under the magenta. **The slab is a thick block**: `Field.THICK` 2 → 6, its front face, outer sides and pit walls the concept's dark stone (`SLAB_SIDE #0c151c`) in the light's tones, sinking into the height fog; the cyan rim stays on the top edge. Same boxes, same triangles, but the taller boxes pass frustum culling more often: **draw calls 366 at bar 1 (was 328), 382 at bar 11 (was 343)** — the one cost in this brief; the fallback is a two-box skirt per bar. Frame time at bar 11 in the endless run on this Mac: **6.9 ms average** (`tools/frame_probe.gd endless=1 bars=13`); the phone's number is the acceptance. Screenshot: `docs/screenshots/l-floor-vs-concept.png` (bar 1) — taken with §3 in as well.

**Acceptance, this brief:** layout hashes levels 1–6 — `rules.gd` changed on purpose (section 3), so `LAYOUT_VERSION` was bumped and the verdicts regenerated; every shader compiles (checked by the headless bot's dummy renderer); every changed script parse-checked; validator numbers in section 3.

### 2026-09-23 — THE FOOT BUG, found: it was never the fall

**The README's hypothesis is dead.** The two prints ran (`player3d.gd`'s snap logging the depth, `creature.gd`'s leash logging the frame the raw distance peaks): the worst frame of the run (3.21 units) WAS the snap frame (a 1.18-unit snap up out of a pit) — but the snap was only a trigger, and the same 2.1-unit spike happened at frame 1206 of the same run with **no fall at all**, at a sharp turn. A 30-frame ring-buffer trace around every spike then showed the mechanism, and it is three lines, all in `creature.gd`:

1. **Every reset that puts the feet home — landing (a jump or a fall), a sharp turn (`_plant_swinging_foot`), a teleport, a respawn — sets `_last_lp = [0.0, 0.5]`, which parks foot 1 EXACTLY on the swing boundary.** The swing-entry test was `was < 0.5`, which is false at 0.5, so foot 1's first swing after any reset never refreshed `_foot_from`: it lerped from wherever it last lifted, a stride ago, 2–3 units behind the hip, and swam forward over five frames to catch up. **That is the dragged foot.** Fix: a PLANTED foot found in the swing half is starting its swing now (`was < 0.5 or _down[i]`); `_feet_home()` now also marks the feet planted and resets their from/to; a sharp turn refreshes the other foot's origin. **3.21 → 1.90.**
2. **The tidy-up step home (`_settle_feet`) kept its target fixed where the hip was when the step began** — only the leash's flick re-aimed — and the creature can start walking again inside the step's 0.18 s. Measured outrun by 1.9 units. Fix: it re-aims at the hip every frame, like the flick. **1.90 → 1.66.**
3. **A corrective step could steal the other foot's running step** (`_step_now` overwrote `_settling`), leaving that foot standing in mid-air, "planted" 0.4 units up, dragged at the leash limit until its swing came round; and the leash's step trigger tested `_down`, which the leash itself clears on the foot it pulls in, so the foot never stepped. Fix: no step starts while one is under way, and "planted" for the trigger is the cycle's word (stance half) not `_down`'s. **1.66 → 1.04 — below the leash (1.116): the clamp was never reached in that run.**

**Numbers, `tools/autoplay.gd` level 1, 60 fps, 20 bars, unclamped worst:** before 1.80–3.22 (README), after **1.04 / 1.16 / 1.26** over three clean runs, and **1.28 over endless laps 0–2** (456 s, deaths 0). The bot is real time, so runs differ; the clamp still catches a frame now and then by ≤ 0.16 units — drawn as a leg at full stretch for a frame, not a foot left behind. Validator: level 1 `deaths=0`, laps 0–2 `deaths=0`. **Judge it on the phone**: the bot never jumps, and the jump landing is reset case 1.

**The second bug (`_place_legs` skipping the draw on a teleport frame) is fixed in the same commit:** only the measurement skips a ported frame now; the leg is always drawn. The diagnostic prints and the trace are NOT in the commit.

### 2026-09-23 — BRIEF 6 sections 1 + 2: the light, and things sit on the floor

Screenshots (web renderer, 2400×1080, level 1): `docs/screenshots/l-before-after-bar1.png` and `l-before-after-bar11.png` (`light=0` against the new look), `l-bar1-vs-concept.png`, and the four singles `l-bar1.png` / `l-bar1-light0.png` / `l-bar11.png` / `l-bar11-light0.png`. **`tools/shot.gd` is as flaky as documented** — half its captures are the LOADING frame; the pairs above are the ones that carried a real draw-call count, and the bar-1 pair is about two seconds apart (the tool's clock is not the run's).

**Section 1 — one light, one direction, everywhere** (`palette.gd`, `flat_mats.gd`, `props/props.gd`, `camera_rig.gd`, `project.godot`, `frame_meter.gd`, `track_test.gd`, `menu.gd`, `tools/shot.gd`).
- The scene's `CreatureLight` IS the light. `CameraRig.publish_light(light)` publishes its direction (toward the light, the node's +z: `(0.36, 0.80, −0.48)` — from the viewer's upper left, 53° up, which is what the brief asked for and what the creature was already lit by) as the global uniform `pr_light_dir`, once, from both scenes. The rig also keeps it in `CameraRig.light_dir` for the shadows. `project.godot` carries the same value as the default.
- `lit_tone()` in the shared shader head (`Mats.fade_head()` — the palette's numbers are written into the shader text there, the one place they meet): three tones by the face's normal, **top / lit side / shadow side = 1.00 / 0.74 / 0.46** (`WorldPalette.LIGHT_TOP/SIDE/SHADE`), the shadow side pulled 15 % toward `SHADE_TINT #0f1a26`. Hard steps with a hair of smoothstep so a facet on the boundary does not shimmer. The TILE shader (tiles, slab sides, pit walls, `stone()` = the checkpoint markers and pillars) and the BUILDING shader (monoliths) use it. **The tile's `side` colour is gone**: a slab's sides and a pit's walls are the FACE colour in the side tones, so `WorldPalette.TILE_SIDE` was deleted. The building shader's own light direction, its smooth 0.45→1.3 ramp and "top 12 % lighter" are replaced.
- **`BUILDING_STONE` / `_FAR` start 30 % lighter** (`#5c6272` / `#4f5664`): the tones top out at 1.0 where the old ramp lit a facet to 1.3, so without this every monolith simply went darker (seen in the first screenshot). Milko's numbers, from the screenshots.
- The lit shaders (creature, clay, gloss) already use the real light; they agree by construction — same node.
- **`?light=0`** (a dev URL switch; `tools/shot.gd light=0`) is the old look, exact: the tones are mixed out by `pr_light_on`, the building shader keeps its old ramp under that switch at the old colour scale, and the shadows fade to nothing. `set_light()` in `track_test.gd`.
- Cost: no draw calls, a few ALU ops per world pixel. Triangles/draw calls at bar 1 / bar 11 with the light on and off at the same moment: **328 / 343 draw calls both ways** (see below for the flakiness caveat).
- **Honest note:** a live plate's SIDE face (only visible on the slab edge or a pit wall) in the shadow tone is `#661640`-ish, close to `LETHAL_ARMED` — the plate's state is read from its top, which is untouched, but it is a colour that now exists on screen. Colour meaning on top faces is unchanged: magenta / cyan / amber are never re-hued.

**Section 2 — drop shadows** (`prototype/shadows.gd` NEW, `creature.gd`, `hazard3d.gd` + the five hazards, `prewarm.gd`, `track_test.gd`, `menu.gd`).
- **One `MultiMeshInstance3D`, one draw call, every shadow in the world**: the creature's body and both feet, each gate / sweeper train (one rounded bar per side, from the gap's edge to the last shown segment), slammers, orbiter pillars and orbs, volley orbs, notes. **It replaced the creature's blob (`_ring`, deleted), so the net is zero draw calls** — measured the same count with the light on and off, 328 at bar 1, 343 at bar 11.
- Each caster calls `cast_round()` / `cast_bar()` on it every frame after posing (the node runs at `process_priority 100`); nothing is allocated per frame, CAP 160 instances. The shape is a signed distance in the quad's UV (round, or a rounded bar), a darker core under the contact point, a soft edge, and the world's distance fade so a shadow never outlives its floor.
- **They obey the light**: offset along `pr_light_dir` on the floor by the height above the floor × tan(light angle) — 0.75 per unit here — growing (`GROW` 0.35 / unit) and fading (`SHADOW_MAX_ALPHA` 0.55 at contact → 0.15 at the 2.0-unit jump apex). A slammer's shadow tightens as it drops; a volley orb's runs along the floor under it.
- **The thing the brief did not say, found with the quads painted red:** a shadow the exact size of the footprint is INVISIBLE — the caster stands on it and covers it, and the creature draws on top of everything. So a shadow spreads `SPREAD` 0.55 beyond the footprint, and leans along the light by `SELF_OFFSET` 0.2 of the caster's own height. That is what makes them read at all, and what makes a pillar read as lit from one side.
- **No floor, no shadow** (`Field.floor_at` at the shadow's own centre): nothing hangs over a pit. Hazard shadows follow the posed nodes (hazard_math for the song time), so they hold in hit-stop and rewind with the song.
- `prewarm.gd` draws one instance of the MultiMesh with the real material before the run (a MultiMesh is its own pipeline variant); the menu gives it its own build frame (`_build_shadows`, step 4).
- `light=0` has NO creature blob any more — the blob is gone for good; the A/B for section 2 is shadows against none.

**Acceptance, this slice:** layout hashes levels 1–6 identical (`tools/plan_stats.gd`, before/after); validator bot level 1 `deaths=0` and endless laps 0–2 `deaths=0`; **`rules.gd` untouched**; every changed script parse-checked; every shader compiles (the first version did not — `tint` collided with the clay shader's uniform, caught by the headless bot's dummy renderer). **The phone reading is still to do** (NEXT 1). Draw-call numbers come from `tools/shot.gd`, whose paired captures vary run to run (286–328 at "bar 1" because it does not always shoot the same frame); the on/off pairs quoted are same-frame pairs.

**What still does not match the concept:** the fog is one grey (section 3), the floor is still a dark sheet (section 4), no rim on the hero (5), hazards still read as pink cones at the wash strength they have (6), no glow (7).

### UI PASS BACKLOG (written down 2026-09-22, not built)

- **Leaderboard rows are far too transparent to read** — the row list sits on a 0.5 fill over a dimmed live world and the names and metres drown. The rows need a solid card, not a tint.
- **The whole UI wants the design pass** with `docs/concept/UI/`: the menu (title block, PLAY, the chip), the leaderboard (tabs, rows, JOIN), the end screen (distance, rank line, RETRY / MENU / JOIN), the consent + account panel (still the 2D game's 560-wide card; its heading overflows it; its X sits under the dev readout), the pause panel. Button layers and states per the references — pressed / disabled states do not exist anywhere yet.
- **Shared drawing code is spread over four files** (`Hud.glass_pill` / `Hud.centre_text` in `hud.gd`, `_glass_pill` in `level_select.gd`, `_glow_rect` in both `account_panel.gd` and `leaderboard_screen.gd`, `centre_text` in `ui.gd`). The pass should leave ONE.
- The account panel's `_draw_consent` centres lines by hand at 18 px pitch; a proper paragraph layout is part of the pass.
- The frame readout (dev) collides with anything placed top-right; the pass should reserve that corner in dev builds.

### 2026-09-22 (night) — consent copy, PAUSE, and a profile fix

- **Consent copy** (`ui/account_panel.gd`): Milko's text word for word — JOIN THE LEADERBOARD, five short lines, CREATE ACCOUNT · NOT NOW; "What exactly is stored?" swaps in the old long text unchanged, on the same screen. `Consent.VERSION` 1 → 2, so anyone who agreed to the old wording is asked once more. `docs/screenshots/e-consent.png`.
- **PAUSE** (`hud.gd`, `track_test.gd`, `ui.gd`): a glass pill top-left of the run (88 units in — clear of the notch; 66 units — 48 pt; hidden while a bot drives) → a near-opaque panel with RESUME · RESTART · HOME. **No new clock code:** pause = `BeatClock.pause()` (the death freeze's own call: clock and audio stream stop in the same frame); resume = `BeatClock.seek(song_time)` (the rewind's own call) at the exact time they stopped, after a 3-2-1 count-in with the world visible. Nothing samples time in PAUSED / COUNTIN, so distance, lives and the fairness numbers cannot move; paused wall time is kept out of `run_seconds`. `ui.gd` gained `dead_zone`: the touch controls ignore the pill's own tap. **The proof, one line:** `tools/shot.gd pause=1` — the clock read **21.236 s before the pause, during it, and after resume (moved 0.0 ms)**, the audio-vs-clock gap was **+14.5 ms before and +14.5 ms after** (this Mac's constant output offset), distance 35 → 35, lives 3 → 3. `docs/screenshots/e-pause.png`.
- **A tool's sign-in renamed the guest profile** — found because the menu's chip suddenly read `lastgame-check-112016`. The live check signs in as its throwaway account and `Talo._sync_profile` claimed the name into `profile.save` on this Mac. Gated on `Progress.save_enabled` now (the switch every tool already flips); the file was put back by hand.
- Validator bot `level=1 fps=60` → `deaths=0` after all of it. Exported; serving.


### 2026-09-22 (late) — section 8 ACCEPTED against the real API

Milko created the `distance` board. `tools/talo_check.gd` then ran the whole brief-8 acceptance for real — register → post → on GLOBAL → on MY COUNTRY → delete → gone:

| step | result |
|---|---|
| register a throwaway account | PASS |
| post the best, the way the run does it | PASS — `#1 GLOBAL   ·   #1 SE` (the rank line the end screen shows) |
| posted flag set; a second post is a no-op | PASS, PASS |
| row on GLOBAL, score = the metres, all seven props on the entry | PASS ×3 (`season, country, laps, run_seconds, deaths, build, layout`) |
| row on MY COUNTRY (SE); country rank found | PASS, PASS |
| delete the account; signed out; best un-posted | PASS ×3 |
| entry gone after the delete | **PASS — after Talo's 10-minute listing cache expired** (see below) |

**Screenshots:** `docs/screenshots/e-leaderboard-global.png`, `e-leaderboard-country.png` (a real row, `#1 lastgame-check-112016 · 1 234 m · SE`, live world behind), `e-end-screen.png` (guest, JOIN). All four of section 8's shots are in.

**The finding — Talo caches every board listing for 600 s, and it is in their source, not a guess.** The first run of the check failed its last step: the deleted account's row was still listed. `identify` already said "Player not found"; Talo's docs promise entries go with the alias. Their public backend (TaloDev/backend) settles it: the delete route removes the alias inside the request's own transaction and `leaderboard_entry.playerAlias` cascades — erasure is immediate — but `routes/protected/leaderboard/entries.ts` wraps every listing in `withResponseCache({ ttl: 600 })`, no sliding window. A page anyone read shortly before a delete (or a post) stays as it was for up to ten minutes, for everyone, and the game cannot bust it. Measured: the row was gone at the first read after the window. Consequences, all written into `docs/TALO_GOTCHAS.md` (item 5) and `docs/TALO_SETUP.md`: the end screen's GLOBAL rank comes from the POST's own `position` (live); the country rank re-reads a page and can miss a fresh entry on a warm cache, in which case the end screen shows only `#N GLOBAL` (the check reports that as a NOTE, not a failure); the check polls up to 11 minutes for a delete to show and prints the measured time.

**Nothing in the game changed for this** — tool and docs only. The served build is the one exported before the check.

### 2026-09-22 (night) — Stage 2 section 8: THE LEADERBOARD, built, waiting on the dashboard

**What it is.** One board, `distance` (`Talo.DISTANCE_BOARD`): descending, unique — one entry per player, replaced only by a better run, which is Talo's own rule for unique boards. The season is a PROP on the entry, not part of the name, along with `country`, `laps`, `run_seconds` (wall time of the run — a rewind cannot shrink it), `deaths`, `build` (`application/config/version`, now `0.8.0`) and `layout` (`LapGen.LAYOUT_VERSION`): the facts a later cheat check needs, there from day one because prizes are planned.

**Reused, not rewritten.** `autoload/talo.gd` gained three things: `post_best_distance(season)` (posts the player's best ONCE — a `posted` flag in `Progress.best_run` that a new best clears — and returns the rank line), `country_rank()` (the row's index among the country-filtered pages, 1-based), and `_sync_profile()` (the claim/unclaim of the guest name on sign-in/out, which used to be `main.gd`'s job and is now the signal's own, since the menu and the run both need it). `ui/leaderboard_screen.gd` gained a **distance mode** (`open_distance()`): no difficulty tabs, no PROGRESS/FINISHERS, only GLOBAL / MY COUNTRY; a row is rank, name, country, metres; 66-unit tap targets; it paints no opaque background so the menu's live world stays behind it. `ui/account_panel.gd` untouched, opened from three places now (SETTINGS, JOIN on the board, JOIN on the end screen).

**Where it shows.** The menu's LEADERBOARD is lit (amber) when the build has a key and opens the board; dim with "not set up in this build" when it has none. The end screen shows `#12 GLOBAL   ·   #3 SE` under BEST for a signed-in player (the run posts on game over; the country code, not the name — the screen shows codes too), or JOIN TO POST YOUR DISTANCE for a guest, which opens the account panel right there and posts the moment they are signed in (the 2D game's "register on the results screen, score still counts" flow). A best that was never posted goes up the next time the menu opens signed in.

**The key verdict — safe as scoped, nothing to change in the dashboard.** Full reasoning in `docs/TALO_SETUP.md` ("The access key"). In one line: the key identifies the game not a person; with `read/write:players` + `read/write:leaderboards` a stranger can read boards, look up names, register, and post **as themselves** — not as anyone else, because Talo demands that player's session token for any action on a Talo-registered alias; no delete, no emails, no dashboard. A key holder can always post a made-up distance from outside the game; that is every client-submitted leaderboard, and why the props exist.

**`talo.cfg` ships now** — both presets name it in `include_filter`. That means REGISTER · LOG IN works on the phone from this build on (it did not before: the panel said "accounts are not set up in this build").

**Talo's refresh interval — exists, reported, not used.** A board can reset daily / weekly / monthly / yearly; the old entries are archived, readable with `withDeleted` / `include_archived`. The brief said report it and not build seasons on it: the `distance` board is created with NO refresh interval and the season stays a prop.

**Proof so far, against the real API (`tools/talo_check.gd`, new):** `register` PASS with a throwaway account; `post` stops with **"Leaderboard not found"** — the expected stop, the board does not exist yet — and the account is deleted again. The rest of the check (on GLOBAL, on MY COUNTRY, country rank, delete removes the entry, the posted flag) runs the moment the board exists: `godot --headless --path . -s tools/talo_check.gd -- metres=1234 country=SE`. **Regression:** validator bot `level=1 fps=60` `deaths=0` after the run-scene changes; the menu and the board hold `16.7 avg`.

**Screenshots** (`docs/screenshots/`): `e-end-screen.png` (guest, JOIN) is in; `e-leaderboard-global.png` / `e-leaderboard-country.png` wait for rows to exist.

**Tooling found out the hard way:** `tools/shot_scene.gd` used to read the picture from `_process`, which is the PREVIOUS frame's — with a 2D screen that opened this frame it was a picture of the wrong screen, and it looked exactly like "the tap did nothing". It now reads in a one-shot `frame_post_draw` callback. `tools/shot.gd end=1` shoots the end screen (it always could).

~~MILKO'S TURN: create the `distance` board.~~ **Done 2026-09-22 — checked live, see the report above.**


### 2026-09-22 (evening) — the menu's creature GREETS you

Milko accepted the menu and asked for one change first: the creature was standing in profile doing very little. It now faces the lens, looks around, and hops. Screenshots: `docs/screenshots/e-menu.png` (facing, the moment the menu opens), `e-menu-idle-look.png` (looking away), `e-menu-idle-hop.png` (mid-hop), `e-menu-frametime.png` (the frame readout after a hop and a look-around).

- **THE BUG THAT MADE IT STAND IN PROFILE, and it is worth knowing about.** `creature.gd` measures the angle to its look target in **world** space and then applies it as a yaw in **its own** frame. In the run those are the same frame — `player3d` never rotates — so it is exactly right there. The menu's creature IS rotated (it is turned to face the camera), so a world-space target came back as a yaw off by that whole rotation: the body pointed at the lens and the head turned 35° off it, which is the profile. Fixed in `menu.gd` (`_look_point()`): the target is rotated into the stand's frame before it is handed over, and the creature then does the same sum it does in the run. **`creature.gd` is untouched.** The same trap is waiting for anything else that rotates the creature — `play_glance()` / `_toward_camera()` have it too, which is why the menu does not call them.
- **The greeting is creature.gd's own code, driven from the menu.** The body turn is the stand's yaw; the head and eye are `set_look_target()`; the hop is `on_jump()` over `player3d.gd`'s own jump constants at `HOP_SCALE` 0.8 (apex 1.2 units, 0.54 s in the air, so the one full turn still lands on the ground); the landing squash, the footfall and the dust puff are `creature.gd` noticing `on_ground` come back. **No second animation system, no new tween, no AnimationPlayer.** Breathing and the beat squash are untouched.
- **The script is written out, not rolled at random** (`Menu.IDLE`): 18 seconds round, three hops — one about every six. Two hops in twenty seconds read as asleep; a hop every two reads as a fidget. Written out also means a screenshot lands on the same frame twice.
- **The dust puff is prewarmed.** The landing's dust has a material of its own and the web renderer compiles a material the first time something using it is DRAWN — the standing rule at the top of `prewarm.gd`. Without it the FIRST hop's landing would be a hitch on the phone. `prewarm.gd` gained `warm_bursts()` (the burst half of `prepare()`, split out and called by it, so there is one copy) and the menu warms the dust as its fourth build step. Measured: the four build frames spike (418 / 125 / 523 / 113 ms on a cold cache) and **nothing spikes afterwards — no hitch at the first hop.**
- **THE ANSWER TO MILKO'S QUESTION — does facing the camera show the melted underside or the tail prongs? No, and it is better than before.** Square to the lens the tail is BEHIND the body and hidden; the old three-quarter pose was what stuck it out to the side. Through the hop the spin is about the vertical axis plus a 32° tilt AWAY from the camera, so the belly never turns toward the lens: the frames across the whole airborne window show the back and the two rear flipper stubs, which is exactly the silhouette the game already shows on every jump. Checked frame by frame at 2400x1080 across take-off, apex and landing.
- **Frame time: unchanged.** `frame 16.7 avg · 17.4 worst · cpu 0.2 avg · 0.5 worst` at 13 s, after a hop and a look-around (`e-menu-frametime.png`). The run still loads at `load 2.2 s [validate 0.0 (lap 0 shipped) · prewarm 1.9 (55 items, 70 frames)]` — 55 items, the same count as before the prewarm split, which is the proof that refactor changed nothing.
- **`tools/shot_scene.gd` grew a burst** (`frames=N step=S`, one run instead of N) — that is how the hop was found. **Pass `--fixed-fps 60`**, the standing rule from `shot_walk.gd`: without it a frame's delta is however long that frame really took (a cold shader compile is half a second, saving a 2400x1080 PNG another tenth), so `at=` lands somewhere different every run and a moving thing cannot be aimed at. `e-menu-idle-hop.png` was taken that way, so **the frame-time readout in that one image is not a measurement** — `e-menu-frametime.png` is.

### 2026-09-22 (evening) — Stage 2 section 7: THE MAIN MENU

**The game no longer opens into the run. It opens into `prototype/menu.tscn`** (`run/main_scene.phase_r`), and the run is what PLAY loads. Screenshots: `docs/screenshots/e-menu.png`, `e-menu-settings.png`.

- **It is the game's own world, live** — not a picture of it. A five-column strip of the real field (the same tile size and the same `Mats.tile()` material as `field.gd`), two carved buildings behind it dissolving into the fog, the creature standing on the strip facing the camera with its breathing, its beat squash and an idle that looks at the lens, away, and back. The camera is `camera_rig.gd` itself — the game's yaw, pitch and lens, only closer (distance 12.5 -> 17, solved from the window depth the rig is handed, not hardcoded).
- **No new anything.** Glass buttons are `Hud.glass_pill` — the very pill the end screen draws, now a static so both use one copy. Colours are `WorldPalette` and `Palette`. The title is drawn letter by letter to carry real tracking; that is the only new drawing idea in the file.
- **PLAY -> LEADERBOARD -> SETTINGS**, bottom left; the player's name is a chip top right. SETTINGS holds sound on/off, the nickname (RANDOM / EDIT, `Profile`), and **the existing account panel** — `ui/account_panel.gd`, opened unchanged: consent -> register / log in -> manage / delete. **No second account flow was written.** LEADERBOARD is deliberately dim and labelled `next` until section 8.
- **Every tap target is at least 48 pt, worked out rather than eyeballed.** The 2D canvas is 540 units tall whatever the screen is, and the test iPhone gives 1179 device pixels at 3 per point — so one canvas unit is 0.73 pt and the brief's 48 pt is **66 units** (`Menu.TAP_MIN`). The first pass had 48-unit buttons, which is 35 pt. The left margin is 88 units (64 pt) to clear the landscape notch, and the bottom row stops 30 units (22 pt) above the home indicator.
- **Sound on/off is new and saved** (`Progress.sound_on`, `AudioServer.set_bus_mute(0, ...)`). It MUTES, never stops: `BeatClock` reads the song's playback position every frame and a stopped stream has no position.
- **The level select is now a dev tool only**, reached from the menu's DEV pill while `Progress.UNLOCK_ALL`. Tapping "N" there starts an endless run **at lap N-1** (the lap that uses band N), which is the brief's way to look at a band without playing up to it. Nothing there plays an old stand-alone level any more.
- **The dev URL switches still work.** They used to be read by the run scene, which was the first scene; it is not any more. The query is now parsed once in `frame_meter.gd` (`FrameMeter.url_param`, `any_url_switch`), and **a page opened with `?level=N`, `?autoplay=1`, `?live=1`, `?grad=1` or `?scale=X` skips the menu and goes straight to the run** — `?level=1` is still the fixed spot for a frame-time reading and the bot still needs to arrive without a tap.
- **Two rules obeyed on purpose:** the LOADING label is painted before PLAY's blocking scene change, with `FrameMeter.LABEL_TIMEOUT_MS` as the ceiling (copied from `level_select.gd`); and the world is built **one kind per frame** — tiles, then buildings, then the creature — so no single frame carries more than one first shader compile.
- **`Hud.metres()` moved** from `track_test.gd` to `hud.gd` (the menu shows BEST in the same "1 240 m" form). Same function, same output.
- **New tool: `tools/shot_scene.gd`** — opens any scene file, optionally taps it, saves a PNG. `tools/shot.gd` shoots a run and `tools/shot_walk.gd` shoots the walk rig; neither can be pointed at a screen. Section 8's four screenshots will come from this.

**Numbers, Mac, 2400x1080, gl_compatibility:** menu **frame 16.7 avg / 17.6-20.6 worst, cpu 0.1-0.3** — the same 60 fps as the run, which is the brief's acceptance for this screen. The menu's own build costs `[menu 0.9-1.2]` on a COLD shader cache (four frames, one compile each) and that work is not repeated: PLAY still reports `load 2.1 s [validate 0.1 (lap 0 shipped) · prewarm 1.9]`, unchanged from the phone's 2.1 s. **Regression checks:** validator bot `level=1 fps=60` -> `deaths=0`; no layout source was touched, so `LAYOUT_VERSION` did not move.

**Known, left alone:** the account panel's consent heading is a little wider than its 560-unit card — a pre-existing 2D-game layout quirk, not caused by the menu. Worth a one-line fix when section 8 touches those screens.

**WAITING ON MILKO:** the phone test of the menu. Section 8 (the leaderboard) does not start before that.

### Where the work stands

| | |
|---|---|
| Performance | **DONE and closed.** The phone holds 60 fps. |
| Phase A brief 5 (the walk) | **Sections 1-5 done**, accepted by Milko "for now" on 2026-09-21. Pushed: `25a2445`, `fe2e784`, `8ff427b`, `f460f67`. |
| Brief 5 section 6 (the tail) | **SKIPPED on purpose.** This model has no tail, it has two rear flippers, so the brief's z-range sway would swing both together. Milko: handle it when the model is regenerated. |
| Code health check | **DONE 2026-09-22.** Read-only pass, then six commits of housekeeping. See below. |
| Brief 6 (light) | **Sections 1+2 built 2026-09-23**, local commits, not exported. Sections 3–8 next. |

### 2026-09-22 — the housekeeping session (no gameplay or art changed)

A read-only health check first, then the fixes Milko approved. **No game code was touched**: not `creature.gd`, not `rules.gd`, not `placement.gd`, nothing under `prototype/` except this file. Layout hashes and the verdict fingerprint are untouched by construction — re-checked anyway, `LAP READY lap 0 shipped` and the validator bot still clears level 1 with `deaths=0`.

- **The build was shipping the documentation.** Godot imports every PNG under `res://`, so 41 screenshots and 10 concept images were being converted to compressed textures and packed into `index.pck` — 21.5 MB, downloaded by the phone on every fresh load. `docs/` is now in the Phase R preset's `exclude_filter`. **`index.pck` 43 MB -> 22.8 MB, 358 packed files -> 176.**
- **Builds now export OUTSIDE the project**, to `../the-last-game-build/`. A build folder inside `res://` is scanned by Godot, which is why each export was packing the *previous* export's icons into itself. `build/` and `game test 1/` are deleted; `tools/package_web.sh` needed no change (it reads the path from the preset) and `tools/serve.py` defaults to the new location. The one hand-made file in there, the original 2026-08-08 itch.io zip, was kept at `../the-last-game-build/archive/`.
- **The Godot MCP plugin is OFF.** Three dev bridges were starting with the game on the phone; two checked the filesystem for a command file on *every frame* and one injected synthetic input if it found one. Deleting the autoload lines does not work — `plugin.gd` re-injects them and saves `project.godot` every time it starts — so the *plugin* is disabled, which makes its own `_exit_tree()` remove them. `addons/*` is now excluded too. To get it back: enable `godot_mcp` in the editor's Plugins tab, and remember to turn it off again.
- **Three hooks now enforce the rules that used to be prose** (`.claude/settings.json`, scripts in `.claude/hooks/`): a push gate that raises a permission prompt carrying the staged diff and the outgoing commits; a guard that speaks up when a layout source is edited without a `LapGen.LAYOUT_VERSION` bump; and a 0.95 s GDScript parse check on every `.gd` write, which filters the false "Identifier not found" that `--check-only` reports for the seven autoloads.
- **This file lost 60 KB.** The closed-phase reports moved to `docs/PHASE_LOG.md`; "Where we are", the current phase and the reference sections stayed. 100 KB -> 40 KB.
- **`CLAUDE.md` was rewritten.** It still described the pre-pivot synthwave maze game. It now describes the endless run, the current art direction, and Milko's hard rules as rules.

**Later the same day, after Milko's phone test passed** (page 1.9 s, load 2.1 s, frame 16.7 avg / 18-20 worst at bar 12):

- **RETRY on the end screen is fixed.** It was changing scene correctly, but the retried run came up on TAP TO START and sat there, because the tap that pressed RETRY was spent on the scene change and the new scene never saw one. It now starts by itself, which is what the 4 s run-up is for. RETRY also uses `change_scene_to_file` now, the same call MENU makes — `reload_current_scene()` was the only thing the broken button did differently from the working one. Reproduced and fixed against a mirror of the project with the headless shortcut disabled, so the real LOADING path ran: before, run 2 ended at `state=WAIT`; after, `state=RUN` with the clock running.
- **The push gate is a DENY, not an ask.** Milko's session runs in an auto-approve mode that satisfied the tool call before an "ask" could become a prompt — the first real test on 2026-09-22 went straight through. `deny` is not overridden that way, and it is now proven: an attempt was blocked with the message. **Milko's own escape hatch is measured too:** he pushed `ba2e2ee` with `! git push origin phase-r-prototype` and the gate never fired — a command typed with `!` runs in his shell, not as a tool call, so no hook sees it. That was reasoning before; it is a measurement now. The matcher also had to learn to fire only on a command position and to ignore heredoc bodies — the first version denied merely *writing about* the command, in a doc or a commit message.

**Known warnings, deliberately left** (full list in the session's report): two real footguns in the legacy 2D files — a parameter named `scale` in `entities/board.gd:160` and a local named `tr` in `ui/account_panel.gd:447`, both shadowing Godot built-ins. Not biting anything today. The ~30 "return value discarded" warnings are Godot noise. The integer divisions in `beat_clock.gd` and `rules.gd` were each checked and are all deliberate floor divisions.

### (FIXED 2026-09-23, see above — kept as the record of the hunt) KNOWN ISSUE — a foot can still be dragged in the real game

The leash (brief 5A) guarantees `distance(foot, hip) <= LEG_H * LEG_STRETCH_MAX` on the hip and foot the capsule is actually drawn between, so **a foot can never be drawn detached from the body again**. In the walk rig the gait never even reaches the clamp.

**But in the real game the clamp is active**, and it is worse than the 2.5 units recorded earlier: **the unclamped worst reproduces at 3.22** (`tools/autoplay.gd -- level=1 fps=60`, `deaths=0`). It varies run to run — 1.80 at three bars, 3.22 at six, 2.79 at twelve, 2.10 for the human bot — so it is a repeating *spike*, not something cumulative.

**Ruled out on 2026-09-22, with measurements — do not re-check these:**
- **The jump.** The bots never jump. They only set `move_dir`; `_on_jump()` is reachable only from a real tap. The spike happens in runs with zero jumps.
- **The gait, even at the real game's speed.** The rig was re-run at 5.9 units/s, turning, and jumping — a case the old table never covered. Worst readings: forward 0.7982, forward+jump 0.8290, turn 0.9140, **turn+jump at game speed 1.0875**, against a clamp of 1.1160. The rig never once reaches it.
- Earlier, and still true: the plant itself (feet land 0.66-0.76 from the hip), the pose order, and the start-of-run teleport.

**The top hypothesis, and the two prints that settle it.** The rig has a flat infinite floor and its stand-in player can never drop below `y = 0`. The real one can, and two things line up:

1. `prototype/creature.gd:460` — the teleport guard measures only sideways:
   `var moved := Vector3(here.x - _ground.x, 0.0, here.z - _ground.z)`
   That middle `0.0` throws away vertical movement, so `TELEPORT_UNITS` **cannot see the creature move up or down, however far**.
2. `prototype/player3d.gd:70` — `if y <= 0.0 and floor_here: y = 0.0` snaps the player up from whatever depth it had fallen to, in one frame. `Rules.FALL_DEATH_Y` is **-3.0**, so that snap can be just under 3 units, it is not a death, and it happens freely inside a "death-free" run. **The worst measured is 3.2165.**

**Next session starts here:** one `print` at that snap logging the height it snapped from, one in `_leash()` logging the frame the raw distance peaks. Same frame = proven. Cheap cross-check: run `autoplay` on a level with no pits and see whether the spike disappears.

**A second, separate bug found on the way** — worth fixing whichever way the first one lands. In `_place_legs`, `prototype/creature.gd:906`, `if _ported: continue` skips the rest of the loop body — which includes `leg.global_transform = ...`, **the line that actually draws the leg**. So on any frame flagged as a teleport the legs are not repositioned at all: they hold last frame's pose while the body moves on. The measurement and the drawing are being skipped by the same flag, which means the legs go wrong on exactly the frames nobody is measuring. This alone could be the drag Milko sees. It changes how the creature looks, so it gets flagged before it is changed.

**How to measure it:** `tools/autoplay.gd -- level=1 fps=60` prints a `LEASH` line over a clean, death-free run (max as drawn, planted, and the unclamped worst). `tools/shot_walk.gd -- slide=1 dir=forward|turn|strafe [jump=1] [speed=1.5]` is the rig version and is the reliable instrument; `tools/shot.gd` prints `LEASH` too but its captures are flaky (see below). Note the rig's `slide=1` report prints the clamped numbers only — it never prints the unclamped worst, which is why the rig looked clean for so long.

### (superseded by the NEXT list at the top) the earlier NEXT list

1. **Section 8's phone test** — the served build has the key: SETTINGS → REGISTER, play, die, see `#N GLOBAL` on the end screen, see the row on LEADERBOARD (up to 10 min late, that is Talo's cache), delete the account in SETTINGS → ACCOUNT. Then Stage 2 is closed.
   - **It reuses the 2D game's code, which is exactly why that code MUST STAY IN THE EXPORT**: `autoload/talo.gd` (the only file that talks to the internet), `autoload/consent.gd` (GDPR consent + the self-declared country), `ui/leaderboard_screen.gd` and `ui/account_panel.gd`. Do not "clean up" the 2D files or their autoloads — `Talo` and `Consent` ARE Stage 2's backend. `docs/TALO_GOTCHAS.md` and `docs/TALO_SETUP.md` become live reading again.
   - The backend is already live and verified end to end against the real Talo API (2026-09-02): register, play, submit, rank, delete. `talo.cfg` is gitignored and must exist locally per `docs/TALO_SETUP.md`; with no key the whole feature hides itself.
   - ~~One export detail to fix when Stage 2 lands: the "Web (Phase R)" preset has an empty `include_filter`, so it does NOT ship `talo.cfg`.~~ **Done 2026-09-22.**
   - **On web, HTTP goes through `JavaScriptBridge`, never `HTTPRequest`** — see `docs/TALO_GOTCHAS.md`. That is a branch nothing on this Mac has ever tested.
2. **The foot bug — the two prints, first.** `prototype/creature.gd` has roughly doubled over briefs 5 and 5A/B and carries five interacting clocks (the stride phase, the settle clock, the leash's recovery step, the jump tuck, the mode timer), which is where this is hiding. Do not split the file until the bug is found; splitting it now just moves the bug house.
3. **Brief 6 sections 1 + 2 as ONE slice** (`PHASE_A_BRIEF_6_LIGHT.md`): one light direction published as a global uniform, then drop shadows, **creature first** (body + both feet), hazards after. Taking section 1 with it avoids hardcoding a light direction and then reworking it.
   - **Cost: zero net draw calls.** All shadows go in one `MultiMeshInstance3D` -- one call however many casters -- and it REPLACES the blob the creature already draws under itself (`_ring` in `creature.gd`). The real cost is fill rate (transparent quads), a fraction of a percent of the frame at bar 11.
   - **Why it is not more leg tuning:** "it floats" is a contact problem. At game distance the whole creature is about 105 px tall and a leg is ten of them, so no amount of thickening solves what a shadow solves directly.

### Today's numbers, from Milko's iPhone (2026-09-21, build `5648f06`)

| | reading |
|---|---|
| Load (landscape) | **2.2 s** `[validate 0.0 (lap 0 shipped), prewarm 2.0 (54 items, 71 frames)]` |
| Start screen | 17.1 avg / 49 worst |
| **Play, lap 0 bar 17** | **16.7 avg / 22.0 worst, cpu 1.1 / 2.0** · audio -1372 (+0) |
| Portrait | LOADING shows under ROTATE YOUR PHONE |
| Faceted pillars | "not noticeable, keep them" |

16.7 ms is 60 fps, the target exactly. The road there: 28.7 avg -> 21.9 (the 0.75 render scale) -> **16.7** (the cheap pillars). The load: 6.5 s -> **2.2 s**; `validate 0.0 (lap 0 shipped)` is the verdict fingerprint working on a real device and is the phrase to look for if it ever regresses. `audio -1372 (+0)` is the expected read-out: the device's constant offset, correctly ignored.

**The walk has NOT been measured on the phone for frame time.** Brief 5 adds two leg capsules and a dust emitter: 8 more draw calls at bar 2 of level 1, and slightly fewer triangles. Worth one reading at `?level=1`, bar 11.

### Asked for but not done
- **Brief 5 section 6 (tail)** -- skipped, see above. Milko's call, deferred to the model regeneration.
- **Step 1c, the monolith shader** -- parked for good unless brief 6 needs it. Monoliths are now the biggest item in frame (69 880 triangles), so if lights and shadows cost too much, that is where the headroom is: fewer noise octaves, or the baked 512 px noise tile from the brief 2b report.
- **`tools/shot.gd` is flaky** and it is not worth trusting for a paired screenshot: its clock disagrees with the run's after a fast load (it can report `bar=11` while the run is at bar 0) and it sometimes saves a black LOADING frame. It now refuses to save unless the world is up, which stops the black frames. **Use `tools/shot_walk.gd` (deterministic, `--fixed-fps 60`, `cam=game` gives the game camera's own angle and lens) for anything that has to be the same moment twice.**

### Rules that bit me -- keep them
- **Nothing that can raise, and no `JavaScriptBridge`, inside a `RenderingServer.frame_post_draw` callback.** They increment an int and nothing else.
- **Every loading gate needs a ceiling** (`FrameMeter.LABEL_TIMEOUT_MS`, 2 s, then carry on and mark the line `TIMED OUT`).
- **A branch behind `OS.has_feature("web")`, or anything that reads a file the exporter transforms, has been tested by nothing on this Mac.** The verdict fingerprint was the second instance in two days.
- **Bump `LapGen.LAYOUT_VERSION`** whenever placement / rules / hazard_math / fairness change what a lap looks like, then re-run `godot --headless --path . -s tools/lap_stats.gd -- laps=0-9 write=1`. Forgetting is caught: where the sources are readable, `stored_verdict()` compares the scripts and refuses the file.
- **An acceptance number must measure the thing that can break.** "Zero drift during stance" was true and useless -- nothing in it said how far a planted foot could be from its hip.
- Run every Godot tool through a kill switch: a script error makes a `-s` tool spin for ever and there is no `timeout` on this Mac.

### Open, Milko's calls
`SHIELD_COST` 30 · lap 7 still clears 5 bars at 24 passes · the audio encoder -- **conditional permission already given: ONLY if he says the ogg sounds worse than the mp3 may I `brew install ffmpeg` for libvorbis and re-cut the same file at quality 6** · the human bot's blind spots at run bars 63 / 77 · whether rotation resizes the canvas (still unmeasured).

### Not to be started without him saying so
Anything past section 8 (the share / roast screen, skins, prizes) · brief 5 section 6 · anything in brief 6 beyond sections 1+2 · any Stage-1 tuning beyond what he asks for.

**ON HOLD / superseded:** level-1 orbiter tuning (he called the pace right), the level-6 verdict cache (replaced by `levels/verdicts.json`).

**Models in `assets/models/`:** unchanged (creature; five hazard props with vertex colours from the bake; two buildings + their `_hi` copies, geometry only).

### Reference: the phone build and its dev switches (`https://172.20.10.2:8443`, reload fully)
The build opens into the MAIN MENU; PLAY loads the run. A dev switch in the URL skips the menu. `?level=N` goes to one old level instead (the fixed spot for frame numbers), `?scale=X` overrides the render scale, `?autoplay=1&live=1` lets the bot play with every lap generated live, `?grad=1` plays as a graduated player. All dev-only, behind the same switch as the readout.
- A first run as a new player: lap 0 is level 1 as he knows it (no lives). Crossing into lap 1 (`STAGE 2`, ~2.5 min) graduates him: 3 lives from then on, and lap 0 stops teaching.
- **The seam by ear** at ~2:29 of music (bar 73 -> bar 1). If it clicks, `LOOP_END_BAR` moves to another 8-bar boundary and `tools/make_endless_audio.py <bar>` re-cuts the file.
- Notes charge the ring right of the distance; full = a cyan bubble that absorbs one hit. `SHIELD_COST` 30.
- Three deaths as a graduated player: the end screen, RETRY (4 s run-up), MENU (= the dev level select).
- Readout: `frame ... cpu ... audio +-N (+-M)`; under it the gold load line `page - tap - load [steps]`.

### Screenshots worth knowing about
`docs/screenshots/m-body-front|side|below.png` (the melt), `m-walk-cycle.png` (eight stills across one stride), `m-walk-game.png`, `m-jump-tuck.png`, `m-idle-feet.png`, `m-legs-before-after.png` (brief 5B, the same instant of the same stride at the game camera's angle).


### Brief 5A + 5B, after Milko's phone test rejected the walk (2026-09-21)

**He was right about the bug and about the test.** "Zero drift during stance" was true and measured the wrong thing: nothing said how far a planted foot could be from its hip, so a foot could be perfectly still and still be nowhere near the leg drawn to it.

**A -- the leash.** The invariant is now `distance(foot, hip) <= LEG_H * LEG_STRETCH_MAX`, checked on the hip and foot the capsule is actually drawn between. A planted foot that reaches LEASH_STEP of it takes its step NOW; anything left over is pulled in, and a foot that has to be pulled in stops being called planted, so the no-slide claim is not quietly bent. Landing re-plants both feet under the body.

**Three real bugs were behind what he saw**, none of which the old test could have caught:
1. The old "stranded" check allowed `LEG_H * 2.0` = 1.04 units against a leg that could span 0.75, measured only horizontally, and TELEPORTED the foot instead of stepping it.
2. **A corrective step froze the other foot.** The settle returned out of the whole cycle, so while one foot stepped home the other stayed nailed to the world while the body walked away from it. Over a clean bot run that reached 9.9 units.
3. `TELEPORT_UNITS` was 2.0. The creature really travels 5.9 units a second, which is 0.10 a frame -- so a yank of a whole unit sailed under the threshold and was walked off as if it were a step.

Plus a self-inflicted one: the first leash trigger sat INSIDE the normal gait (a foot plants 0.63 from its hip; the trigger was 0.62), so every plant re-triggered a step and the stance count tripled, 45 -> 104 in 8 s.

**And the bob turned out to cost leg.** The hip rides on the body, so `BODY_BOB * HEIGHT` = 0.20 units is 0.20 of leg spent on height before the foot can reach forward at all -- and 5B makes the bob bigger on purpose. `LEG_STRETCH_MAX` went 1.45 -> 1.8 to pay for it, and the stride is now capped per frame by how much leg is left after the CURRENT hip height.

| measured at 60 fps, on the hip and foot as drawn | drift in stance | foot-to-hip | reach |
|---|---|---|---|
| walk rig, 3.9 u/s | 0.000000 | 0.7982 | 1.1160 |
| walk rig, 5.9 u/s (the real game's speed) | 0.000000 | 0.8288 | 1.1160 |
| walk rig, turning at 5.9 u/s | 0.000000 | 0.9140 | 1.1160 |
| validator bot, level 1, no deaths | - | **1.1160 (clamped)** | 1.1160 |

**Honest about the last row.** In the rig the gait never needs the clamp. In the real game it does: the unclamped worst is about 2.5 units, so something there still throws a foot further than the walk does, and the clamp is what keeps it attached. I chased it a long way and did not isolate it -- what I ruled out: the plant itself (feet land a healthy 0.66-0.76 from the hip, measured at the moment of planting), the pose order (running the cycle after the pose changed nothing), and the start-of-run teleport (excluded from the measurement; it was the 9.9). **What this means in practice: a foot can never be drawn detached, but at speed it may be dragged into place rather than stepping cleanly.** Milko's eyes on the phone decide whether that reads.

**B -- readability from the game camera.** Legs thicker (0.34 -> 0.50 wide), set wider apart (HIP_WIDTH 0.46 -> 0.60) so they clear the body's silhouette instead of hiding under it, darker (8 % -> 22 % below the body's median), bob 0.05 -> 0.085 of HEIGHT and the footfall squash 0.04 -> 0.065. "Longer" is not free: the visible part of a leg is the gap between the belly and the floor, so the section-1 cap was raised from -0.620 to -0.575 (0.390 -> 0.445 above the floor, 14 % more leg). Re-checked: 2 556 vertices lifted, every one still inside the stub box.

`docs/screenshots/m-legs-before-after.png` is the pair, the same instant of the same stride (t=2.42, phase 0.123, same foot down) at the game camera's own angle, lens and distance.

**And an honest verdict on it: the improvement is modest.** At game distance the whole creature is about 105 pixels tall and a leg is ten of them, so thickening it 50 % moves it from nearly invisible to barely visible. What will actually sell contact is the thing Milko already suspected -- a shadow under the feet (brief 6 section 2), scoped below.

### Phase A brief 5, sections 2-5 -- the creature walks (2026-09-21)

`rules.gd` and `player3d.gd` are untouched, and so are `fairness.gd`, `placement.gd`, `hazard_math.gd`, `lap_gen.gd` and every level file. The only game file besides `creature.gd` is one line in `track_test.gd` adding the dust emitter to the prewarm list. **Section 6 (the tail) is NOT done -- it needs Milko's call, see below.**

**The no-slide number: MAX FOOT DRIFT DURING STANCE = 0.000000 units**, walking straight, turning and strafing (`tools/shot_walk.gd -- slide=1`, 45 stances each). Not "small": zero, and zero by construction -- nothing in the stance branch writes the foot's position at all.

Screenshots: `docs/screenshots/m-walk-cycle.png` (eight stills across one stride, sampled by PHASE so it really is one stride end to end), `m-walk-game.png` (the game camera), `m-jump-tuck.png`, `m-idle-feet.png`.

**How it works.** The cycle is driven by DISTANCE TRAVELLED, never by a timer. A planted foot does not move while it is planted, and standing still cannot run the cycle because standing still covers no distance. Two consequences fall out for free: the hit-stop needs no special case (a frozen world moves the player nowhere, so the legs hold by themselves), and the creature can never moonwalk.

**Measured, then sized to fit.** The brief's starting numbers do not close on this model, and the rig says why:

| | brief | built | why |
|---|---|---|---|
| ground speed at full input | assumed | **3.9 units/s** | measured in the real game |
| stride at full speed | 1.8 | **1.4** | gives 2.8 cycles/s = **5.6 footfalls/s**, the "fast scurry" asked for |
| plant point | half a stride ahead of the hip | **a quarter** | a foot is planted for half the cycle and the body covers half a stride in that time, so a quarter ahead is what sits it symmetrically about its hip. Half would put the foot always in front and never behind |
| leg / hip height | 0.42 / at the belly | **0.52 / 0.52** | at full speed the foot ends 0.44 from its hip; a 0.42 leg from a 0.44 hip has to span 0.68 = 1.6 rest lengths, and the capsule visibly comes off the body |
| stretch clamp | 1.3 | **1.45** | a safety net now, not a working limit: the gait needs 1.31 and never reaches it |

**Two bugs the rig caught, both from the cycle being distance-driven:**
- **A corrective step could never finish.** Stopping is when the feet tidy up under the hips -- but the step that takes them there was driven by distance, and a stopped creature has none. The foot hung in mid-air for ever. The settle now runs on its own 0.18 s clock.
- **The parked cycle fought the settle.** With the phase frozen, the stride loop kept dragging the swinging foot back onto its arc and undid the corrective step the moment it finished. Standing still now PARKS the cycle instead of merely stalling it.

**Acceptance:** layout hashes of levels 1-6 **identical** (`4db8f95b…`, `55a53537…`, `ac320116…`, `5701d3f6…`, `70ba1a40…`, `489da92b…`) · **validator bot deaths=0** both on level 1 (`level=1 fps=60`) and across laps 0-2 of the endless run (`endless=1 laps=3 fps=60`, min_fps 59) · at bar 2 of level 1 the frame carries **8 more draw calls** than before the brief (two legs and the dust emitter) and slightly fewer triangles.

**Section 6, the tail -- Milko's call, not started.** The brief wants tail vertices pushed sideways by a damped spring. This model has no tail: it has **two rear flippers** (the same surprise as section 1, where the "arms above the equator" turned out to be four flippers below it). A z-range sway would swing both flippers together, which is a different idea from the one the brief describes and worth deciding rather than improvising.

### Phase A brief 5, section 1 -- the baked legs are melted (2026-09-21)

Screenshots: `docs/screenshots/m-body-front.png` / `-side.png` / `-below.png`, made by `tools/shot_creature.gd` (`melt=0` renders the same three with it off, for the A/B). **Section 2 (the legs) is NOT started.**

**No scar from the game camera.** From directly underneath there is a faint ghost of the two old soles -- two soft circles and a slightly ragged arc on one of them -- but the game camera looks DOWN at the creature from behind (pitch ~54 degrees) and the belly is never in view, not even mid-jump with the spin: checked on a real frame (`bar=2 level=1 jump=1`). Front and side are clean: a round one-eyed body, four flippers, a smooth underside, nothing hanging down.

**The brief's method could not work on this model, and the measurements say why.** It asked for a body ellipsoid, with everything below the equator and outside it projected back onto it. Three things the model does not do:
- **The belly IS the stubs.** Excluding them, the body has NO surface at all below y -0.547 inside a horizontal radius of 0.6. There is nothing underneath to melt onto. Any ellipsoid large enough to cover the stubs either sits above the body's real underside -- tried it, it shredded the flippers, the tearing is what a hard per-vertex rule does at its own boundary -- or passes below the stubs and shortens them by 17 %, which is invisible.
- **The model has SIX limbs**, not two: two front flippers, two rear flippers, two leg stubs.
- **The flippers hang BELOW the equator** (y -0.475..-0.031; the fitted equator is y 0.027), so the brief's "the arms sit above the equator, exclude the tail by its z range" does not hold: a plain below-the-equator rule reaches every limb the creature has.

**What was built instead** (same idea, different surface): a **cap** is closed over the stubs -- a dome that meets the body's real underside exactly where the stubs end, so there is no boundary to tear, and domes gently down from there. Solved from three measurements, not chosen:

| measured | |
|---|---|
| the stubs live inside horizontal radius | **0.62** of (x 0.0, z 0.065) |
| the body's real underside at that radius | **y -0.517** |
| the new belly bottoms out at | **y -0.620** (the stubs reached -0.938) |
| -> cap ellipsoid | centre y **-0.340**, y radius **0.280**, horizontal radius **0.800** |

A vertex inside that radius and below the cap is lifted onto it, and its normal is set to the dome's, so the shading has no seam either. Checked against all 26 769 vertices of the mesh: **2 510 are lifted (median 0.150, max 0.373 units) and every one of them is inside the stub box** -- not one body or flipper vertex moves. That is what makes it seamless, and it is a property that can be re-checked rather than eyeballed.

The GLB is untouched, as the brief requires; `MELT_ON := false` in `creature.gd` turns the whole thing off. **Milko's call still stands open**: if he wants the ghost on the underside gone rather than merely unseen, the brief's fallback is a regenerated body-only model.

### What those four commits were (2026-09-21, all now confirmed on the phone)

1. **The verdict fingerprint an export can match** (`4d7e9f4`). `LapGen.source_hash()` no longer md5s the layout SCRIPTS -- an export ships them compiled (`placement.gdc`), so that hash could never match the one `lap_stats.gd` stamped from the readable sources, and every device rejected `levels/verdicts.json` and validated every lap live. It is now `LAYOUT_VERSION` + `Fairness.VERSION` + the two JSON data files (the only things shipped byte for byte). **Bump `LapGen.LAYOUT_VERSION` whenever placement / rules / hazard_math / fairness change what a lap looks like, then re-run `tools/lap_stats.gd -- laps=0-9 write=1`** -- and forgetting is caught, not trusted to memory: where the sources are readable (the editor and every tool, i.e. everywhere a verdict is made) `stored_verdict()` also compares the scripts and refuses the file if they moved without a bump. Verified both ways: `FROM shipped` on every lap tested and `validate 0.0 (cached)` on the load line; tampering the recorded script hash makes it refuse and fall back to live. The regenerated file is byte-identical except the fingerprint.
2. **LOADING is said under the rotate prompt** (`bd79823`). `ui.gd` gained one optional line (`portrait_note`) drawn below ROTATE YOUR PHONE; `track_test` sets and clears it. **The glass controls cannot be touched by this**: the portrait branch of `_draw()` returns before the HUD and the controls are drawn at all.
3. **The drift gate measures the change, not the raw gap** (`115eef3`). `DRIFT_IGNORE_S` tested the absolute number, so the phone's constant -1374 ms tripped it every frame and the correction was off on the only device it is for. Now gated against the settled baseline, as its own comment always claimed.
4. **GPU step 1b: cheap pillar copies** (see below).

### GPU step 1b -- measured, before / after at level 1 bar 11

| | before | after |
|---|---|---|
| gate pillars | 37 meshes, **148 000** triangles | 37 meshes, **42 916** |
| in the frame | 130 660 triangles, 331 draw calls | **87 958 triangles, 171 draw calls** |

Only `i == 0` -- the pillar forming the edge of the opening, the one whose inner face IS the gap -- keeps the full model. Everything further out is wall and gets a cheap copy: **108 triangles instead of about 4 000**, and the draw calls roughly halve as a bonus.

The copy is not modelled or guessed, it is **measured from the real mesh at load** (`Props.low_mesh`): for each of 7 heights it takes the model's own vertices near that height and asks how far the shape reaches in each of 8 directions, then intersects those to get one convex ring that hugs the real cross-section. Stacking the rings gives the real silhouette, faceted. Vertex colours come from the same vertices, so it keeps the bake's colouring and needs **no new material -- nothing to add to `prewarm.gd`**. If the art is replaced it needs no attention.

Why not Godot's own mesh LOD: `generate_lods=true` is on in the `.import`, but mesh LOD does not run in the **Compatibility** renderer, which is what the web build uses. Another "works here, does nothing on the phone" trap.

**Known, not fixed: `tools/shot.gd` is flaky now that loads are fast.** Its clock and the run's clock disagree after a cached load, so it can report `bar=11` while the run is at bar 0, and it used to save a black LOADING frame. It now refuses to save unless the world is actually up (`state == RUN`), which stops the black frames; the wrong-bar mismatch is untouched and older than today. The triangle figures above are safe from it -- they are counted by walking the scene, not read off a frame.

### The three findings from that test (all now fixed above; kept for the diagnosis)

1. **The shipped verdicts can never be trusted in an exported build.** `LapGen.source_hash()` md5s four `.gd` files; the exporter ships them COMPILED (`placement.gdc` is in the pck next to the name `placement.gd`, `script_export_mode=2`). So the hash the phone computes can never equal the hash `tools/lap_stats.gd` stamped into `levels/verdicts.json` from the readable sources -- the file is rejected on every device and every lap validates live. **That is 4.6 s of the 6.5 s load**, and the live result was identical to the shipped one (1 pass, 0 cleared). The check itself is correct and must not be weakened (a stale verdict = an unproven lap). Fix: fingerprint what survives export -- the two JSON data files (verified byte-identical in the pck) + a hand-bumped layout version, with `lap_stats.gd` failing loudly if the scripts changed without a bump. On the Mac the hash matches (`ec646cf3540a`), which is why nothing ever caught it -- another instance of the standing rule: **a path that only runs in an export has been tested by nothing here.**
2. **The LOADING word is on screen but nowhere near the eye.** Nothing covers it: `ui.gd`'s portrait branch draws only two lines of text and returns, and `Status` is a sibling label that draws after it. But ROTATE YOUR PHONE is big, cyan and centred while LOADING is small, gold and 70 px from the top edge -- and the whole 6.5 s ran in portrait (the load line recorded 1179x2379). Fix: say it under the rotate message, where the eye already is. **That edits `ui/ui.gd` = the glass-controls file, so it needs Milko's go-ahead** (one line inside the portrait branch, nothing near the controls).
3. **The drift correction is switched OFF on the phone, silently.** `audio -1374` is the device's CONSTANT reported offset and is meant to be ignored (SYNC_OFFSET_S was tuned by ear on top of whatever the device reports) -- that part is by design, and is why nothing sounded wrong. But `DRIFT_IGNORE_S` (0.25 s, "a gap this big is a glitch, not drift") tests the RAW gap, not the change since the baseline, so 1.374 s trips it on every frame and `_follow_audio` returns before correcting anything (`(+0)` confirms it). The thing it protects against -- audio slipping over a long deathless run -- is exactly what an endless run is. On the Mac the offset is 15-60 ms, so the gate never fired here. Fix: gate on `d - _drift_base`, one line.

## Earlier phases — moved out

Everything before the current phase now lives in **`docs/PHASE_LOG.md`**: the GPU and
load instrument job, the Phase E endless-run report, the frame-meter / "screen jumps"
report, Phase A briefs 1-4, and the addendum-4 overnight report. This file is the
current snapshot; that one is the history.


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
| `frame_meter.gd` | dev-only frame-time readout + the FRAME log line (`FrameMeter.note()`) |
| `prewarm.gd` | draws every material once behind TAP TO START so no shader compiles mid-run |
| `../tools/frame_probe.gd` | measures hitches, camera steps and clock evenness with the validator bot: `godot --path . --resolution 1200x540 --rendering-method gl_compatibility -s tools/frame_probe.gd -- level=1 bars=22` |

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
