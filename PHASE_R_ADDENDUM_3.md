# Phase R — Addendum 3: concrete before abstract

**Read after Addendum 2. Where this conflicts with Addendum 2 §2 (the curriculum) or with hazard rates anywhere, this wins.** Everything else in the brief and addenda 1–2 stands: camera, field width, demo bars, no lives on level 1, progress bar, the bots, staging for approval.

## Why (Milko's playtest, 2026-09-16)

Level 1 opened with a full-field checkerboard flipping on every beat. At 117 BPM that is a half-second flip across the whole floor — the most abstract and fastest mechanic in the game, delivered first. Milko could not understand what was killing him. The curriculum order in Addendum 2 was wrong: it went abstract → concrete. It must go the other way.

## 1. Hazard rate per level (new, global)

Hazards don't act on the beat by default. Each level has a rate, and every hazard's timing in `rules.gd` is expressed in that rate:

```
HAZARD_RATE_LEVEL_1 = "bar"        # everything acts on the downbeat, once per bar (~2.0 s at 117 BPM)
HAZARD_RATE_LEVEL_2 = "half_bar"   # beats 1 and 3
HAZARD_RATE_LEVEL_3+ = "beat"      # what the prototype does now
```

The song and the world's scroll speed do not change. Only how often hazards do something. The camera's FOV punch stays on every downbeat regardless.

Warning windows scale with the rate: a hazard warns for one full period of its rate before it fires (one bar in level 1).

## 2. New hazard: Volley

"Something thrown at you." A magenta orb fired from one side of the field, travelling along one tile-row (constant z) across the full width in exactly one period of the hazard rate. Telegraph: a thin dark-magenta line along that row for one period before it fires, and a small dark-magenta muzzle block at the field edge it comes from. Lethal only on contact with the orb itself, which is one tile wide. Jumpable. Direction (left or right) seeded per instance. Add it to `rules.gd` as pure math like the others, add it to the validator and both bots, and give it the demo word `VOLLEY`.

Slammers (from above) already exist; together with volleys they are the "thrown" family.

## 3. Level 1 curriculum (replaces Addendum 2 §2 table)

| Bars | Role | Allowed | Rules for this wave |
|---|---|---|---|
| intro (0–16 s) | rehearsal | none | the **gate** of bar 1 rehearses: its opening moves on each bar of the intro grid, in warning colour. Not plates — there are no plates until wave 5. |
| 1–8 | wave 1: **doorways** | gates, pits | one gate per two bars (bars 1, 3, 5, 7), opening 5 tiles wide (was 4), opening moves once per bar. One pit somewhere in bars 2/4/6/8, 2 units deep in z. Plain landing rows before and after every gate. Bar 1 is the gate demo bar. |
| 9–16 | breather | notes, checkpoint at 9 | |
| 17–24 | wave 2: **thrown** | slammers, volleys | bar 17 is the volley demo bar, bar 18 the slammer demo bar (two demos, two words). Then one thrown hazard per bar, never two in the same bar. |
| 25–31 | breather | checkpoint at 25 | |
| 32–40 | wave 3: **walls** | sweepers (+ one gate allowed) | bar 32 is the sweeper demo bar. One sweeper per bar max, gap 5 tiles (was 3), plain rows either side. |
| 41–48 | breather | checkpoint at 41 | |
| 49–56 | wave 4: **orbiters** | orbiters (+ gates allowed) | bar 49 demo. Orbit period = one bar (unchanged); single orbiters only in level 1, never the opposite-rotation pair. |
| 57–64 | wave 5: **floor** | plates only | bar 57 demo. **Plates cover at most 4 tiles per bar**, placed as a short `row` segment or a 2×2 block, never `checker`, never `spiral`, never `column_wave`. Warn one full bar, lethal on the downbeat only, lethal window 40 % of a beat as now. |
| 65–78 | outro | any of the above at Breather density | ends on the goal. Nothing new, nothing dense. |

Hard rules the generator enforces for level 1:
- Never two hazard **types** in the same bar.
- Plates never before bar 57.
- `checker`, `spiral`, `column_wave` patterns do not exist in level 1 or level 2. They are level 3+ material and their introduction gets its own demo bar there.
- The "nothing lethal before its demo" rule from Addendum 2 §3 stays, and now also applies per **pattern**, not just per type.

## 4. Difficulty knobs the later levels will turn (define now, use later)

These become parameters of the generator so levels 2–30 are data, not code:

```
hazard_rate        bar | half_bar | beat
plate_coverage     0.0 – 0.7     # fraction of a bar's tiles that may be plates
plate_patterns     [row, block, checker, column_wave, spiral]   # allowed set
gate_opening_tiles 3 – 5
sweeper_gap_tiles  3 – 5
types_per_bar      1 | 2
orbiter_pairs      false | true
```

Level 1 = bar / 0.12 / [row, block] / 5 / 5 / 1 / false. Do not build level 2 now; make the knobs exist and print them at level start.

## 5. Bots and acceptance

Unchanged: validator-path bot must finish with zero deaths; human_bot 20 seeds, median ≤ 5 deaths, 90 % reach the goal within 8. With bar-rate hazards and this curriculum the human_bot should pass easily — if it doesn't, the bot is broken, not the level, and you time-box it as before: one fix pass, then report the numbers.

## 6. Report back with

Phone-resolution screenshot of bar 1 (a gate, a plain field, nothing else on screen), the human_bot table, validator result, the LAN URL. Export and serve **before** the bot batch so Milko can play while it runs. Stage, do not push.
