# Phase A — Art integration. Brief 1: the creature

**Read after the Phase R brief and addenda 1–4.** Phase R is the gameplay model; nothing in it changes here. Phase A adds the art on top, in this order, one brief each: **1 creature → 2 world (monoliths) → 3 motion → 4 UI**. This file is brief 1. Same overnight permission as addendum 4: commit and push on `phase-r-prototype` per section, never `main`, report at the top of `prototype/README.md`.

## The asset

`assets/models/creature.glb` — Milko drops it there. A textured mesh from Higgsfield image-to-3D: a round soft-clay creature with one large glossy eye, stubby arms and legs, a small tail at the back. No skeleton, no animations. Look at it in the editor first; expect the pivot to be off-centre and the scale arbitrary. Fix both in an inherited scene, never by editing the GLB.

Reference images: `docs/concept/creature_ref.png` (front) and `docs/concept/creature_alarmed.png` (the eye reacting). Milko will drop them in.

## Scale and placement

- The creature is **1.5 tiles tall** (3.0 world units from foot to top of body). The gray-box capsule was 1 tile. A mascot you can barely see is not a mascot — it must read as *someone* from the Phase R camera.
- Collision stays what the capsule had: a capsule of the same radius and height as before. The visual is bigger than the collision, deliberately — that is standard, it makes the game feel fair. The collision capsule is centred on the visual's feet-to-body centre.
- Pivot at the feet, on the floor. Facing: the front of the creature (the eye) faces **+z, down the field**. Store the model's rest rotation as a constant, because the GLB will not come in facing the right way.

## Material

The baked texture from the GLB is the base. Wrap it so it obeys the world rules:
- **Lit** — the creature is the one lit thing in the scene (Sayonara rule). One `DirectionalLight3D` in the scene, soft, from front-left-above, no shadows on web. The world stays unlit; only the creature's material responds to the light.
- The distance-fade shader from `prototype/flat_mats.gd` does **not** apply to the creature. It never fades.
- Drawn on top as before (the walls-see-through rule).
- Eye: if the baked eye is crisp enough at gameplay size, keep it and animate by rotating the whole head/body (below). If it isn't, replace it with a separate `MeshInstance3D` sphere (dark glossy, small specular) placed where the baked eye is, and animate that sphere's rotation instead. Decide by looking at a phone-resolution screenshot, not the editor viewport.

## Procedural animation — no rig, everything in code

All of this lives in a new `prototype/creature.gd` on the visual node, driven by the same inputs the player already has. Every value below is a constant at the top of the file; Milko will tune by feel.

1. **Idle breathing.** Vertical scale oscillates ±2 % at 0.5 Hz. Always on.
2. **Beat pulse.** On every downbeat the whole body does a 6 % squash (y down, xz up) over 60 ms and springs back over 180 ms. The creature is *on the beat* like everything else. Reads as bouncing to the music.
3. **Lean.** The body tilts up to 12° into the movement direction (pitch forward when moving forward, roll sideways when strafing), lerped at 0.2. Standing still = upright.
4. **Run bob.** When moving, a 3 % vertical bob at 4 Hz, scaled by speed. The tiny legs don't animate; the bob sells it.
5. **Jump.** On jump: 15 % stretch upward in the first 100 ms. **During the jump the body spins one full turn (360°) around its vertical axis**, so the eye is seen from the camera at least once per jump. Spin duration = the jump's airtime, eased in/out so it starts and ends facing forward. This is a Milko requirement, not a nicety. On landing: 20 % squash over 80 ms, spring back over 200 ms.
6. **Eye look-at.** The existing eye-targets-nearest-lethal-hazard behaviour moves to the creature: the body yaws up to 35° and pitches up to 15° toward the target, lerped at 0.15, on top of the movement lean. When no hazard is within the next beat, the eye drifts back to forward. If the eye is a separate sphere (see Material), rotate the sphere instead of the body for the look-at, up to 40°.
7. **Alarm.** In the beat before a hazard becomes lethal within 1.5 tiles of the player, scale the body up 5 % and hold — it braces. Release when the beat passes.
8. **Death.** No ragdoll. On death: freeze, 0.35 s as before; the body scales to 1.3× over the freeze while the eye (or body) snaps to look straight at the camera; then it pops to nothing over 80 ms with a burst of 12 small clay-coloured particles (GPUParticles3D, or CPU on web if GPU particles misbehave). Rewind brings it back at scale 0 → 1 over 150 ms at the checkpoint.
9. **Goal.** On reaching the amber gate: three quick hops (jump 1–3 without spin) and hold the last one facing the camera.

Order of blending: base pose → idle breathing → beat pulse → lean/bob → jump stretch/spin → look-at/alarm. Multiply scales, add rotations. Keep it in one `_process` so it's readable.

## Acceptance

- A phone-resolution screenshot at bar 1 with the creature standing still: it reads as the character from the concept image, from the Phase R camera, at a glance. `docs/screenshots/a-creature-idle.png`.
- A second screenshot mid-jump with the eye toward the camera. `docs/screenshots/a-creature-jump.png`.
- Frame time on the web export does not rise by more than 1 ms with the creature versus the capsule. If it does, decimate the mesh in the importer (Godot's mesh import "Simplify" option) until it doesn't; the silhouette matters, the polygon count doesn't.
- Both bots unchanged: the creature is visual only, collision is the same capsule.

## Not in this brief

Outfits and cosmetics (Milko's later monetization idea — design the material so the base colour and a "skin" texture can be swapped, but build nothing), the monoliths, screen shake, UI. Those are briefs 2–4.
