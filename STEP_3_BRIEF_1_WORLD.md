# Step 3, brief 1 — the world: light fog, upright pillars, tops in the frame

Written 2026-10-04 by Cowork from Code's scouting report of the same day. Roadmap step 3 (look, round 3). This brief replaces "stage C" of the look plan (`claude/LOOK_PLAN.md` in the Cowork project, never copied to the repo).

The character (model v2 and the walk) is brief 2. The menu's old buildings are roadmap step 4. Neither is in this brief.

## Why this brief is not "remodel the monoliths"

The scouting report measured the real causes, and the models are the smallest one. Compare `docs/screenshots/b-bar11-vs-concept.png` (left: the game, right: the target `docs/concept/field_monolith.png.png`, which is one single picture and all of it is the target):

| | The game today | The concept |
|---|---|---|
| Background | 36 % of the frame is 12/255 or darker | Nothing is pure black; the fog is the lightest thing |
| Pillars | Black, leaning, converging shards with tops cut off or sunk below the floor | Upright, calm, tops visible inside the frame |
| Count in view | 19–20 per side | About 12 in the whole picture |
| Carved faces | On +x and −z only, so the screen-left pillars show a blank shadow side | Form readable on every pillar |

So the order is: measure, then values, then placement, then the bake, then the camera. Cheapest first. Each section is one commit.

## Rules for the whole brief

- Art direction is unchanged: stone, clay and fog; the world stays matte; magenta = kills, cyan = safe, amber = goal, and none of the three may appear in the stone or the fog. Textures are procedural or baked in Blender from our own models.
- The app runs the Compatibility renderer. Every check is made on a Compatibility build (the headless web shot at 2556 × 1179, glow off), never on a Mobile-renderer Mac shot.
- No gameplay change. `prototype/rules.gd`, the generator and the hit boxes are not touched. If a section turns out to need one of them, stop and ask.
- Frame time: the phone holds 16.7 ms today and the spare time is unknown until section 1. No section may add a full-screen see-through layer, turn glow on, or raise the draw-call count. Run `frame_probe` before and after each section and report both numbers.
- After each section: a new side-by-side against the concept at bar 1 and bar 11, saved in `docs/screenshots/` as `c<section>-bar1-vs-concept.png` and `c<section>-bar11-vs-concept.png`, plus the measured share of pixels at 12/255 or darker (whole frame, left third, right third).
- Milko judges on his phone. Never open a visible game window. Stop at every line marked **STOP**.
- Hard rules 1–8 in `CLAUDE.md` apply as always.

---

## Section 1 — measure: the probe and a look switch inside the app

**Why:** the phone caps at 60 fps, so 16.7 ms hides how much time is spare. The probe (`prototype/probe.gd`) only starts from the web address switch `?probe=1`, which the app doesn't have. Sections 2–5 also need a way for Milko to compare before and after on the phone.

**Build:**
1. A way to start the existing probe from inside the app, in debug builds only (never in a release export). Simplest thing that works, for example a long press on the frame readout on the TAP TO START screen. The table is drawn on screen as today and also written to `blackbox.log`.
2. A "look" switch, debug builds only, that cycles named look variants and shows the current variant's name in the readout. It works like the probe's setups: a variant is a small set of overrides. For now it has one entry, `today`. Sections 2, 3 and 5 add entries. One mechanism, used by both the switch and the probe. No second copy of any value.
3. Add two probe setups: `no pillars` and `pillars ×0.5`, so the table says what the background costs on the app.

**Done when:** on the cable app Milko can start the probe and read the table.

**STOP.** Milko runs the probe on the phone and sends the table (a screenshot) to Cowork. The numbers decide how much sections 3–5 may spend.

---

## Section 2 — values: no black anywhere in the world

**Why:** this is the largest visible fault and the fix costs nothing at runtime.

**Where the darkness comes from (from the report):**
- `prototype/palette.gd:24-27` — the backdrop stops `BG_TOP #556173`, `BG_THIRD #38404e`, `BG_MIDDLE #1b2029`, `BG_BOTTOM #0c1016`. The lower half of the fog is near-black.
- `prototype/palette.gd:51-53` — `NEAR_PILLAR #1b232c`, `MID_PILLAR #222a34`, `FAR_PILLAR #384150`, multiplied onto the baked stone.
- `prototype/flat_mats.gd:78-80` — `LOW_FOG_MAX 0.92` pulls everything below the floor 92 % toward `BG_BOTTOM`.
- `prototype/props/props.gd:322` — `PILLAR_FLATTEN [0.3, 0.6, 0.92]`.

**Change:** retune these values (and only values) so the frame matches the concept's brightness order:
1. The fog is the lightest thing in the world. Lift `BG_MIDDLE` and `BG_BOTTOM` clearly; the bottom of the frame in the concept is a dark blue-grey, not black.
2. The floor stays the brightest thing in the play area.
3. Near pillars are the darkest thing, as silhouettes against lighter fog, but still stone you can read: never below about 20/255.
4. Mid and far pillars step toward the fog colour, so depth reads as lighter, not darker.

