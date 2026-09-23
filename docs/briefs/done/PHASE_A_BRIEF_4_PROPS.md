# Phase A — Brief 4: the props

**Read after Brief 2b and its seam fix.** Same rules, same permission. **`rules.gd` is not touched by this brief.** Every hit box, timing and position stays exactly what it is — this brief only changes what is *drawn* at those positions. If a model doesn't fit its hit box, scale the model, never the hit box.

## The idea

The world's material split, decided by Milko 2026-09-20: **what you stand on is stone; everything that moves or kills is a clay being — the same clay as the hero, in magenta.** The buildings are stone with carved symbols. The hero is the one open eye; every hazard has a closed one. Circles everywhere.

## Assets — Milko drops these into `assets/models/`

| File | What | Built from |
|---|---|---|
| `gate_pillar.glb` | one gate pillar, a chunky leaning clay pillar with a closed-eye recess | a gate = two of these, the second mirrored on x |
| `sweeper_segment.glb` | one loaf-shaped clay segment with rounded ends | a sweeper = N segments end to end across the field, omitted where the rules put the gap |
| `slammer.glb` | plump clay block, flat underside, closed eye on front | one per slammer |
| `orbiter_pillar.glb` | squat clay pillar with a groove ring, no orb | one per orbiter; the orb stays the existing glossy sphere, on its existing orbit |
| `volley_emitter.glb` | half-buried clay egg with one open glossy eye | one per volley, at the field edge it fires from, eye facing across the field |
| `building_tall.glb` | tall thin carved building | monoliths |
| `building_stacked.glb` | stacked wide building | monoliths |

Reference stills for each are in `docs/concept/props/` (Milko drops them; names match the GLBs). If a GLB is missing, keep the box for that type and say so — don't block.

## Import rules (same as the creature)

- Inherited scene per model under `prototype/props/`. Fix pivot and scale there, never in the GLB. Pivot at the base centre for standing things, at the top centre for the slammer (it hangs).
- Store each model's rest rotation as a constant. They will not come in facing the right way.
- Materials: the baked clay texture is the base. Wrap it in the hazard material logic from Brief 2b so it still does: armed = wine tint over the clay, live = hot magenta wash with the bright rim, the Brief 3 breathe-to-the-beat and the white flash. The eye recesses stay dark. Hazards are lit like the creature (they are the same clay); buildings stay unlit with the distance fade.
- Buildings keep the Brief 2b concrete shader's grain *on top of* their baked texture only if the baked texture looks flat at phone size; otherwise the bake alone.

## Fit rules per type

- **Gate:** two pillars, one mirrored, placed at the opening's edges. The pillars' inner faces define the visible opening; that opening must equal the rules' opening width to within 0.1 unit — measure it, don't eyeball it. When the opening jumps, both pillars slide (Brief 3's 120 ms), the mirror stays.
- **Sweeper:** segments are 2 units long; a 9-tile field is 9 segments minus the gap. Rounded ends face the gap. The whole train moves as one node.
- **Slammer:** hangs from its top pivot; the Brief 1 hover-telegraph moves the whole model. Flat underside is the lethal face; it must sit exactly on the hit box's bottom plane.
- **Orbiter:** pillar at the rules' pillar position, orb unchanged. The groove ring is at the orb's orbit height — scale the pillar so it is.
- **Volley:** emitter at the field edge, eye toward the field. On fire: 15 % squash then release (Brief 1 style), the orb spawns from the eye.
- **Buildings:** the seeded monolith placer now picks a model (tall 60 %, stacked 40 %) instead of a box, with the same seeded scale, tilt and distance. Still one `MultiMeshInstance3D` per model type per window. Far huge ones use the tall model scaled up.

## Performance

Total triangles on screen must stay under 150k on the web export. Read each GLB's count in the importer; if the sum for a busy bar exceeds that, enable the importer's mesh simplification per model until it fits, biggest offenders first. Buildings are the likely offenders — they're far away and can lose most of their detail without anyone noticing.

## Acceptance

- `docs/screenshots/a-props-bar1.png` (a gate, pillars visible), `a-props-wave2.png` (a slammer and a volley), `a-props-wave3.png` (a sweeper train with its gap), `a-props-wave4.png` (orbiters), all at 2400×1080, web renderer.
- Validator bot: 0 deaths on 1–5 — proves the hit boxes didn't move.
- Triangle count per screenshot in the report.
- "`rules.gd` untouched" stated in the report.

## Not in this brief

The goal ring, checkpoint ring and notes (they're shader-built and fine), UI, audio, the death/share screen.
