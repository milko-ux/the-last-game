# Phase A — Brief 2: the world

**Read after Brief 1.** Same rules, same permission. Reference: `docs/concept/field_monolith.png`. The target is that image: dark stone tiles with thin cyan seams on a thick floating slab, brutalist monoliths around it dissolving into fog, one lit creature. Everything here is unlit and uses the distance fade from `prototype/flat_mats.gd`.

## 0. Palette in one place

Create `prototype/palette.gd` (autoload `Palette` for the prototype only) with every colour the world uses as a constant. Nothing else declares a colour from now on. Starting values — Milko tunes from a screenshot:

```
BG_TOP        = #05060a
BG_BOTTOM     = #0b0d14
TILE          = #0f2b2f      # dark stone teal, the tile face
TILE_SEAM     = #19d3c9      # the thin cyan line between tiles
TILE_SIDE     = #081a1d      # side faces of the slab
SAFE          = #19d3c9      # cyan for anything "safe": pillars, checkpoint, death line
LETHAL_ARMED  = #5a1638      # dark wine magenta, the warning state
LETHAL_LIVE   = #ff2d95      # bright magenta, lethal now
GOAL          = #ffb020      # amber
MONOLITH      = #111419
MONOLITH_FAR  = #0c0e13
```

## 1. Tiles — from flat cyan to stone-with-seams

The floor is currently bright flat cyan. In the concept it is dark stone with thin cyan seams. One shader on the tile material:
- Face colour `TILE`.
- A seam of `TILE_SEAM`, 0.06 units wide, along every tile edge (use the tile's UV or local position, not extra geometry).
- Plates: armed state tints the face toward `LETHAL_ARMED`; live state = face `LETHAL_LIVE` with the seam brightened to white-magenta. The seam is what makes a live plate readable at a glance.
- Pits: the hole's inner walls get `TILE_SIDE`, so a pit reads as depth, not a black rectangle.
- Distance fade applies as before.

Readability check: a live plate must be identifiable in a phone-resolution screenshot in under a second. If the dark face makes armed plates hard to see, brighten `LETHAL_ARMED`, never the face.

## 2. The slab has thickness

The field is a floating slab, not a paper sheet. Give each bar segment 2.0 units of thickness below the surface, side faces in `TILE_SIDE` with a single `TILE_SEAM` line along the top edge. The near-side face is what the camera sees below the death line — it is the thing that makes the field look like it floats. Under the slab: nothing.

## 3. Monoliths

Brutalist slabs around the field, outside the play area. They scroll with the world (parented to bar segments or to a world root positioned by z), placed deterministically by bar index, seeded.

- Shapes: tall boxes, some tapered (scale the top face 70–90 %), some tilted ≤ 6°, a few stacked two-high with an offset. No detail, no bevels, no texture. Silhouette only.
- Sizes: width 3–8 units, depth 3–8, height 10–40.
- Placement: per bar, 1–3 monoliths per side. Distance from the field edge 3–14 units. Never intersect the field. Occasionally (1 in 6 bars) one sits *far* back, 20–30 units, huge, to give scale.
- Colour: `MONOLITH`, far ones `MONOLITH_FAR`. Same distance fade as everything, so the ones ahead dissolve into the background exactly like the field does.
- No monoliths within 4 units of the field's near-right corner, which is close to the bottom edge of the screen.
- One `MultiMeshInstance3D` per bar (or one for the whole window) so this costs one draw call, not fifty.

## 4. Background

The `WorldEnvironment` background colour becomes a vertical gradient `BG_TOP` → `BG_BOTTOM`. On the web renderer the cheapest way is an unlit quad parented to the camera, far behind everything, with a two-stop gradient shader; do the same on native for consistency. Nothing else in the background — no stars, no grid, no sun.

## 5. Hazards recoloured to the palette

Walls, gates, sweepers, slammers, orbiters, volleys: armed = `LETHAL_ARMED`, live = `LETHAL_LIVE`. Pillars, checkpoint marker, death line = `SAFE`. Notes and goal gate = `GOAL`. Remove any hard-coded colour that isn't in `Palette`. Walls stay see-through as before.

## Acceptance

- `docs/screenshots/a-world-bar1.png` and `docs/screenshots/a-world-wave3.png` at 2400×1080, next to a copy of the concept image. The question Milko will answer: is this the same world?
- Frame time on the web export within 1 ms of the previous build. Monoliths must be one draw call per bar or fewer.
- Bots unchanged — nothing in this brief touches `rules.gd`.
- A live plate is readable at phone size.

## Not in this brief

Beat-reactive pulsing of seams and monoliths, screen shake, hit-stop, particles beyond the creature's death, UI. That is Brief 3 — motion.
