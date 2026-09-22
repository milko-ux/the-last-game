# Hazard collision in the 2D game — why the hit test is in screen space

**Read this before tuning 2D difficulty.** Pointer lives in `CLAUDE.md`.

Hazard hit tests are measured in **screen space**, not on the flat grid — `Hazard.hits()` uses `Iso.project_offset()`. This is deliberate and was a bug fix on 2026-08-21.

The grid underneath is flat, but everything is DRAWN isometrically, which squashes the vertical axis to half. Testing on the grid made the real kill zone about **half as tall as the ball looks on screen**: you could overlap the art from above or below and live, while the same gap from the side killed you. Measuring the projected offset instead means contact means contact from every direction — what you see is what kills you.

Practical effect: hazards became roughly **twice as sensitive** along the screen-vertical axis, which is what Milko asked for after playtesting. Wall collision is unchanged and still grid-based (`Player._blocked()`) — that's a different problem and belongs on the grid.

If difficulty needs tuning later, change `Hazard.RADIUS` or `Player.HIT_R`, not the projection.

