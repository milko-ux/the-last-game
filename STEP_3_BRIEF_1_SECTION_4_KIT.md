# Step 3, brief 1 — section 4, rewritten: a new pillar kit

Written 2026-10-06 by Cowork. **This file replaces section 4 of `STEP_3_BRIEF_1_WORLD.md`.** The rules at the top of that brief still apply. Do section 3 (placement) first: this kit is designed for section 3's pillar count and height ranges.

## Why

Milko on the phone, 6 Oct, look `deep fog`: "some monoliths just look like Legos stacked on top of each other". He is right, and the cause is in `tools/blender/pillars.py`: every pillar is three to five boxes stacked by a script, with a cap wider than the shaft (`v_plain`, `v_circle`, `v_stacked`, `v_symbols`). While the world was black nobody could see it. Now the values are right, the shapes are the fault.

Re-baking the same kit, which the old section 4 asked for, would not fix this. The kit is replaced.

**The quality bar (Milko):** the best the phone can show. Heavier models are fine. What is not negotiable is 16.7 ms on the phone and the art direction.

## The target

`docs/concept/field_monolith.png.png`. Look at its pillars before modelling anything:

- Each pillar is **one solid mass**, not a stack. No cap, no base plate, no part wider than the shaft.
- The tops are **broken**: chipped corners, a notch, an uneven edge. No two are the same.
- A few carry one large feature: an arched niche, a bridge to a neighbour, a ledge.
- The surface is weathered stone with fine block joints, and it is readable even on the shadow side.
- They are few, upright and calm.

## The kit: six pieces

| # | Piece | From the concept |
|---|---|---|
| 1 | Tall plain shaft, broken top | The pillars in the upper right |
| 2 | Shaft with a tall arched niche cut into one face, and a stepped shoulder | The big pillar in the left foreground |
| 3 | Bridged pair: two shafts joined by a thin lintel | Upper left |
| 4 | Shaft with a ledge and a narrower upper part | Right middle |
| 5 | Split shaft: a deep vertical crack and a notched top | Lower right |
| 6 | Slender far shaft, simple, cheap | The pale ones dissolving in the fog |

- The closed-eye circle motif stays, on one or two pieces only, carved large and deep enough to read on a mid-band pillar on the phone. Not a small stamp on every face.
- Every side face and the top face are finished, because the game turns the pillars and the camera sees the tops.

## How to build them (Blender, headless, as today)

1. **Model a mass, don't stack boxes.** Start each piece from one block. Give it a slight taper and slightly uneven faces. Break the top with boolean cuts from displaced, irregular cutters, so edges look chipped and no edge is a perfect straight line at close range. Bevel the long edges a little so they catch light.
2. **Stone surface, baked.** Fine block joints, pitting and vertical weather streaks made with Blender's own procedural textures, baked into the atlas together with the light. No AI image is used as a texture, as always.
3. **Light, baked.** Ambient occlusion, the game's own key light direction, and enough soft sky light that a face turned away from the key averages no darker than about 45 % of the lit face. **No face may be 0 in the atlas** (today's shadow faces are, which is why they stayed black under every tint).
4. **Native heights.** Build tall pieces at the heights section 3 calls for. No piece is stretched more than 1.5× in the game, and never in one axis only.

## Budgets

- Triangles: up to about 1,500 per piece (today 26–130). Report the total in view at bar 1 and bar 11.
- Still one material and one shader, so nothing new for `prewarm.gd`; confirm it. The atlas may grow to 4096 if needed.
- Download grows by less than 4 MB. Report the `mem` readout before and after.
- `frame_probe` before and after. The phone's probe rows `no pillars` and `pillars x0.5` are the real check.
- The `deep fog` zone values must still hold: re-measure the zone table after the new bake and retune the band tints if the brighter shadow faces moved them.

## Order, with a quality gate

**4a. Pieces 1 and 2 only.** Put them into the game as the look variant `new kit` (the other pieces keep the old models for now). Save:
- `docs/screenshots/c4a-pieces.png`: each new piece at 100 % of the 2556 × 1179 web shot, beside the matching crop of the concept.
- `c4a-bar1-vs-concept.png` and `c4a-bar11-vs-concept.png`.

One commit. Re-export the cable app.

**STOP.** Milko judges on the phone: do these two look like the concept's stone, or like better Lego? Cowork looks at the crops. Nothing else in this section is built until he says yes.

**If the answer is no:** stop and tell Cowork. The fallback is geometry from Higgsfield image-to-3D of the concept's pillars, cleaned up and decimated in Blender, with our own bake. Cowork writes that brief; don't start it unasked.

**4b. Pieces 3–6**, in the same way. One commit. `new kit` becomes the shipped pillars; the old kit and `pillars.py`'s old variants are deleted, not kept beside the new ones.

**Done when:** on the phone, no pillar reads as stacked blocks, carving is visible on pillars on both sides of the field, and the frame time is unchanged.

**STOP.** Re-export. Milko plays a run and runs the probe.

## Not in this section

The menu's old buildings (roadmap step 4), the hazards, the hero and the floor (brief 2).
