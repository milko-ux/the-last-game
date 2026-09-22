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

## GPU + load instrument job (2026-09-20, night — step 1a ANSWERED by the 2026-09-21 phone test above)

iPhone, build c1fe875, level 1 bar 11 (~22 gate pillars + big near monoliths): **frame 28.7 avg / 36 worst ms with cpu 2.5 ms; quiet moments 16.7 / 18, cpu 0.3-1.3. GPU-bound.** Steps, ONE at a time, each read at the same spot: `https://172.20.10.2:8443/?level=1` (dev switch: straight into level 1), bar 11.

- **1a — DONE, exported (`543a8fa`): 3D render scale 0.75 on web / mobile** (`track_test.RENDER_SCALE_MOBILE`, `viewport.scaling_3d_scale`). The web (Compatibility) renderer supports it — checked with a 0.3 test: the 3D went blocky, 2D text stayed sharp. It has NO canvas pixel-ratio cap (Godot's web export only knows hi-DPI on / off), and a cap would blur the glass controls; 3D scale leaves HUD + controls at full resolution. The phone's canvas is 3 device pixels per point; 0.75 = 56 % of the 3D pixels. `?scale=1` = the old number, `?scale=0.6` = harsher. The load line ends with `3D 0.75 of W x H`. Visual cost: slightly rougher silhouettes at a 1:1 crop (`docs/screenshots/g1a-bar11-scale-1.0.png` / `-0.75.png`), not visible at phone size in my judgement — Milko's eyes decide.
- **1b — measured, NOT built (waits for the 1a number):** triangles in frame at bar 11 by kind (`tools/shot.gd` now prints `BUDGET` lines): **gate pillars 37 meshes = 148 000** · monoliths 19 = 69 880 · creature 30 040 · tiles 2 880. Plan if needed: a light pillar copy (~600-1 000 triangles) for every pillar but the two next to the opening.
- **1c — not started:** monolith shader (fewer noise octaves, or the baked 512 px noise tile).
- **REGRESSION, found and fixed the same night (`0e733e5`): the iPhone hung on LOADING.** Symptoms: LOADING for ever, gold line `page - · tap - · load -` (all three empty), frame meter frozen at `— ms`, the canvas stuck at a portrait 1179 x 2085 even in landscape, ROTATE YOUR PHONE on top. Cause: `e66adf3` called `FrameMeter.first_frame_painted()` from inside the `RenderingServer.frame_post_draw` callbacks, and ITS WEB BRANCH read the page clock through `JavaScriptBridge.eval()` — the one line of the whole instrument that a Mac never executes (`OS.has_feature("web")` is false here), so every test took the other path. Two verified faults: **an error inside a `frame_post_draw` callback aborts the rest of that callback**, so the next line (`_painted += 1`) never ran; and **`float()` of a Nil raises** ("Nonexistent 'float' constructor") if eval ever returns nothing. The counter froze at 0 and the gate waited on a number that could no longer grow; the frozen canvas and dead readout say the engine stopped there too. **The rotate overlay is not involved** — `ui.portrait()` only draws text and returns, nothing in the project pauses the tree or the render loop, and a 590x1050 window shows ROTATE YOUR PHONE while still loading through to TAP TO START. Fixed: render callbacks do nothing but count; the page clock is read from `_process`, `typeof`-guarded; and **`FrameMeter.LABEL_TIMEOUT_MS` = 2000 — every wait for a painted frame carries on anyway after 2 s, warns, and marks the line `TIMED OUT`**. That ceiling is now the rule for both gates: a wait that can never end is the bug class, not just this instance. Proved by simulating the phone (painted-frame callback disconnected): released after 2184 ms instead of never. **Lesson for anything web-only: a branch behind `OS.has_feature("web")` has never been tested by anything I can run here.**
- **2 — DONE (`e66adf3`): the load instrument.** Reset on every load; three spans on the gold line: `page` (page opened → first painted frame; the browser's clock, so it covers download + engine start) · `tap` (tap → first PAINTED frame of the loading label) · `load` (that label → TAP TO START, steps in brackets). What was wrong before: a RETRY / reload never reset the log (so "scene 72.9 s" was play time and the line appended), and the label was shown but the blocking scene change could start before the browser had painted it. Now the level select waits for `frame_post_draw` (label drawn + one more frame) before it changes scene, and the run scene does nothing heavy in `_ready`: the level path's validation + field build runs after ITS label has been painted. The page itself now shows `LOADING 43 %` → `STARTING` while it downloads (head_include script reading the engine's progress element). **Which span is the long one: Milko's phone has to say** — my expectation: `page` on a first visit (42 MB), and on the dev level path `load [validate NOT cached]`.


## Phase E report — brief 1, the endless run (Stage 1 done, 2026-09-20)

### Section 1 — knobs per lap, not per game (done)
Nothing reads "the current level's knobs" from a global any more. The knob dictionary (one row of `levels/curriculum.json`, `Rules.level(n)`) is an ARGUMENT everywhere: `Placement.build(clock, rerolls, knobs)`, `Fairness.validate(plan, clock, knobs)`, `Rules.plate_state(entry, col, row, t, k)`, every `Rules.*` knob accessor (`period_beats(k)`, `gate_gap(k)`, `sweep_gap(k)`, `player_speed(k)`, `window_depth(k)`, `reach_per_beat(k)`, `lives(k)`, …), every `HazardMath.*` function (`boxes_at(spec, t, k)` …). `BeatClock.period_beats` is gone: the period functions take the period (`period_index_at(t, pb)` …). A `field` carries the knobs it was built with (`field.knobs`), its hazards get them in `setup(spec, knobs)`, the death rules read `field.knobs`, the player reads its speed from the field it runs on, the camera gets its window in `configure(knobs)`, the bots read `test.knobs`. The plan itself is unchanged (the knobs travel beside it, not inside it), which is what makes the proof below possible. `Rules.LEVEL` survives only as the dev path's pick, read once in `track_test._ready`; the level select → one level path works as before.

**Proof it changed nothing** — `tools/plan_stats.gd` now prints a `HASH` per level: SHA-256 of the whole generated plan + the re-rolls it settled on (keys sorted, floats at full precision). Before the refactor / after it:

| Level | before | after |
|---|---|---|
| 1 | `4db8f95bfc951cd4…56f69f13` | `4db8f95bfc951cd4…56f69f13` |
| 2 | `55a5353726793008…a60ecae6` | `55a5353726793008…a60ecae6` |
| 3 | `ac3201169bc89ebb…d79d2598` | `ac3201169bc89ebb…d79d2598` |
| 4 | `5701d3f65f7726b9…acbfa171` | `5701d3f65f7726b9…acbfa171` |
| 5 | `70ba1a404f2d6cf2…fc2da460` | `70ba1a404f2d6cf2…fc2da460` |
| 6 | `489da92bba732302…c3be3c0f` | `489da92bba732302…c3be3c0f` |

Identical, as are the validation pass counts (1, 3, 3, 7, 8, 35) and the re-roll tables. Runtime: validator bot **0 deaths, goal reached on levels 1, 3, 5**; a bar-1 frame before / after: same 145 384 triangles, 326 draw calls, 0.06 % of pixels differ (the creature's idle, 10 ms apart).


### Section 2 — the song loops (done)
- **Audio:** `assets/audio/fuffens_endless.ogg` = the track cut at bar 73's downbeat (165.581 s), made by `python3 tools/make_endless_audio.py [end_bar]` (reads the bar time from the beatmap, so moving `LOOP_END_BAR` = re-run it with the new bar). Loop on, loop offset 16.602 s (in the `.import` file, and set again at runtime from BeatClock's constants). **Encoder note:** this Mac's ffmpeg has no libvorbis, so the script used ffmpeg's built-in Vorbis encoder; measured against the source: sample-aligned, SNR 33.9 dB, spectrum intact to 16 kHz (−1.6 dB above), 22 samples (0.5 ms) of end padding. If Milko hears it, the same cut from the DAW replaces the file, nothing else changes.
- **Clock:** `BeatClock.set_endless(true)`; `LOOP_START_BAR` 1, `LOOP_END_BAR` 73 → 72 bars, 288 beats, 148.979 s. `song_time()` (alias `run_time()`) is the smoothed system clock from the glitch fix and simply keeps growing; the audio loops by itself, so there is no wrap to detect — `lap_at(t) = floor((t − loop start) / loop length)`. Every time-taking function folds run time into the loop, so numbers keep counting: run bar = lap × 72 + bar (`bar_at`, `bar_start`, `bar_energy` …), run beat = lap × 288 + beat (`beat_at`, `beat_time`, `period_*`). `z_at(t)` grows for ever, measured from a fixed origin (`ENDLESS_Z_ORIGIN_S` 8.0) so the course sits at the same z after a short retry run-up. `seek(t)` sends the audio to the place inside the loop and the clock (hence the lap) to `t`. With `endless` off nothing changes (level hashes 1-5 re-checked: identical).
- **`prototype/lap_clock.gd`:** one lap seen as a level (bars 1..72, absolute times and z) — what the generator, the validator and the field get handed in section 3.
- **Test:** `godot --headless --path . -s tools/clock_test.gd` → `COUNTING 46054 samples over 3 laps: ok` (beat / bar / period indices step only by 0 or +1, every time inside the bar, beat and period it is given, lap 1's beats = lap 0's + one loop) · `SEAM into lap 1: 289 frames, run_time step min 6.55 ms max 7.50 ms (at most 1.01 frames' worth), negative steps 0` · rewind lap 1 → lap 0 → lap 3 follows in lap, audio place and z · `CLOCK TEST PASS`. BeatClock prints that SEAM line at every seam of a real run too.

### Section 3 — the course, lap by lap (done)
- **Band / seed / lap 0** (`prototype/lap_gen.gd`): lap k uses band `min(k + 1, 30)`; `SEASON_SEED` 20260901 + lap seeds the layout (`knobs["seed"]`, read by `placement.gd` instead of the level number). Lap 0 for a new player = level 1's curriculum, bars 1-72, its own seed: **untouched** (72 hazards, fair in 1 pass, as level 1). Lap 0 for a graduated player = band 1, `structure` mixed, no demo bars. `Progress.graduated` is set and saved the first time a run crosses into lap 1. Later bands keep their demo bars as the data says.
- **Bar 1 of every later lap** is plain, with a checkpoint and the word `STAGE n` (`knobs["plain_bar1"]`). The validator starts such a lap FROM that bar (not from "any safe tile", which could be two bars in): the lap is proven fair from where the player really stands at the seam and after a rewind.
- **Fair or easier, never stuck:** generate → validate → re-roll, up to the band's `reroll_passes`; bars still unfair after that are cleared to open floor and logged (`LAPGEN lap N: bar B … cleared`), and validation runs again; every round clears at least one bar. **Bands 4 and 5 got `reroll_passes` 24** in `levels/curriculum.json` (they cleared 6 and 3 bars at 10; levels 4-5 themselves settle in 7-8 passes, hashes unchanged).
- **Resumable everything.** `Placement.begin / step / finish` (one bar per step), `Fairness.begin / step(budget) / finish` (unit = one beat's safe set, then one tile's reachability search), `LapGen.begin / step(budget)`, `field.build_step(budget)` (one bar's tiles / one hazard / one 64-unit strip of monoliths per item). `build()` / `validate()` are those in a row and give the same result: level hashes 1-5 re-checked identical after each change. **A new pass resumes from 5 bars before the first changed bar** (`Fairness.begin_from`, per-bar snapshots): a re-roll only changes that bar and later ones. Proven equal to walking the whole lap: laps 0-5, same passes, cleared bars and hashes with `incremental=0`.
- **Live generation:** the next lap starts generating the moment a lap begins, `GEN_BUDGET_USEC` 2000 per frame (generation, then node building, share it); forced at bar 68 (`LapGen.force_finish`: unvalidated + failing bars cleared, never a stall). Measured on the Mac: slicing adds no overhead (6.56 s sliced vs 6.59 s straight for lap 1), worst slice 4.8 ms. Caveat found: in the headless bot the same work took ~4x the CPU time, because the OS parks 2 ms bursts on slow cores; a phone will do the same — which is what the shipped verdicts are for.
- **Shipped verdicts:** `levels/verdicts.json`, made by `godot --headless --path . -s tools/lap_stats.gd -- laps=0-9 write=1` (both lap-0 variants; carries a hash of placement / rules / hazard_math / fairness / curriculum / beatmap and is ignored when that does not match; then the per-device cache, then live). With it a lap costs only its placement.

| Lap | band | generate + validate (Mac) | passes | bars cleared | hazards | notes |
|---|---|---|---|---|---|---|
| 0 new | 1 | 1.9 s | 1 | 0 | 72 | 40 |
| 0 graduated | 1 | 1.9 s | 1 | 0 | 53 | 34 |
| 1 | 2 | 6.7 s | 4 | 0 | 73 | 33 |
| 2 | 3 | 3.7 s | 4 | 0 | 62 | 36 |
| 3 | 4 | 23.4 s | 18 | 0 | 55 | 32 |
| 4 | 5 | 21.4 s | 15 | 0 | 53 | 35 |
| 5 | 6 | 18.0 s | 9 | 0 | 61 | 36 |
| 6 | 7 | 39.0 s | 18 | 0 (was 9 at 10 passes) | 52 | 24 |
| 7 | 8 | 30.2 s | 24 | **5** [62, 63, 66, 67, 68] (was 7) | 52 | 29 |
| 8 | 9 | 16.7 s | 10 | 0 | 60 | 30 |
| 9 | 10 | 24.3 s | 15 | 0 (was 5) | 59 | 26 |

Laps 0-5: 0 cleared (target ≤ 2). **2026-09-20, late: `reroll_passes` 24 on bands 7-10 (Milko), verdicts regenerated** — cleared bars per lap before → after: lap 6 9 → 0 · lap 7 7 → 5 · lap 8 0 → 0 · lap 9 5 → 0; laps 0-5 unchanged (same lap hashes), level hashes 1-6 unchanged. Band 6 was left at its 40 (level 6 needs 35 passes; 24 would have lowered it). Lap 7 still runs out at 24 passes around bars 62-68.
- **Nodes:** `field.gd` holds a rolling set of laps under run-wide bar numbers (the dev level is "one lap of 78 bars", built in one go). Lap k−1 is freed once the death line is 3 bars into lap k (monoliths with it); a later lap carries a hidden 12-unit lead-in slab that shows when the lap behind it goes, so a rewind to its bar-1 checkpoint never looks into a void. Hazards are posed only near the window now (`field.update_hazards`: −14 … +52 units) instead of every hazard of the level every frame.
- **Window / camera between bands:** `track_test._window_depth_at` eases 2.5 → 2.2 bars over the new lap's first two bars; the camera distance follows (`rig.set_window_depth`).
- **Entry:** the Phase R main scene is the run (`track_test.tscn`, `Rules.ENDLESS`); the level select is the dev tool (its ENDLESS RUN pill, or pick a level = the old path). Tools: `endless=1 [laps=N grad=1 start_lap=N]`.
- **Validator bot:** see the acceptance table below.

### Section 4 — lives and death (done)
`rules.gd` untouched; `track_test.gd` is the referee. Graduated: `RUN_LIVES` 3 for the whole run; a death = lose one, the freeze, the song rewinds to the last checkpoint (what levels 2+ do); none left = the run is over. New player: lap 0 costs no lives (level 1's rules, 0.25 s freeze); they start at 3 on crossing into lap 1 (the same moment `Progress.graduated` is saved). RETRY: `RETRY_RUNUP_S` 4.0 — the song starts at 12.6 s instead of 8.0 s (`runs_this_session`, a static, so the first run of a session keeps the full run-up); z is measured from a fixed origin, so the course does not move. The band's own `lives` knob is ignored in the run. Every rewind logs `REWIND t=… lap=… bar=… audio=… checkpoint_bar=…`. Bots: no lives unless `lives=1`. Checked: a graduated bot that stands still dies three times (the two rewinds land at the start) and the run ends.

### Section 5 — distance, and what notes are for now (done)
- **Distance:** `distance_m = floor(furthest z the player reached − z of bar 1's start line)`; never goes down (a rewind takes nothing away). `Progress.best_distance` per `SEASON_SEED`, saved at every death, at the end of the run and on leaving.
- **HUD** (`docs/screenshots/e-run-hud.png`): the distance big at the top centre, `BEST 1 240 m` small under it, the lives as three glass dots left of it (hidden while lives are off), the shield meter right of it. The score, the combo readout and the song progress bar are gone in this mode; the score maths is neither shown nor stored.
- **Best line:** a thin amber line across the field at the best distance (built like the death line, `Mats.player(GOAL)`); crossing it holds `pr_rim_amber` for one bar (`motion.on_best_crossed`).
- **Shield:** each note adds the current combo (1-4) to a meter; at `SHIELD_COST` 30 the shield arms and holds (one at most). Armed, it absorbs ONE hazard or plate death — no life, no rewind, the shield pops, `SHIELD_GRACE_S` 1.0 s immune to hazards and plates. Falling and the death line always kill. Decided in `track_test._shield_takes()` after `Rules.death_cause()`; **`rules.gd` untouched**. Logged: `SHIELD absorbed <kind> at bar N, D m`.
- **Look (a visual addition, flagged):** a thin glass bubble around the creature — the existing hot-glass shader in `SAFE` cyan (`Mats.shield()`, nearly clear body, bright rim), flickering out over the grace second; the pop = the creature's clay-pop particles recoloured cyan; the HUD ring fills amber and turns cyan when armed. `palette.gd` colours only. All three are in `prewarm.gd`.
- **Notes on offer per lap** (for tuning `SHIELD_COST`): lap 0 new 40 · lap 0 graduated 34 · lap 1 33 · lap 2 36 · lap 3 32 · lap 4 35 · lap 5 36. A player who takes half (~17) and keeps a combo of 4 charges ~60 a lap = two shields; one who dies every few notes (combo back to 1) charges ~25 = a little under one. 30 sits at "about one a lap" for the second kind of player; Milko's call after playing.

### Section 6 — end screen (done, minimal)
`docs/screenshots/e-end-screen.png`: the distance big, `NEW BEST` when it is (else `BEST 1 240 m`), **RETRY** (big, cyan glass) and **MENU** (small). Drawn by `hud.gd` in the HUD's glass style over a dimmed, frozen world; the death line and the best line are hidden so nothing cuts across the buttons. RETRY = a new run with the 4 s run-up; MENU = the dev level select until Stage 2's menu exists; any key = retry. The run's summary goes to the log: `RUN OVER distance=… best=… new_best=… laps=… run_s=… deaths=… notes=… shields_used=…` (the numbers Stage 2's leaderboard entry needs). The share / roast screen is its own brief.

### Stage 1 acceptance (2026-09-20, evening)
| # | Item | Result |
|---|---|---|
| 1 | Layout hashes of levels 1-6 identical before / after | **Identical**, re-checked after every section and at the end (4db8f95b · 55a53537 · ac320116 · 5701d3f6 · 70ba1a40 · 489da92b), pass counts 1 / 3 / 3 / 7 / 8 / 35 unchanged. |
| 2 | Validator bot: 0 deaths through laps 0-5, both lap-0 variants | **0 deaths, both variants, at `fps=60`** (15 min each, `run_s` 902). At the bots' usual 30 fps both runs had ONE identical death (run bar 202 = lap 2 bar 58, a sweeper): a 4 cm graze — the plan leaves 0.19 units to the wall's edge and a 30 fps bot was 0.23 off its tile at that frame; lap 2 played from its own start at 30 fps passes that bar, and at 60 fps the whole run is clean. The bot, not the lap; judge the validator bot at `fps=60`. |
| 3 | Seam: `run_time` per-frame delta never negative, never over two frames' worth | Every seam of every run: **1.00-1.01 frames' worth at most, 0 negative steps** (30 fps: 33.0-33.9 ms; 60 fps: 16.5-16.8 ms; windowed 120 Hz: 8.26-8.36 ms). Milko judges the audio seam by ear. |
| 4 | A death in the first bars of lap 1 rewinds to lap 1's bar-1 checkpoint, in sync | `kill_bar=75`: `DEATH … bar=75` → `REWIND t=163.558 lap=0 bar=72 audio=163.558 z_back=609.08 player=(0.00, 618.00) checkpoint_bar=73`: the song goes 2.0 s before the seam (the usual checkpoint lead), audio place = clock, the player stands on lap 1's start line + 1; the bot then crossed the seam again and played lap 1 into lap 2 with no further death. |
| 5 | Live generation: no stall, worst frame under 25 ms while generating; times and cleared bars for laps 0-9 | **Native Mac, verdicts ignored (`frame_probe.gd -- endless=1 live=1 bars=147`):** lap 0 validated behind the loading bar (1 pass, 1.8 s); lap 1 live: 4 passes, 0 cleared, 6.7 s of CPU spread over 25.9 s; lap 2 live: 4 passes, 0 cleared, 3.6 s over 14.1 s; no stall, no death, **no frame over 25 ms while either lap was generating**. (Scattered 25-110 ms frames appear in every windowed run on this Mac, with or without generation, at different places each time: background load, not the game.) Times and cleared bars for laps 0-9: the table in section 3 (laps 0-5: 0 cleared; 6-9: 0 / 5 / 0 / 0 since bands 7-10 got 24 passes). **NOT done: the same on the Mac WEB build** — the Chrome extension would not connect. It is one URL for Milko instead: `https://172.20.10.2:8443/?autoplay=1&live=1` (dev switches, `track_test._dev_url_switches`): the validator bot plays, stored verdicts are ignored, and the frame / cpu readout shows whether generating costs frames in the browser. |
| 6 | Human bot, graduated, 3 lives, 20 seeds — report only | **Median distance 635 m, median run 167 s** (min 567 m / 152 s, max 636 m / 167 s); 16 of 20 reached lap 1. Killers: orbiter 29, slammer 19, gate 6, volley 4, back edge 2. The deaths pile up on the same bars for every seed (run bar 63: 20 deaths, bar 77: 19, then 73, 48, 52, 70, 74) — an identical death after every rewind is the bot's blind spot, not a verdict on the lap. One shield was used in 20 runs (the bot does not go for notes). No tuning done. |
| 7 | Export, "Where we are", stop | Done: `build/phase-r`, this file. **Stage 2 not started.** |

Found and fixed on the way: **audio drift** — on real audio the music fell 15 ms behind the clock by the first seam and 61 ms by the second (slow frames underrun the audio buffer). `BeatClock._follow_audio` now slews the clock toward the audio, low-passed, at most 2 ms per second, and only by how much the gap has CHANGED since the run / the last seek settled (the constant offset `SYNC_OFFSET_S` was tuned on stays). Measured after: +6 ms against a +14.5 ms baseline at the first seam, 37 ms slewed on the way. The dev readout shows it in a run: `audio −12 (−30)` = gap now (total slewed).

## Report — frame meter, the "screen jumps", the monoliths (2026-09-20)

**`rules.gd`, `hazard_math.gd`, `fairness.gd`, `placement.gd` untouched.** One thing under the rules did change: the clock they read is smoothed (below). Validator bot after it: **0 deaths, goal reached on levels 1, 2, 3, 4, 5** (one level-5 run died once at bar 2 while the Mac was rendering screenshots next to it, 27 fps; alone it passes — the known starved-bot pattern).

### 1. Frame meter (`prototype/frame_meter.gd`, `FrameMeter`)
Top-right: average and worst frame ms over the last 2 s. On in debug builds and while `Progress.UNLOCK_ALL`; never in the headless tools; in a release with the switch off the node is never created and every hook is one static bool test. Cost when on: one clock read + one array write per frame, text rebuilt 4x/s. Any frame over 25 ms prints
`FRAME 102.2 ms  bar=0 beat=2 t=15.53  events=[pickup burst]`
— the events are whatever noted itself that frame: beat / downbeat, gate jump, volley fire / warning line, material swaps, tile repaints, monolith detail swaps, killer flash, pickup burst, checkpoint, death, rewind (song seek), progress save; "(off-screen)" marks hazards outside the view.

### 2. The "screen jumps" — what was true
Measured with the new `tools/frame_probe.gd` (the run scene with the validator bot, like `shot.gd`; `--rendering-method gl_compatibility` = the web renderer; shader cache moved away first, because a web page has none). Level 1, bars 1-22:

| Suspect | Verdict | Evidence |
|---|---|---|
| a. shader compile on first draw | **TRUE** | ~100 ms frames at the first pickup burst (102-117 ms), the first checkpoint (97 ms: first flat-shader material), and two first-appearances (98-108 ms). 10 frames over 25 ms mid-run. |
| b. clock stepping | **the named cause false, a cousin true** | nothing reads `get_playback_position()`. But `song_time()` read the system clock at whatever moment the script ran: its per-frame step differed from the engine's frame delta by **3.46 ms median, 6.7 ms p99, 12 ms worst** — everything on screen is positioned from it, so the whole picture trembled along the scroll. |
| c. camera | **kick / hit-stop: false. Downbeat nod + punch: THE JUMP** | `kick()` is only called from `on_death`. But the brief-3 nod (1.5°) and the 2 % FOV punch went to full strength in ONE frame: a point fixed to the camera rig moved **18.7 px (at 1200 px wide, ~37 px on a phone) on 22 of 22 downbeats and on no other frame** — the frame the gates jump and the volleys fire. The camera follows `z_at(song_time)`, so it inherited (b) and nothing else. |
| d. spawn spikes | **false** | nothing is instantiated after `field.build()`. One-off: on the bar-1 downbeat every wall in the level swaps material at once (23 gates, 10 sweepers, 16 slammers): ~2 ms on the Mac. Left alone. |

**Fixed (only those):** (a) `prototype/prewarm.gd` draws every real mesh + material pair, and invisible copies of both particle bursts, at 1/1000 scale behind TAP TO START, then frees itself after 8 frames. (b) `BeatClock` advances by frame delta and is pulled toward the system clock (`CLOCK_CORRECT_TAU_S` 0.5, hard snap beyond `CLOCK_SNAP_S` 50 ms); `song_time()` is constant within a frame. (c) `PUNCH` and `NOD_DEG` are 0; if re-enabled they ease in over `BEAT_ATTACK_S` 80 ms.

**Before → after (same probe, cold cache, Mac):** frames over 25 ms mid-run **10 → 0**; worst mid-run frame **117.7 → under 25 ms** (ring worst 15.3); camera steps over 1.5 px **22 → 0**; clock step vs frame delta **3.46 → 0.04 ms** median. The load frame got longer (845 → ~1500 ms) — that is the compile moving behind TAP TO START, where it belongs. **Phone numbers: not measured from here; read them off the meter.**

Leads, not touched: every hazard in the level is posed every frame, on screen or not (`track_test._update_world`) — if the phone's AVERAGE is high, that is the first thing to cut. `Progress.record_best` writes the save file every 2 s while setting a new best (shows as `progress save` in a FRAME line if it ever costs).

### 3. Monoliths
- **Were the carvings geometry? Yes** — an untextured render of both source GLBs shows every symbol and the recessed circle; nothing was invented. At the old 1.5k triangles they were mush; at 6k they read.
- **Uniform scale:** one number per monolith (height / model height). The per-axis stretch and the shader taper are gone. Tall 14-40 high, stacked 14-28, far huge ones 44-64 (tall only). 1-2 per side per bar (was 1-3).
- **Material:** no colour from the model (the vertex colours were a blurred copy of the AI bake). `Props.building()` is procedural stone from world position: triplanar fine + coarse grain, formwork bands, lit per facet from derivative normals so carved edges are hard. `WorldPalette.BUILDING_STONE` / `_FAR`.
- **Detail:** `building_*_hi` (6000 triangles) within -6..+18 units of the window, `building_*` (1500 / 1800) beyond; one `MeshInstance3D` each (289 on level 1, ~26 shown, 6-9 detailed).
- **Fog:** the z fade, plus fog by |x| (16 → 60 units, up to 85 %) and below the field (6 → 30, up to 90 %).
- **Triangles in frame (whole scene):** bar 1 **76 852 → 145 234**, bar 9 **64 290 → 119 466** (under brief 4's 150k); draw calls 308 → 326, 324 → 342.
- **Screenshots (web renderer):** `docs/screenshots/a5-monoliths-before-bar1.png` / `after-bar1.png`, `-before-bar9.png` / `-after-bar9.png`.


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
- **Validator (rerun with the props in):** levels 1, 2, 3, 4, 5 — **0 deaths, goal reached**. The hit boxes did not move.

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
