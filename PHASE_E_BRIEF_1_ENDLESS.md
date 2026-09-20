# Phase E — Brief 1: the endless run

**Read after the glitch / monolith job of 2026-09-20 is committed.** Same rules and permissions as the Phase A briefs: one commit per section, report at the top of `prototype/README.md`, stage the diffs and show Milko before pushing. Branch `phase-r-prototype`.

## The idea (decided by Milko, 2026-09-20)

The levels go away. The game is **one endless run: how far can you get with this little character.** Distance is the only score, it is the number on the leaderboard and on the death screen. The level select is no longer what the player sees.

Nothing that is built is thrown away. BeatClock, `rules.gd`, `hazard_math.gd`, the validator, the bots, the hazards, the materials, the creature and the motion pass all stay. What changes is the *shape of a run*: the song loops, the course is generated lap by lap, and difficulty climbs with each lap.

Words used below: a **lap** is one pass through the looped part of the song (72 bars, 576 units, about 2 min 29 s). A **band** is one row of `levels/curriculum.json` — what used to be "a level's knobs".

**Two stages. Stop after Stage 1, export, and let Milko play it on the phone before starting Stage 2.**

---

# Stage 1 — the run

## 1. Knobs per lap, not per game (do this first, it is the big refactor)

Today the knobs are global: `Rules.LEVEL`, `Rules.level()`, `BeatClock.period_beats`, the verdict cache path. In an endless run two laps with **different** bands exist at the same time (the one being played, the next one being generated and validated). So:

- Everything that reads a level knob takes the lap's knob dictionary (or a lap index) as an argument instead of reading one global. That includes the hazard period (`hazard_rate`), `player_speed`, `window_bars`, gaps, openings, plate rules, and what the validator assumes.
- **Proof it changed nothing:** before touching anything, hash the generated layouts of levels 1–6 (`tools/plan_stats.gd`); after the refactor the six hashes must be identical. Put both lists in the report.
- The old per-level path (level select → one level) must keep working. It becomes the dev tool (section 7).

## 2. The song loops

- **One track, looped — Milko's decision. Tempo stays 1.0 on every lap.** `song_tempo` in the curriculum is ignored in the endless run; the `_105` / `_110` files are not used by it. (Faster laps or new songs are a later brief.)
- **Loop region:** bar 1's downbeat (16.602 s) to bar 73's downbeat (165.581 s) = 72 bars, 148.98 s. Bars 73–78 are the fade-out and never play in the endless run. `LOOP_START_BAR := 1`, `LOOP_END_BAR := 73` as constants in `beat_clock.gd`; Milko confirms the seam by ear and may move the end to another 8-bar boundary.
- **The intro is the run-up and plays once** (`song_offset_s` 8.0, as level 1 today).
- **One new audio file, nothing else:** `assets/audio/fuffens_endless.ogg` = the existing track cut at the loop end, imported with loop on and loop offset = 16.602 s. OGG because MP3 padding leaves a gap at the seam. Make it with a script in `tools/` (ffmpeg); if ffmpeg is not on the Mac, stop and ask Milko to export the file from his DAW — do not install things silently.
- **`BeatClock.run_time`:** a clock that only moves forward: song position on the first lap, afterwards `lap × loop_length + position inside the loop`. Detect the wrap (audio position drops by more than half a loop → `lap += 1`); keep the smoothed-clock behaviour from the glitch fix. **Everything that places the world reads `run_time`, never the raw song position**: `z_back = run_time × scroll_speed` keeps growing forever. Run bar = `lap × 72 + bar`; a run bar's energy/band data comes from beatmap bar `((run_bar − 1) mod 72) + 1`.
- **Rewind across the seam** works: seeking to a checkpoint sets both the audio position and `lap`.
- z is absolute and simply grows. No re-origin tricks; float precision is fine for far more laps than anyone will survive.

## 3. The course, lap by lap

