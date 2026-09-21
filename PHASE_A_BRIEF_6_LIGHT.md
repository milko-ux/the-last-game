# Phase A — Brief 6: light

**Read after Brief 5 (the walk).** Same rules and permissions: one commit per section, report at the top of `prototype/README.md`, stage the diffs and show Milko before pushing. Branch `phase-r-prototype`.

**Visual only.** `rules.gd`, `hazard_math.gd`, `fairness.gd`, `placement.gd`, `lap_gen.gd`, hit boxes and timings are not touched. Colour meaning is not touched either: **magenta = kills you, cyan = safe, amber = goal.** Light may shade those colours; it may never shift their hue or make one read as another.

## The problem (Milko, from the phone, 2026-09-20)

"It still looks way too basic. Too flat." Put the game next to `docs/concept/field_monolith.png.png` and `docs/concept/creature_ref.png` and the difference is not the models. It is that **the concept has a light in it and the game does not.** In the concept every top face is lighter than its sides, one side of every block is in shadow, things sit on the floor because there is darkness under them, the fog has a colour and a depth, and the hero has a rim of light. In the game the world is unshaded flat colour, nothing casts anything, the fog is one grey, and the hazards read as pink cones.

The concept images are the target. Every section below closes one named gap between the two.

## How this brief is staged

- **Stage A (this brief, do it now): fake the light inside the shaders we already have.** It costs almost nothing per pixel, it works in the web renderer the phone runs today, and it gets most of the way to the concept.
- **Stage B (NOT in this brief, do not start): real shadows and the lit pipeline on the native iPhone build.** It will be written once the game runs natively on Milko's phone.

**The phone is GPU-bound** (performance job, 2026-09-20). Everything here must be cheap per pixel: no new full-screen passes unless measured, no texture lookups in the world shaders, no extra draw calls beyond the ones named. One dev switch for the whole brief: `?light=0` renders the old look, so Milko can A/B it on the phone at the same spot (`?level=1`, bar 11).

## 1. One light, one direction, everywhere

- The existing `CreatureLight` becomes **the** light of the world. Its direction is published once per frame as a global shader uniform `pr_light_dir` (declare it in `project.godot` like the brief-3 uniforms). Starting direction: from the viewer's upper left, in front of the field, about 50° above the horizon — matching the concept, where tops are lightest and right-hand faces are darkest.
- **Every unshaded world shader** (tiles, slab sides, pit walls, monoliths, pillars, checkpoint markers) shades its colour by its normal against `pr_light_dir`, as three tones, not a smooth ramp: **top / lit side / shadow side = 1.00 / 0.74 / 0.46** of the base colour (`LIGHT_TOP`, `LIGHT_SIDE`, `LIGHT_SHADE` in `palette.gd`). The shadow tone is also pulled 15 % toward a cool blue (`SHADE_TINT #0f1a26`), so shadow reads as shadow, not as a darker grey. This replaces the monoliths' "top 12 % lighter".
- The lit shaders (creature, clay hazards, gloss orbs and notes) already use the real light; check they agree with the fake one by eye in one screenshot. One source of truth for the direction.

## 2. Things sit on the floor: drop shadows

- One `MultiMeshInstance3D` of soft dark quads lying just above the floor, unshaded, alpha-blended, one instance per thing that stands on or flies over the field: the creature (replaces its current blob), each leg's foot, gate pillars, sweeper segments, slammers, orbiter pillars, orbiter orbs, volley orbs, notes. One draw call for all of them.
- **The shadows obey the light:** each quad is offset from its caster along `pr_light_dir` projected on the floor, by `height above floor × tan(light angle)`, and gets larger and fainter with height (`SHADOW_MAX_ALPHA := 0.55` at contact, fading to 0.15 at jump apex). A slammer's shadow tightening and darkening as it drops, and a volley orb's shadow running along the floor under it, are **readability wins**, not decoration — they tell the player where the thing is in depth. Keep them crisp enough to read.
- Shape follows the caster's footprint: round for orbs and the creature, a long rounded bar for a sweeper segment, and so on. Darker core under the contact point (a fake ambient occlusion), soft edge.
- No shadow where there is no floor (`field.floor_at()`): a quad must not hang over a pit.
- Shadows follow hazard positions from `hazard_math`, never from their own timeline, and hold during hit-stop.

## 3. The fog gets colour and depth