**Targets, measured on the web shot at bar 1 and bar 11, the UI excluded:**
- Pixels at 12/255 or darker: under 2 % of the frame (today 36 %; 61 % on the left third).
- The darkest tenth of pixels averages 18–26/255 (the concept: about 21).
- The left and right thirds differ by less than a factor of two in median brightness (today 5 against 42).
- Hazards, the hero and the cyan rim must read at least as clearly as today. Show a crop of each, before and after.

**Also:** measure what the ACES tone mapping does to values under 30/255. If it is crushing them, say so and propose a change, but don't switch the tone mapper without asking.

The old values stay reachable as the `today` look variant; the new ones are `light fog`.

**Done when:** the targets are met and both side-by-sides are saved.

---

## Section 3 — placement: upright, fewer, tops inside the frame

**Why:** the camera looks 54° down (`prototype/camera_rig.gd:33`), so nothing higher than about 21 units above the field can be on screen. Today the far band's tops (up to +48) are always cut off, 62 % of near pillars end below the floor, and the pillars lean up to 6° (`TILT_MAX_DEG`, `prototype/monoliths.gd:30`), which the wide lens turns into chaos. In the concept every pillar is upright and you see its top.

**Change, in `prototype/monoliths.gd` (`BANDS`, line 32, and the constants above it):**
1. **Upright:** `TILT_MAX_DEG` to 0, or at most 1.
2. **Tops in the frame:** set each band's height range from the camera's real projection, not by eye: for every band, at least 80 % of the pillars in view must have their top edge inside the frame, with a margin to the top of the screen. Work out the ranges from `camera_rig.gd`'s pitch, FOV and distance and write the calculation in a comment.
3. **Above the floor:** in the near and mid bands, most tops end above the floor (the concept's near pillars rise past the field). A near pillar must never cover any part of the playing field or the hero on screen; check this by projection across a whole lap.
4. **Fewer:** aim for about 8–10 pillars per side in view instead of 19–20, with real gaps of fog between them. Keep the bridged pair, but rarer.
5. Placement stays seeded and identical on every phone. This is background only: confirm that nothing in the rules or the generator reads it. If something does, stop and ask.

Add the result as the look variant `tops in frame` (on top of `light fog`).

**Done when:** the side-by-sides show upright pillars with visible tops on both sides, the field is never covered, and `frame_probe` is no slower than before.

**STOP.** Re-export the app. Milko compares `today`, `light fog` and `tops in frame` on the phone, runs the probe, and reports.

---

## Section 4 — the bake: every face carved, no black shadow side, no 9× stretch

**Why:** the carvings exist only on the +x and −z faces (`tools/blender/pillars.py:126,139,172`) and the light is baked from one direction, so every pillar on the screen-left shows a blank face in baked shadow. One 8-unit piece is stretched up to 9× for the far band.

**Change, in `tools/blender/pillars.py`, then re-run `tools/blender/bake_all.sh`:**
1. Carvings on all four side faces of every pillar, and on the top face, since the camera sees the tops. Different on each face, so a turned pillar doesn't repeat. The closed-eye circle motif stays.
2. More soft sky light in the bake, so a face turned away from the key light is still clearly stone: its average no darker than about 45 % of the lit face. The key light's direction stays the game's own.
3. Add tall pieces to the kit (for example 24 units) so no piece is stretched more than about 3× in the game, and have `monoliths.gd` pick the piece that fits the height.
4. Still one 2048 atlas, the same material and shader, and triangle counts in the same range as today (26–130 per piece). No new material means nothing new for `prewarm.gd`; confirm it.
5. Deeper carvings: they must be visible at the size a mid-band pillar has on the phone screen. Check on a crop at 100 % of the 2556 × 1179 shot.

**Done when:** on the bar 11 side-by-side, carvings are visible on pillars on both the left and the right, and the download grows by less than 1 MB.

---

## Section 5 — the camera test (a test, not a decision)

**Why:** the wide lens (FOV 55) close to the field makes vertical lines splay; the concept is a longer lens from further away, which keeps pillars parallel and calm. This is the biggest remaining lever, and it is a feel question only Milko can judge.

**Build three look variants, switchable in the app:**
- `cam A`: today (pitch 54°, FOV 55, distance 26).
- `cam B`: longer lens, same angle: FOV about 40, the distance increased so the field covers the same share of the screen as today.
- `cam C`: longer lens and a little lower: FOV about 45, pitch about 47°, the distance set the same way.

**Hard limits:**
- The same stretch of course is visible ahead of the hero in all three (the window's far edge stays on screen), so the difficulty doesn't change.
- Controls, rules, hit boxes and the jump are untouched. The joystick stays world-relative.
- Section 3's height ranges are recalculated per variant from that variant's own projection.
- Run `frame_probe` on each. A variant that puts more pillar on screen may cost more; report it.

**Done when:** Milko can switch between the three in the app.

**STOP.** Milko plays all three on the phone and picks one. Only then is the pick made the default and the others removed.

---

## At the end

- Update "Where we are" in `prototype/README.md`.
- Move this brief to `docs/briefs/done/`.
- Save a copy of the look plan's outcome: one paragraph in `docs/ROADMAP.md` step 3 saying what brief 1 changed and what is left (the character, brief 2).
