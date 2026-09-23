# Phase A — Brief 3: motion

**Read after Brief 2.** Same rules, same permission. Nothing here touches `rules.gd`, hit boxes or timing — motion is presentation only, driven by the same `BeatClock` signals the game already fires. If any item would change when something becomes lethal, it's wrong; stop and ask.

Goal: the world is visibly *on the beat* and every important moment — death, pickup, checkpoint, goal — has weight. This is the difference between a prototype and a game people screenshot.

**Performance rule for everything below:** the web export on a phone must stay within 1 ms of the previous build per frame. No per-tile scripts — pulses are shader uniforms set once per frame on shared materials. Particle budget: at most 200 alive at once, `CPUParticles3D` on web if `GPUParticles3D` misbehaves.

## 1. The world on the beat

- **Rim pulse.** On every downbeat the slab's bright edge (`TILE_EDGE`) brightens 40 % and decays over one beat. On other beats, 15 %. One uniform on the rim material.
- **Seam pulse.** Seams brighten 20 % on the downbeat only, decaying over half a beat. Subtle — if you notice it consciously, it's too much.
- **Armed hazards breathe.** Anything in `LETHAL_ARMED` state pulses toward `LETHAL_LIVE` by 25 % on each beat of its rate, so a warning hazard visibly counts down to the beat it fires on. This is the single most useful motion in the brief: it teaches timing without words.
- **Gate opening slides.** When a gate's opening jumps to a new x on the downbeat, the *visual* wall slides there over 120 ms instead of teleporting. The rules still treat the jump as instant — the slide is only the mesh. The slide happens *after* the rules change, never before, so the visual never shows an opening that isn't yet real.
- **Notes bob and spin.** Amber notes bob ±0.15 units at the beat rate and rotate once per bar. Nearest note within 2 tiles of the player also does a small scale pulse on each beat.
- **Monoliths: still.** They do not move, pulse or breathe. The stillness is what makes the field's motion read.

## 2. Death

Already: freeze 0.35 s, creature grows and pops, 12 particles, rewind. Add:
- **Hit-stop.** During the freeze, the *whole world* holds — hazards, notes, rim pulse — not just the player. `BeatClock` keeps running (audio must not stutter); the visuals sample a frozen time value for the duration.
- **Camera kick.** A 0.25 s shake, amplitude 0.35 units, decaying; plus a 4 % FOV punch outward. Direction of the shake biased away from the killing hazard.
- **Flash.** The killing hazard flashes white for 2 frames at the moment of death, so the player's eye lands on *what* killed them. Nothing else flashes.
- **Rewind.** On rewind, the field between the death point and the checkpoint does a fast cyan ripple backward along the slab (rim brightness travelling from the death bar to the checkpoint bar over 200 ms). Reads as "time going back", costs one uniform.
- **Level 1 stays lives-free**; none of this adds delay beyond the existing freeze.

## 3. Pickup and combo

- Note pickup: the note collapses to the player over 80 ms, then a ring of 8 amber particles bursts outward. HUD note counter pops 30 % and settles over 150 ms.
- Combo step-up (×2, ×3, ×4): the combo label pops 50 % and the rim pulses amber once instead of cyan for that beat.
- Combo break (death): the combo label drops and fades over 300 ms. No sound effects in this brief; audio is separate.

## 4. Checkpoint and goal

- Checkpoint reached: the cyan checkpoint marker sends a single rim pulse *forward* along the slab (200 ms), the creature does its quick turn to the camera (Brief 1 addition), the progress bar's tick for that checkpoint lights.
- Goal: the amber gate's opening widens over one bar as the player approaches the last bar; on crossing, the whole rim goes amber and pulses on the beat for 2 bars while the creature does its three hops. Then the results label.

## 5. Level start

The run-up is currently a static field for ~9 seconds. Make it a build-up:
- Bars materialise ahead of the player as the window advances during the run-up: each bar's tiles rise from 0.5 units below the surface to 0, staggered 20 ms per tile row, over 200 ms, in the order they enter the window. After the first downbeat, bars ahead of the window materialise the same way as they come into fade range, so the world is always being built just ahead of the player.
- Monoliths do not materialise; they're already there. The field is what's being built for you.
- The progress bar fills from empty to the run-up point over the first second.

## 6. Camera

- Keep the 2 % downbeat FOV punch.
- Add a very slight forward tilt of 1.5° on the downbeat that decays over the bar. The camera nods to the beat.
- Death kick as in §2.
- No camera motion on jumps.

## Acceptance

- A 4-second screen recording at phone resolution from bar 1 to bar 3, saved as `docs/screenshots/a-motion-bar1.mp4` (or a sequence of 8 frames if recording isn't possible from the MCP). Milko judges: does the world visibly move on the beat?
- A frame at the death moment with the killing hazard flashed white: `docs/screenshots/a-motion-death.png`.
- Web frame time within 1 ms of the previous build. Report the number if measurable, or the alive-particle peak if not.
- Bots unchanged. Nothing in `rules.gd` touched — say so explicitly in the report.

## Not in this brief

Audio (SFX, ducking on death), the death/share screen, the level select, the progress bar's restyle. Brief 4 is UI; audio is its own pass after that.