- **Band:** lap `k` (0-based) uses curriculum band `min(k + 1, 30)`, except `song_tempo`, `song_offset_s` and `lives`. When `window_bars` / camera distance differ between two laps (2.5 → 2.2, 28 → 26), ease over the first two bars of the new lap — never a snap.
- **Seed — one course per season, the same for every player:** `SEASON_SEED` (a constant) + the lap index seeds the layout. Same seed → same course for everyone, so distances are comparable, the course is learnable (World's Hardest Game DNA), runs can be verified later, and the next season is one number. Per-run random seeds are **not** in this brief.
- **Lap 0 for a new player** (`Progress.graduated == false`) is today's level-1 curriculum, bars 1–72, untouched (demo bars, words, nothing lethal before its demo). The goal gate is gone. **Lap 0 for a graduated player** is band 1 with `structure: mixed` and no demo bars. `graduated` is set, and saved, the first time a player crosses into lap 1. One flag — no per-hazard bookkeeping.
- **Demo bars in later bands stay as the curriculum data says** (they are part of the season's course, identical for everyone).
- **Bar 1 of every lap after the first is a plain bar with a checkpoint** and the glass word `STAGE n`. That makes each lap validate on its own (no hazard spans the seam) and guarantees a rewind never reaches back into an earlier lap.
- **Fairness is not negotiable:** every lap goes through `fairness.gd` exactly as a level does today. If a bar is still unfair after the band's `reroll_passes`, **clear that bar to breather density and log it** — a lap is fair or easier, never unfair, and generation never loops forever.
- **Shipped verdicts:** `levels/verdicts.json` holds the found re-rolls (and cleared bars) for laps 0–9 of the current `SEASON_SEED`, for both lap-0 variants. Produced on the Mac by one `tools/plan_stats.gd` command (document it), loaded before the per-device cache, keyed by `Fairness.VERSION` + seed + lap. With it a phone never validates the first ~25 minutes of a run.
- **Live generation beyond the shipped laps** (and when the file is missing): lap `k + 1` is generated and validated **while lap `k` is played, time-sliced to ≤ 2 ms per frame** — the web export has no threads. It must be ready by bar 60 of lap `k`. If it is not ready by bar 68, finish it with every unvalidated bar cleared to breather density. Never a stall, never an unfair bar.
- **Nodes:** only the current and the next lap exist as nodes. Free lap `k − 1` once the death line is three bars into lap `k`. Monolith chunks follow the same rule.

## 4. Lives and death

- **Graduated players: 3 lives per run.** Death = lose a life, the freeze, rewind the song to the last checkpoint — exactly what levels 2+ do today. No lives left = the run is over → the end screen (section 6).
- **New players: lap 0 costs no lives** (exactly level 1 today). Lives start at 3 when they cross into lap 1.
- **Retry is fast:** RETRY starts a new run with a run-up of `RETRY_RUNUP_S := 4.0` instead of 8.6 s (start the song later into the intro). First run of a session keeps the full run-up.
- `rules.gd` still decides what is lethal and is **not changed** by this section. `track_test.gd` stays the referee.

## 5. Distance, and what notes are for now

- **Distance:** `distance_m = floor(furthest z the player has reached − z of bar 1's start line)`, 1 unit = 1 m. It never goes down — a rewind does not take distance away. `Progress.best_distance` is saved per `SEASON_SEED`.
- **HUD:** the distance as the big number, top centre; `BEST 1 240 m` small under it; lives; the shield meter. The old score, the combo multiplier readout and the song progress bar leave the HUD. The score maths (`distance_points`, `death_penalty`, `note_bonus`) is no longer shown or stored in this mode.
- **Best line:** a thin amber line across the field at the player's best distance (amber = goal; build it like the death line). Crossing it pulses the rim amber for one bar (Brief 3's `pr_rim_amber`).
- **Notes no longer score. They charge a shield.** Each note adds the current combo (1–4) to a meter; at `SHIELD_COST := 30` the shield arms and the meter holds until it is used (one shield at most). With a shield, a **hazard or plate** death is absorbed: no life lost, no rewind, the shield pops, `SHIELD_GRACE_S := 1.0` of invulnerability to hazards and plates. **Falling and the death line always kill.** The decision lives in the referee (`track_test.gd`), after `Rules.death_cause()` — `rules.gd` stays untouched.
- **Shield look (flagged to Milko as a visual addition):** a thin glass bubble around the creature in `SAFE` cyan using the existing gloss/glass shader, popping with the existing clay-pop particles recoloured cyan. HUD meter: a small glass ring that fills amber and turns cyan when armed. `palette.gd` colours only.
- Report how many notes each of laps 0–5 offers, so `SHIELD_COST` can be tuned to roughly one shield per lap for a player who takes half of them.

## 6. End screen (minimal — the share / roast screen is its own brief)

Distance big, `BEST`, `NEW BEST` when it is, then **RETRY** (big) and **MENU**. Glass style as the HUD. Until Stage 2 exists MENU goes to the dev level select.

## Stage 1 acceptance

- Layout hashes of levels 1–6 identical before / after section 1.
- Validator bot: **0 deaths through laps 0–5**, for both lap-0 variants.
- Seam: around every lap seam log `run_time`'s per-frame delta — never negative, never more than two frames' worth. Milko judges the audio seam by ear on the phone.
- A death in the first bars of lap 1 rewinds to lap 1's bar-1 checkpoint, song and world in sync.
- Live generation proven: delete `levels/verdicts.json`, play laps 0 → 2 on the Mac web build — no stall, worst frame under 25 ms on the frame-time readout while the next lap is generating. Report time to generate + validate each of laps 0–9 on the Mac, and how many bars per lap had to be cleared (**target: ≤ 2 per lap on laps 0–5**).
- Human bot, graduated, 3 lives, 20 seeds: **report only** the median distance and median run length in seconds and what killed it. No tuning — that is Milko's call after he has played it. (The level-1 orbiter wave stays as it is: Milko played it on the phone on 2026-09-20 and called the pace and difficulty right.)
- Export `build/phase-r`, update "Where we are", **stop for the phone test.**

---

# Stage 2 — menu and leaderboard

## 7. Main menu

- New scene `prototype/menu.tscn`; it becomes `run/main_scene.phase_r`. The level select stays in the repo as a **dev tool only** (reachable when `Progress.UNLOCK_ALL` is true): picking "level N" there starts an endless run at lap `N − 1`, so a band can be tested without playing up to it.
- **Look: the game's own world, live, not a flat screen.** A short strip of the stone field floating in the grey fog, two monoliths behind, **the creature standing on it facing the camera** (the one open eye is the logo) with its breathing, beat squash and glance idle. Title `THE LAST GAME` at the top, `BEST 1 240 m` under it, then three glass buttons: **PLAY** (large), **LEADERBOARD**, **SETTINGS**. Existing glass style and `palette.gd` only — no new colours, no new fonts, no image textures.
- No music in the menu (the web needs a tap before audio anyway): PLAY starts the song, which is the run-up.
- SETTINGS: sound on/off, and the existing account panel (`ui/account_panel.gd`: consent → register / login → manage / delete, country). Nothing else.
- Tap targets ≥ 48 pt, landscape, clear of the notch and the home bar (`viewport-fit=cover` is already on).

## 8. Leaderboard — wire the run into what already exists

Talo is built and verified (`autoload/talo.gd`, `autoload/consent.gd`, `ui/leaderboard_screen.gd`, `docs/TALO_SETUP.md`). Reuse it; do not write a second client.

- **One new board: distance, higher is better, one entry per player, replaced only by a better run.** Write the exact click-by-click steps for creating it into `docs/TALO_SETUP.md` — Milko does it in the Talo dashboard. The six old boards are left alone.
- **Entry props:** `country` (as today), `season` (= `SEASON_SEED`), `build`, and for later cheat checks `laps`, `run_seconds`, `deaths`. A distance greater than `run_seconds × scroll_speed + window depth` is impossible — nothing to enforce yet, but the data must be there from day one because prizes are planned.
- **Screen:** the existing leaderboard screen, shown from the menu, with two tabs only in this mode: **GLOBAL** and **MY COUNTRY** (the difficulty tabs and the PROGRESS / FINISHERS switch are hidden here). Rows: rank, name, country flag if shared, distance in metres. The player's own row keeps its accent.
- **Submitting:** on run end, logged-in players submit automatically when the run beats their best; the end screen then shows `#12 GLOBAL · #3 SWEDEN`. Guests see `JOIN to post your distance` (the existing `join_requested` path). Guest-first stays: nobody is asked to register before they have played.
- Check Talo's docs for a monthly refresh interval on leaderboards and **report** whether it exists — do not build seasons on it yet.

## Stage 2 acceptance

- Screenshots, 2400×1080, web renderer: `docs/screenshots/e-menu.png`, `e-leaderboard-global.png`, `e-leaderboard-country.png`, `e-end-screen.png`.
- Register → play → die → distance appears on the board → appears under the country tab → delete account removes it: against the real Talo API, stated in the report.
- A guest can open the leaderboard and read it without an account.
- Frame-time readout on the menu scene: no worse than in the run.

## Not in this brief

The share / roast death screen · skins and any shop · prizes, seasons and sponsor logic · server-side score verification · tempo changes per lap or more songs · per-run random courses · SFX · native builds · itch.io.
