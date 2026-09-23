# Phase R — Addendum 1: from track to field

**Read after PHASE_R_BRIEF.md. Where this addendum and the brief conflict, this addendum wins.** Everything about BeatClock, the beatmap, the renderer, the fog, the build/test loop, and "stage diffs for approval" is unchanged. What changes is the *shape of play*.

## Why (Milko's call, 2026-09-14)

A three-lane track where the player's position is locked to the song reduces every decision to "which lane" and "when to jump." That is Temple Run with a beat, and it has been done many times. The game's concept has always been *read the pattern, find the safe path, decide* — the World's Hardest Game idea. Keep that. The song adds the timing layer on top; it must not remove the spatial layer.

## New core model: the song drives the WORLD, not the player

- `BeatClock.song_time()` still drives everything in the world: the camera's forward position, and every hazard's state.
- **The player is no longer locked to time.** The player moves freely on the field surface (x and z) with the joystick, plus jump. The only constraint is the **window**: the region of field currently on screen. The window scrolls forward at song speed. If the player falls out of the back edge of the window, that is a death ("the beat caught you"). The player cannot move past the front edge of the window (clamp).
- Death still rewinds the song to the checkpoint and teleports the player to the checkpoint marker. Hazards still derive their state from time — nothing about rewind changes.

Constants (tune after playtest):

```
FIELD_WIDTH        = 14.0   # world units in x (was 6). Seven 2-unit "columns", but movement is continuous, not lane-snapped.
BAR_LENGTH         = 8.0    # z units per bar, unchanged
WINDOW_DEPTH       = 2.5 * BAR_LENGTH   # how much field is on screen front-to-back
SCROLL_SPEED       = BAR_LENGTH / beat_interval_s / 4   # = one bar per bar, derived from bpm, never hand-set
PLAYER_SPEED       = 2.2 * SCROLL_SPEED   # the player can outrun the scroll — that's what makes route choice possible
```

The back edge of the window is `z_back = song_time() * SCROLL_SPEED`. The front edge is `z_back + WINDOW_DEPTH`.

## Camera (replaces the brief's camera section)

- Higher and further back: local offset `(0, 12, -11)` from the **window centre** (not the player), looking at the window centre. Roughly a 50° pitch. FOV 60. The whole field width and about two bars ahead must be on screen on a phone in landscape — verify this first, before placing any hazard.
- The camera does **not** follow the player. It follows the window. The player moving inside the frame is the point: you see yourself commit to a route.
- Keep the 2 % FOV punch on the downbeat.

## Field (replaces track_builder)