- The backdrop gradient goes from two stops to three: `BG_TOP #10141b`, **`BG_HORIZON #3b4757`** (the light, blue band the concept has behind the far monoliths), `BG_BOTTOM #0c1016`. The horizon band sits at the height where the far end of the field meets the fog.
- **Things fade into what is actually behind them:** the distance fade in every world material fades toward the backdrop's colour at that pixel's screen height (the same three-stop function, shared), not toward one flat colour. Today far objects all go the same grey.
- **Height fog:** anything below the slab's underside fades toward `BG_BOTTOM` with depth, so monolith feet dissolve into a fog sea instead of ending.
- Far monoliths lose contrast before they lose colour (compress their three light tones toward the fog colour with distance), the way the concept's do.

## 4. The floor becomes stone

In the screenshots the floor reads as one dark teal sheet. The concept's floor is big stone tiles with relief.

- **Bevel:** a 0.08-unit band inside every tile edge, shaded by `pr_light_dir`: the two edges facing the light get a thin lighter line, the two facing away a thin darker line. This is the single cheapest thing that makes flat tiles read as slabs with thickness. Seams go darker, not teal.
- `TILE` up from `#1c2830` to about `#2a3642`, per-tile variation up from ±3 % to ±8 %, and a faint broad sheen toward the light on the tile face (one `pow(dot)` term, no texture). These are new starting values for Milko's numbers in `palette.gd`.
- The cyan rim stays only on the slab's outer edge. Armed and live plates stay tinted **stone** (grain and bevel visible under the magenta), never a flat magenta rectangle.

## 5. The hero gets a rim

- A fresnel rim on the creature's shader, on the side away from the key light: warm (`HERO_RIM #ffb9a0`), strength 0.5, tight falloff — the concept's rim. The hero is the only thing in the world with a warm light on it, which is what makes the eye find it instantly.
- The baked eye keeps its highlight at every angle (add a small specular dot that tracks `pr_light_dir` if the bake loses it when the body turns).

## 6. Hazards read as beings, not cones

- Near the player (within 1.5 bars) hazards use their **more detailed copies** so the closed-eye recess survives; further away the light copies are fine. Coordinate with whatever the performance job did to the gate pillars: the detail goes where the player is looking, at the opening.
- The live wash comes down from 75 % to about 45 % magenta over the clay, and the armed wine tint from 55 % to about 35 %, so the key light can model the form. **Live must still be unmistakable at a glance** — if it is not, bring the rim up (`LETHAL_SEAM` fresnel, already there) before bringing the wash back.
- The eye recess stays dark under every tint.

## 7. Glow — measure before keeping

- Try the real thing first: `WorldEnvironment` glow, threshold high enough that only the emissive colours bloom (the cyan slab rim, live magenta, amber notes and the best line, the shield bubble). Check whether the web renderer in this Godot version supports it at all, and report.
- **Milko measures it on the phone** at `?level=1`, bar 11. If the frame average goes above 16.7 ms with glow on, it goes, and the fallback is fake: a small additive halo billboard on notes and orbs, and a soft additive strip under the slab rim. One MultiMesh.
- Brief 3's beat pulses drive the emissive strength, so the glow breathes with the music.

## 8. Air and frame

- Dust motes: at most 40 tiny, slow CPU particles from one emitter riding the camera, lit side only, barely visible. They give the fog volume.
- A vignette: one unshaded full-screen quad **under** the HUD layer, 25 % at the corners, nothing at the centre. No colour-grading LUT.

## Acceptance

- Side-by-sides against the concept, web renderer, 2400×1080: `docs/screenshots/l-bar1-vs-concept.png`, `l-thrown-vs-concept.png`, `l-orbiters-vs-concept.png`, plus `l-before-after-bar1.png` (`?light=0` against the new look, same frame).
- One line per section in the report: what it cost in draw calls, and an honest note on what still does not match the concept.
- Triangles and draw calls in frame at bar 1 and bar 11, before and after.
- Layout hashes of levels 1–6 identical; validator bot 0 deaths on level 1 and laps 0–2; "`rules.gd` untouched" stated.
- Export, then **Milko reads the frame time on the phone** at `?level=1`, bar 11, with `?light=1` and `?light=0`. The brief is only done when the new look holds 16.7 ms average there. If it does not, cut in this order: glow, dust motes, tile sheen, near-hazard detail range.

## Not in this brief

Real shadow maps, lit world materials and anything else that needs the native renderer (Stage B) · the native iPhone build itself · new models or textures · UI, menu and HUD (the endless brief's Stage 2, from the approved mockup) · SFX.
