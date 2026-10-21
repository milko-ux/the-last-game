# Step 3 brief 2 — MONOLITH CANYON

Written by Code, 2026-10-21, from Milko's pick: concept frame **D** (`docs/concept/directions/D_monolith_canyon.png`).
It replaces brief 1's grey-stone direction ("dark stone field, grey fog"); brief 1's sections 4b and 5 are dropped (section 5's camera test survives as section 5 here).

> "I like D, the monolith canyon ... Lets start with bringing this to life and then when that looks great we can get the sunrise to a sunset and eventually the character is running at night." — Milko

## The look in one line

A cream limestone runway above a sea of soft clouds; pastel stone mesas (lilac, sage, sand, slate blue) rise out of the clouds, mostly *below* the runway so we look down on their sunlit tops; a warm low sun, a hazy gradient sky with far cliffs on the horizon.

## Rules for the whole brief

- **Colour meaning is untouched:** magenta = kills, cyan = safe, amber = goal. The scenery uses none of the three.
- **Textures:** procedural, or baked in Blender from our own models. The concept frame is a reference only.
- **One file per real thing:** the canyon *replaces* the grey look (palette, backdrop, floor, pillars); no second copy of the world kept alive. The old look is in git.
- **The colours of the world live in `WorldPalette`** (`prototype/palette.gd`) and are grouped so a later time of day (sunset, night: Milko's next step, NOT this brief) is a second set of the same names, not new code.
- **Any new material goes into `prewarm.gd`.**
- Every section is checked on the web shot (`tools/web_shot.py`, the phone's size) before its commit.

## Section 1 — the sky and the clouds (the backdrop)

The backdrop quad (`camera_rig.gd`) becomes a painted backdrop, in screen space: a sky gradient with the sun's glow, far mesa silhouettes on the horizon in hazy layers, and below the horizon a sea of clouds in perspective that drifts toward the camera with the run. The fog stops (`WorldPalette.BG_*`) become the canyon's haze, so everything far fades into the sky behind it; the height fog sinks the mesas' feet into the clouds.

## Section 2 — the floor

Cream limestone tiles, procedural (the baked slate atlas retires): per-tile tone and warmth, fine grain, a bevel lit by the sun, soft occlusion in the seams. The slab's body is light stone with a cool lilac shadow side. Magenta plates, the cyan rim and the drop shadows stay; the shadows turn cool lilac instead of black.

## Section 3 — the mesas

A new pillar kit, made by script in Blender (`tools/blender/mesas.py`): faceted stone columns with strata ledges and flat tops, low-poly, no atlas. One shader: the facet lit by the sun as three tones, a pastel colour per mesa, a sage cap on the top faces, the foot sunk into the clouds. Placement: tops mostly below the runway (visible from this camera), a few near ones above it.

## Section 4 — the light

The sun lower and warmer, its direction matched to the backdrop's sun; the shadow side cool lilac; the tone mapper chosen on the web shot for the pastels (the hazards must stay as readable as today). The hero stays clearly readable on the light floor.

## Section 5 — the camera test

Two variants on the look switch: today's camera, and a lower, longer-lens one that shows more of the horizon. Milko plays both.

**STOP after section 5.** Re-export the cable app. Milko plays it on the phone and runs the probe.

## Not in this brief

Times of day (sunrise → sunset → night), world zones per lap, trees/foliage, new hazard looks, the menu's own art. Asked again when the canyon is approved.
