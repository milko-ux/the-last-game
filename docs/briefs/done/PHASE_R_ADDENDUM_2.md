# Phase R — Addendum 2: the first two minutes

**Read after PHASE_R_BRIEF.md and PHASE_R_ADDENDUM_1.md. Where this conflicts with either, this wins.** BeatClock, sync, the single death decision in `rules.gd`, the death log, the headless autoplayer, the renderer and fog rules, and "stage diffs for approval" are all unchanged.

## Why (Milko's playtest, 2026-09-15)

Level 1 killed the designer repeatedly before he understood why. The camera sits too low and close, the field is too narrow, and every hazard type is live from the first downbeat. The research is unambiguous: players decide in the first minutes. We get roughly five deaths per download to make them want a sixth. This addendum builds those minutes.

Reference image: `docs/concept/field_monolith.png` (Milko will drop it there). That framing — high, wide, looking down the length of the field, whole field plus two bars ahead in one shot — is the target.

## 1. Camera and field (replace Addendum 1's numbers)

```
FIELD_WIDTH   = 18.0     # nine 2-unit tiles across (was 14 / seven)
WINDOW_DEPTH  = 2.5 * BAR_LENGTH   # unchanged
```

Camera: parent to the window centre as before, local offset `(0, 17, -10)`, look-at the window centre. That gives roughly a 58° pitch. **FOV 50** — the narrower FOV is what makes it look like the concept art instead of a fisheye. Verify by screenshot at a phone landscape resolution (e.g. 2400×1080) that the full nine-tile width and at least two bars ahead are in frame with margin. If the width doesn't fit, raise the camera before you narrow the field.

The back edge of the window must be **visible**: draw it as a thin cyan line across the field, one tile-row above the bottom of the frame, so falling out the back is never a surprise. Death by back edge happens when the player's z is below the line, not below the screen.

## 2. Level 1 is a curriculum

The placement generator gains a `curriculum` input: a list of `(from_bar, allowed_types, density_cap)` entries. Level 1 for this song:

| Bars | Section role | Allowed hazards | Notes |
|---|---|---|---|
| intro (0–16 s) | rehearsal | none lethal | all plates run their bar-1 pattern in warning colour on the beat grid; player free to move |
| 1–8 | wave 1 | **plates only**, `row` and `checker` patterns only | bar 1 is a demo bar (see §3) |
| 9–16 | breather | open floor, 1–2 notes, checkpoint at bar 9 | |
| 17–24 | wave 2 | plates + **sweepers** | bar 17 is a sweeper demo bar |
| 25–31 | breather | checkpoint at bar 25 | |
| 32–40 | wave 3 | plates + sweepers + **gates** | bar 32 is a gate demo bar |
| 41–48 | breather | checkpoint at bar 41 | |
| 49–56 | wave 4 | + **orbiters** (forced: at least two orbiter bars in this wave) | bar 49 is an orbiter demo bar |
| 57–78 | wave 5 / outro | any type, but **density cap = Pressure** (never Gauntlet) and no `spiral` patterns | the level ends on a win, not a wall |

Slammers and pits do not appear in level 1 at all. Level 1 has **no lives**: death = freeze 0.25 s, rewind to checkpoint, continue. No death screen, no roast, no life counter shown. Lives and the death/share screen begin at level 2. Do not build level 2 in this phase; just make the level-1 flag exist.

Hard rule, enforced by the generator: **no hazard type may become lethal before its demo bar has played.**

## 3. Demo bars — nothing kills you before it has shown you

The first bar in which a hazard type appears is a demo bar:

- The hazard runs its full behaviour for the bar but in the **warning colour** (dark magenta) and is non-lethal.
- The creature's eye locks onto it for the whole bar (the existing eye behaviour, but forced to this target).
- One word appears above the field for the bar, in the same glass style as the UI: `FLOOR`, `WALL`, `GATE`, `ORBIT`. Fades on the next downbeat. This is the only text allowed in play. Do not add sentences, arrows or hands.
- The bar after a demo bar contains exactly that hazard type, live, at Pressure density, nothing else.

The rehearsal intro is the plate demo for the whole field: from `song_time() = 0` to the first downbeat, every plate in bars 1–8 plays its pattern in warning colour on the beat grid (BeatClock already knows the grid before the first beat — extrapolate backwards from `beats_s[0]` at the beat interval). The player can walk over them freely.

## 4. Progress bar

A thin bar across the top of the screen, glass style, full width:

- Fill = `song_time() / duration`. 
- Small ticks at each checkpoint bar.
- A thin marker at the furthest `song_time()` reached this session ("best"). Persist it per level in the existing `progress.gd` autoload so it survives restarts.
- On death, the bar does not reset; the fill jumps back to the checkpoint and the best marker stays. That gap is the retry hook.
- On reaching the goal: bar fills, then the notes/combo/time label as before.

## 5. The "five deaths" test

Add a second bot next to the validator-path autoplayer: **`human_bot`**.

- Reacts to a hazard becoming lethal only after a 200 ms delay.
- Chooses the safe tile nearest to its current position rather than the validator's optimal path.
- 10 % of the time it picks the second-nearest safe tile instead.
- Never goes for notes.

Run it through level 1 with a fixed seed set of 20 runs. **Acceptance: median deaths ≤ 5, and 90 % of runs reach the goal within 8 deaths.** If it fails, loosen in this order: (1) reduce plate lethal window from half a beat to 40 %, (2) widen sweeper gaps by one tile, (3) reduce wave-5 density. Never speed up or slow down the song.

Also run the validator-path bot as before; it must still finish with zero deaths.

## 6. Small things carried over from the last report

- Keep the plate "warn for a full beat before firing" behaviour from the last build.
- Keep walls see-through and the player drawn on top.
- Jump-spam on a checker bar: **not fixed in this addendum** — leave it, it is not what will lose a new player. Noted for placement v2.
- Fog start 26.

## Report back with

The camera screenshot at phone resolution, the human_bot table (20 runs: deaths, reached goal y/n), the validator-path result, and the LAN URL. Stage for approval, do not push.
