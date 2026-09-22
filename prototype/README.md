# Phase R prototype — "an album you survive"

## Where we are (2026-09-22) — start here

**The game is ONE ENDLESS RUN** (`PHASE_E_BRIEF_1_ENDLESS.md`): how far can you get. **Stage 1 (the run) is built and accepted. Stage 2 (menu + leaderboard) is NOT started and must not be started until Milko says so.** Everything below is newest first; this section is the whole state, the rest is the detail behind it.

### Where the work stands

| | |
|---|---|
| Performance | **DONE and closed.** The phone holds 60 fps. |
| Phase A brief 5 (the walk) | **Sections 1-5 done**, accepted by Milko "for now" on 2026-09-21. Pushed: `25a2445`, `fe2e784`, `8ff427b`, `f460f67`. |
| Brief 5 section 6 (the tail) | **SKIPPED on purpose.** This model has no tail, it has two rear flippers, so the brief's z-range sway would swing both together. Milko: handle it when the model is regenerated. |
| Brief 6 (light) | Not started. Sections 1+2 are the agreed next build. |

### KNOWN ISSUE — a foot can still be dragged in the real game

The leash (brief 5A) guarantees `distance(foot, hip) <= LEG_H * LEG_STRETCH_MAX` on the hip and foot the capsule is actually drawn between, so **a foot can never be drawn detached from the body again**. In the walk rig the gait never even reaches the clamp (0.83 of 1.12 at the real game's speed, 0.91 turning).

**But in the real game the clamp is active**: something throws a foot to about **2.5 units** from its hip, and the clamp is what pulls it back to 1.116. The visible result is a foot that is *dragged* into place rather than stepping cleanly at speed. Milko accepted the legs with this known.

**Already ruled out — do not re-check these:**
- **The plant itself.** Measured at the moment of planting, feet land a healthy **0.66-0.76** from the hip. The gait is not what is wrong.
- **The pose order.** The step cycle used to run before the body pose, so it read last frame's hip while the legs were drawn against this one. Moving `_step_cycle` to after the pose changed the number not at all.
- **The start-of-run teleport.** The player is placed at z=10 after the creature has posed, which reads as 9.9 units on the first frame. That frame is now excluded from the measurement (`_ported`), and it was the whole of the old 9.9 reading.
- **Three bugs that WERE real and are fixed**: the old stranded check allowed 1.04 units against a 0.75 leg and teleported instead of stepping; a corrective step froze the OTHER foot while the body walked away from it; and `TELEPORT_UNITS` was 2.0 when a real frame moves 0.10, so a one-unit yank was walked off as a stride.

**How to measure it:** `tools/autoplay.gd -- level=1 fps=60` prints a `LEASH` line over a clean, death-free run (max as drawn, planted, and the unclamped worst). `tools/shot_walk.gd -- slide=1 dir=forward|turn|strafe [jump=1] [speed=1.5]` is the rig version and is the reliable instrument; `tools/shot.gd` prints `LEASH` too but its captures are flaky (see below).

### NEXT, in this order

1. **A read-only code health check.** Nothing built. `prototype/creature.gd` has roughly doubled over briefs 5 and 5A/B and carries several interacting timers (the stride phase, the settle clock, the leash, the tuck), which is where the known issue above is hiding.
2. **Brief 6 sections 1 + 2 as ONE slice** (`PHASE_A_BRIEF_6_LIGHT.md`): one light direction published as a global uniform, then drop shadows, **creature first** (body + both feet), hazards after. Taking section 1 with it avoids hardcoding a light direction and then reworking it.
   - **Cost: zero net draw calls.** All shadows go in one `MultiMeshInstance3D` -- one call however many casters -- and it REPLACES the blob the creature already draws under itself (`_ring` in `creature.gd`). The real cost is fill rate (transparent quads), a fraction of a percent of the frame at bar 11.
   - **Why it is next and not more leg tuning:** "it floats" is a contact problem. At game distance the whole creature is about 105 px tall and a leg is ten of them, so no amount of thickening solves what a shadow solves directly.

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
Stage 2 (menu + leaderboard) · brief 5 section 6 · anything in brief 6 beyond sections 1+2 · any Stage-1 tuning beyond what he asks for.

**ON HOLD / superseded:** level-1 orbiter tuning (he called the pace right), the level-6 verdict cache (replaced by `levels/verdicts.json`).

**Models in `assets/models/`:** unchanged (creature; five hazard props with vertex colours from the bake; two buildings + their `_hi` copies, geometry only).

### Reference: the phone build and its dev switches (`https://172.20.10.2:8443`, reload fully)
The build opens straight into the run. `?level=N` goes to one old level instead (the fixed spot for frame numbers), `?scale=X` overrides the render scale, `?autoplay=1&live=1` lets the bot play with every lap generated live, `?grad=1` plays as a graduated player. All dev-only, behind the same switch as the readout.
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
