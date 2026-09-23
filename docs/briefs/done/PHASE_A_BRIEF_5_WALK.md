# Phase A — Brief 5: the walk

**Read after the performance job of 2026-09-20 is committed.** Same rules and permissions as the other Phase A briefs: one commit per section, report at the top of `prototype/README.md`, stage the diffs and show Milko before pushing. Branch `phase-r-prototype`.

**This brief is visual only.** `rules.gd`, `hazard_math.gd`, `fairness.gd`, `placement.gd`, `lap_gen.gd` and `player3d.gd` are not touched. The hit box, the jump physics and every timing stay exactly what they are. If the walk needs a number from the player, it reads it; it never writes one.

## The problem (Milko, from the phone, 2026-09-20)

"It moves like a square and doesn't really walk. It looks like it's floating."

He is right, and tuning cannot fix it. The model has no skeleton, so `creature.gd` tilts, squashes and bobs **one rigid lump** on a timer (`BOB_HZ := 4.0`). Nothing touches the ground, and the bob has no relation to how far the creature actually moved. That is what sliding looks like.

## The idea

**Legs that plant.** Two short clay legs, separate from the body, each one planted at a fixed spot on the floor while the body travels over it, then lifted and swung to the next spot. The step cycle is driven by **distance travelled, not by time**. A planted foot never moves, so the creature cannot slide. No skeleton, no animation files, two extra draw calls.

The target is `docs/concept/creature_ref.png`: a round body on two stubby legs.

## 1. Remove the baked legs from the body (shader, not a new model)

The GLB has two leg stubs fused to the underside. Separate legs under baked stubs would look like four legs.

- Fit an ellipsoid to the body (measure it from the mesh: centre, three radii; print the numbers in the report). In the creature's **vertex shader**, any vertex that is outside that ellipsoid **and below the body's equator** is projected back onto the ellipsoid's surface. The stubs melt into the underside; no holes, no mesh editing, the GLB is untouched.
- The arms, the eye socket and the tail are left exactly as they are (the arms sit above the equator; exclude the tail's region by its z range).
- Screenshots of the body alone from the front, the side and below: `docs/screenshots/m-body-front.png`, `m-body-side.png`, `m-body-below.png`. **If the melt leaves a visible scar from the game camera, stop and tell Milko** — the fallback is a regenerated body-only model, which is his call, not a thing to improvise.

## 2. The legs

- Each leg is one rounded capsule in the creature's own clay shader (same `skin` / `base_tint` swap points, 8 % darker than the body so it reads against it). Starting size at `HEIGHT` 2.3: 0.34 wide, 0.44 deep, about 0.42 tall. All sizes are constants at the top of `creature.gd`.
- **A leg is a line between two points:** its foot (on the floor) and its hip (a fixed point on the body's underside, left and right of centre, `HIP_WIDTH := 0.46`). Every frame the capsule is placed at the foot, aimed at the hip, and stretched to reach it, clamped to 0.8–1.3 of its rest length. The top of the leg is inside the body, so the joint is never visible and the leg can never detach.
- Legs are never distance-faded and use the same "drawn on top" depth squeeze as the body.

## 3. The step cycle (the part that matters)

All in `creature.gd`, reading the player's **world-space** ground displacement each frame (the player's real movement over the floor, not its position inside the scrolling window).

- `stride_phase += ground_distance_this_frame / stride_length`. No movement, no phase change — the cycle cannot run on the spot.
- `stride_length` scales with speed: `STRIDE_MIN := 0.6` units at a crawl to `STRIDE_MAX := 1.8` at full player speed. At full speed that is a fast scurry of roughly 4–5 footfalls per second, which suits a small creature.
- The left foot is in **stance** for the first half of the phase and in **swing** for the second; the right foot is offset by half a cycle. There is always one foot on the ground while moving.
- **Stance:** the foot stays at the world position where it landed. It does not move at all. This is the no-slide guarantee.
- **Swing:** the foot travels from where it lifted off to its next plant point in an arc: `STEP_HEIGHT := 0.28` at mid-swing. The plant point is ahead of the hip along the current movement direction by half a stride. Aim the plant point each frame during the swing, so a direction change mid-step lands correctly.
- **Foot attitude:** yaw follows the movement direction; heel lifts first on lift-off and toe lands last, ±20° of pitch across the swing.
- **Body follows the feet** (this replaces the timed bob — delete `BOB_HZ`): lowest at each footfall, highest mid-stance, `BODY_BOB := 0.05` of `HEIGHT`; ±4° roll toward the stance leg; a 4 % squash on each footfall, multiplied with the existing beat pulse, not replacing it. The 12° lean into movement stays.
- **Stopping:** below `IDLE_SPEED := 0.3` for 0.15 s the feet settle side by side under the hips. A foot further than 0.35 from its rest spot takes one small corrective step to get there. It never slides there.
- **Sharp turns** (direction change over 90°): the swinging foot cuts its arc short and plants; the cycle restarts from that plant.

## 4. Jump, land, death, rewind

- **Jump:** both feet leave the floor with the body, tuck up 0.25 under it and turn with the 360° spin. Existing stretch and spin values are untouched.
- **Landing:** the feet touch one frame before the landing squash and splay 15 % outward during it, then return.
- **Death:** legs scale and pop with the body (same 80 ms pop, same particles).
- **Hit-stop:** while `motion.frozen` holds the world, the legs hold too.
- **Teleports:** on `reset_to`, on a rewind, or whenever the player's position jumps more than 2 units in one frame, both feet snap under the hips. A leg must never swing across the field to catch up.
- **Goal hops and the glance idle:** feet stay planted during the glance; hops use the jump rules above.

## 5. Footfalls you can see, and a hook for sound

- A dust puff on each footfall above half speed: 3 stone-grey CPU particles from ONE shared emitter, 8 on a landing. Stay inside the existing 200-particle budget and say what the peak is.
- `signal footfall(side: int, strength: float)` on the creature, emitted on every plant and every landing. Nothing listens yet; the audio pass will.

## 6. Tail (small, last, skip if it fights the melt)

In the vertex shader, vertices in the tail's z range are pushed sideways by `tail_sway` × their distance along the tail. `tail_sway` is a damped spring in `creature.gd` driven by sideways velocity and by turning, so the tail lags behind a turn and settles. One uniform, no new geometry.

## Acceptance

- **The no-slide number:** a headless run at full speed, straight and with turns, logging the world-space drift of each foot during its stance. **Maximum drift 0.00 units** (report the measured maximum).
- `docs/screenshots/m-walk-cycle.png`: eight stills across one full stride, from a side-on debug camera, laid out as one contact sheet. `m-walk-game.png`: the same moment from the game camera. `m-jump-tuck.png`, `m-idle-feet.png`. All web renderer, 2400×1080.
- Layout hashes of levels 1–6 identical. Validator bot 0 deaths on level 1 and on laps 0–2. "`rules.gd` and `player3d.gd` untouched" stated in the report.
- Frame-time readout at `?level=1`, bar 11: no worse than before this brief (Milko reads it on the phone).

## Not in this brief

Hands or moving arms · a regenerated model (single tail, body-only) · facial animation beyond the existing look-at · footstep sounds · the lighting pass (Brief 6) · outfits.