- One flat slab per bar, `FIELD_WIDTH` × `BAR_LENGTH`, cyan unlit. Small gap between bars as before.
- Edges: no walls. Off the side = fall = death. This is intentional — the edge is part of the pattern.
- Some bars have **pits**: rectangular holes (remove that tile's mesh, no collision) in the slab. A pit is jumpable if it is ≤ 3 units in z.
- Bars are made of a 7 × 4 grid of **tiles** (2 × 2 units each). Tiles are the unit of hazard placement for pulse plates and pits. Give each tile its own small `MeshInstance3D` so it can change colour independently. Seven tiles across, four tiles deep per bar — one tile-row per beat.

## Hazard vocabulary (replaces Slammer / Pulser / Sweeper)

All hazards read `BeatClock` in `_process` and derive lethal state from time. No timelines of their own.

1. **Pulse plates** — the floor itself. A tile in the "armed" state is dark magenta; on its beat it becomes bright magenta and lethal for that beat, then returns to cyan. Placed in *patterns*, never randomly: 
   - `checker`: alternating tiles flip on every beat (beat 1: even tiles lethal, beat 2: odd tiles lethal …)
   - `row`: one tile-row across the full width goes lethal per beat, front to back
   - `column_wave`: lethal column travels left→right across the bar, one column per beat
   - `spiral`: a ring pattern rotating one step per beat
   A pattern is applied to a whole bar, chosen by the placement rules. This is the core "read where it is safe to stand" mechanic.
2. **Sweepers** — a magenta wall of full field height crossing the field in x over exactly one bar, with a 3-unit gap. Consecutive sweepers have their gaps offset by 4–6 units so the safe path is a diagonal that must be planned.
3. **Orbiters** — a cyan pillar (safe to touch) with one magenta orb orbiting it at radius 3 units, one full revolution per bar, phase locked to the downbeat. Two orbiters side by side with opposite rotation is a classic pattern.
4. **Gates** — a magenta wall across the entire width with a 4-unit opening. On every downbeat the opening jumps to a new x position (seeded). The gate is placed at the front of a bar so the player sees it one bar out and must commit.
5. **Slammers** — kept from the brief, one tile footprint, telegraphed by hovering one beat early. Used sparingly as accents on the `low` band.
6. **Pits** — see Field.

Keep hazard *count per bar* modest. Difficulty comes from combining two hazard types in one bar (a sweeper over a checker floor), not from adding more of one type.

## Notes (new) — the route reward

- Amber floating orbs, one tile footprint. Collecting one = +1 note. Consecutive notes without dying = combo multiplier (×1, ×2, ×3, cap ×4).
- Placement: notes go on the *riskier* route through a bar — inside the sweeper's gap, on the tile that is safe for only one beat, between the orbiters. The safe route never has notes. This is how we reward brain over reflex without punishing anyone.
- Score for the run = notes × combo, plus a time bonus. Survival alone gives a score of zero notes; that's fine, the level completes either way. Print notes/combo/deaths on the goal label.

## Placement rules (replaces the brief's table)

| Bar energy | Density | Contents |
|---|---|---|
| ≥ 0.85 | **Gauntlet** | a pulse-plate pattern on the whole bar **plus** one sweeper or gate. 2–3 notes on the risky path. |
| 0.55 – 0.85 | **Pressure** | one hazard type only: orbiter pair, or a sweeper, or a gate. 1–2 notes. |
| 0.35 – 0.55 | **Breather** | open cyan floor, maybe one pit. **Checkpoint marker if this is the first bar of a section.** 1 note in the open. |
| < 0.35 | **Rest** | open floor, nothing. |

Band → type bias (as before): `low` → slammer/gate, `mid` → sweeper/orbiter, `high` → pulse-plate patterns.

Seeded pseudo-random with the bar index, as before, so the level is identical every run.

**Fairness rule (mandatory):** for every beat in every bar there must exist at least one safe tile reachable from at least one safe tile of the previous beat at `PLAYER_SPEED`. Write a validator that checks this from the generated layout before the scene runs, and fail loudly if it doesn't hold. Adapt `tools/check_levels.py` if that's faster than writing a new one.

## Player (changes)

- Joystick → velocity on x and z at `PLAYER_SPEED`. No lane snapping. Clamp to `[ -FIELD_WIDTH/2, +FIELD_WIDTH/2 ]` only by *falling* (no invisible walls at the side); clamp z to the window's front edge with an invisible wall.
- The mesh stays a gray-box capsule in Phase R. But add a **single `MeshInstance3D` "eye"** — a flat black disc on the front face — that rotates to look at the nearest hazard that will be lethal within the next beat. This is the character direction Milko picked (a one-eyed creature); the eye telegraphing danger is gameplay, so it belongs in the gray-box.
- Falling out of the back of the window = death, same freeze/shake/rewind as any death.

## Acceptance (adds to the brief's list)

5. **Readability at width:** the whole field and two bars ahead are on screen on a phone in landscape, and pulse-plate patterns are readable at that size. If they aren't, reduce `FIELD_WIDTH` to 12 before touching anything else.
6. **Choice exists:** on at least three gauntlet bars, there are visibly two ways through, and the notes are on the harder one.
7. **The floor is the game:** a `checker` bar with no other hazard must be survivable *only* by moving on the beat. If you can stand still and live, the pattern is wrong.

## Unchanged from the brief

BeatClock and sync offset, renderer and fog, the 16-second run-up with hazards inert, checkpoints on Standard only, reuse of the glass controls and jump numbers, the branch, the export preset, the LAN serve, staging diffs for approval, and everything under "Out of scope."
