# The Last Game — Project Brief for Claude Code

## Who you're working with
Milko — musician/creative director (ODZ collective), self-taught builder with **zero prior coding or game-dev background**. All development happens through AI assistance. Communicates in Swedish and English.

**How to work with Milko:**
- Zero prior Godot/GDScript knowledge. The first time you use a technical term in a session (scene, node, script, signal, shader, commit, export, etc.), give a one-line plain-English explanation — an analogy helps. Never say "just tweak the X function" — always state the exact file path and show the exact code change.
- After finishing a task, summarize in plain English: what changed, why it matters for how the game looks/feels/plays, and whether Milko needs to do anything (like re-testing on a phone).
- Milko is hands-off from the terminal by preference now that you're running locally — execute builds and commands directly rather than dictating steps, but still narrate what you're doing and why in plain language.
- Mobile-first lens always: touch responsiveness and phone hardware performance take priority over desktop assumptions.
- Responds well to honest, data-backed pushback — don't just agree with an idea that works against the game or the schedule. Say so, explain why, and propose the alternative.

## What this project is
A mobile isometric maze game built in Godot 4 (GDScript).

- **GitHub:** github.com/milko-ux/the-last-game
- **Live/playable (web test build):** mivasthecreator.itch.io/the-last-game
- **Target platforms:** iOS, Android (native) — itch.io web export is the testing loop before native builds

Design synthesis: **World's Hardest Game** (punishing top-down dodge mechanics, instant restart) + **Super Mario** (jump mechanic, lives system, accessible-but-hard philosophy) + **Marble Madness** (isometric pseudo-3D aesthetic). This isn't a straight clone — the goal is a more visually compelling, more complex version of that formula, still just as brutal.

## Roadmap
Work happens in this order unless Milko says otherwise — don't jump ahead to a later phase without flagging it first.

- **Phase 0 — Foundation** ✅ done. Core prototype: isometric maze, jump mechanic, hazards (spinner/sweep/chain/chaser), 5 levels, deployed to itch.io.
- **Phase 1 — Mobile Feel** 🔄 in progress. Glass touch controls (confirmed working well on-device), responsiveness, portrait handling, performance on real phone hardware.
- **Phase 1.5 — Architecture Refactor** ⏭️ next. Move off the single-file/single-scene setup: player and each hazard type become their own reusable scenes, levels become data a loader reads instead of living inline in the script, and the neon look moves from hand-drawn `_draw()` calls to real Godot shaders (glow/bloom, animated pulse, particle trails). Goal: identical visual identity, more capable foundation for everything after it. Existing logic gets relocated, not rewritten from scratch.
- **Phase 2 — Core Loop & Progression.** 3-lives system, difficulty unlock progression (Standard/Hard/Extreme), shareable death screen polish, guest-first onboarding.
- **Phase 3 — Backend & Persistence.** Talo leaderboard integration (global + country-selected), registration deferred to results screen, GDPR/EU consent handling.
- **Phase 4 — Monetization.** Rewarded video ads only, never on death.
- **Phase 5 — Native Build & Store Prep.** iOS export (Xcode/provisioning/App Store Connect), Android export (Play Console/signing), store listing assets, TestFlight/internal testing.
- **Phase 6 — Launch.** Store submission, review, release, post-launch monitoring.

## Non-negotiables — flag before touching any of these
Do not change or drift from these without explicitly flagging it to Milko first:

- **Visual identity:** dark synthwave / neon aesthetic. Color logic is fixed — magenta = death, cyan = safe, amber = goal.
- **Touch controls:** frosted-glass, Apple-style. Milko has confirmed on-device that the current glass controls feel good — don't regress this.
- **Core loop:** 3-lives system. Losing all 3 lives resets the full loop to level 1 (no mid-run checkpoints).
- **Death screen:** must stay shareable — roast-style brag text plus clipboard copy. This is a core viral/retention mechanic, not a nice-to-have.
- **Difficulty:** Standard/Hard/Extreme are unlocked through play progression, not chosen upfront in a menu.
- **Ads:** rewarded video only. **Never show an ad on death** — this was explicitly rejected earlier and should not resurface.
- **Onboarding:** guest-first. Registration is deferred to the results screen, not forced upfront.
- **Data & privacy (GDPR/EU):** any feature that collects or stores player data (accounts, leaderboards) needs consent handling before it ships. Flag this before implementing Phase 3.

**Note on Phase 1.5:** moving from hand-drawn rendering to scenes/shaders is a pre-approved architecture change, not a violation of the visual non-negotiables above — the goal is the identical look on a better-built foundation. Still flag it if the actual visual result (glow intensity, exact colors, control feel) ends up noticeably different from what's live now.

## Current status
Currently finishing **Phase 1**, about to start **Phase 1.5** (see Roadmap above).

- Deployed and playable on itch.io; GitHub repo is live and up to date.
- Frosted-glass touch controls shipped and confirmed to feel good on an actual phone.
- Known fixes already in place: missing `main.gd` resolved, export templates installed (required "Go Online" in Godot's offline mode), portrait letterboxing fixed via itch.io embed settings + Godot stretch mode.

## Your build/test workflow in this repo
Godot and its export templates are already installed locally — use them directly rather than asking Milko to run commands by hand.

1. Before making changes, get oriented: check current scene structure, recent git history, and note anything relevant that isn't yet documented in "Repo structure" below.
2. For build verification, run a headless export (`godot --headless --export-release "<preset>" <output_path>`) and check the log for errors/warnings before reporting a change as done.
3. For the web build, you can drive the itch.io page via browser to visually check for regressions (broken layout, wrong colors, control visibility).
4. **Never commit or push to GitHub without staging the diff and getting Milko's explicit go-ahead first** — the itch.io build is live, and a bad push breaks what's currently playable.
5. Any change that touches the non-negotiables above gets flagged *before* you implement it, not after.
6. This is a solo project — no pull requests needed. Once Milko approves a change, push straight to `origin/main`.
7. Keep this file (`CLAUDE.md`) current — when a phase completes, update its status marker in the Roadmap section above.

## Repo structure
*Note: this reflects the pre-Phase-1.5 structure. Once the architecture refactor lands, this section needs a rewrite — don't treat it as current after Phase 1.5 starts.*

The whole game is deliberately small — one scene, one script, no autoloads yet.

- **`project.godot`** — engine config. Name "THE LAST GAME", main scene `main.tscn`, base viewport 960×540, stretch mode `canvas_items` / aspect `expand` (this is what makes the itch.io embed scale instead of clip), renderer set to `mobile`, features `4.7` + `Mobile`.
- **`main.tscn`** — the entire game: a single `Node2D` named "Main" with `main.gd` attached. No child nodes — everything (level geometry, hazards, player, touch controls, HUD, results screen) is procedural, drawn each frame in `_draw()`. No other scenes exist yet (no menu scene, no pause scene).
- **`main.gd`** — the whole game logic in one file (~830 lines), currently labelled "Phase 2d" in its header comment. Organized top-to-bottom as:
  - **Tuning constants** (top of file): movement/physics (`TILE`, `PLAYER_SPEED`, `JUMP_VELOCITY`, `GRAVITY`), isometric projection (`ISO_X`, `ISO_Y`, `WALL_H`), touch control sizing (`STICK_RADIUS`, `JUMP_BTN_RADIUS`, `CTRL_MARGIN`), hazard tuning, and the full non-negotiable color palette (`COL_HAZ` = magenta death, `COL_EDGE`/`COL_PLAYER` = cyan safe, `COL_GOAL` = amber).
  - **`levels` array** — hardcoded level data as ASCII grids (`#` wall, `.` floor, `P` start, `O` pit) plus a `hazards` array per level. 5 levels currently defined. Hazard types: `sweep` (back-and-forth on a line), `patrol` (same, different framing), `chain` (orbits a pivot point), `chaser` (homes in on the player).
  - **Runtime state vars** — lives (3-life system per the non-negotiables), `current_level`, `total_deaths`, results-screen state, and multi-touch tracking (`stick_touch_id`, `jump_touch_id` — supports simultaneous move+jump).
  - **`_ready()` / `_process()`** — game loop: hazard update → player movement → gravity → collision checks → redraw. Results screen and death-pause states short-circuit the loop.
  - **Level loading** (`load_level`, `start_new_run`, `cell_center`, `cell_char`, `is_wall`) — reads the ASCII grid.
  - **Movement** (`move_player`, `screen_dir_to_world`, `blocked`, `jump`, `apply_gravity`) — grid-based movement with axis-separated collision (slide along walls), plus jump/gravity for the pit-clearing mechanic. `screen_dir_to_world` converts joystick drag direction into isometric world-space movement.
  - **Hazards** (`update_hazards`) — recomputes hazard positions per frame from level data + elapsed time.
  - **Collisions** (`check_collisions`, `die`, `enter_results`) — pit/hazard death checks (skipped for non-chain hazards while airborne, i.e. jumping clears ground hazards), goal-reached → next level or results.
  - **Results/share** (`brag_text`, `copy_brag`) — generates the roast-style brag text (tiered by death count) and copies it to clipboard. This is the shareable death-screen mechanic called out as non-negotiable.
  - **Input** (`_input`) — touch (left half = joystick, right half = jump), keyboard fallback (Space/R/C), and mouse fallback for desktop browser testing.
  - **Isometric projection** (`iso_origin`, `to_screen`, `tile_quad`) — world-to-screen transform.
  - **Drawing** (`_draw()` and helpers) — everything is immediate-mode `draw_*` calls: floor tiles, wall cubes (painter's-algorithm sorted by col+row), goal marker, hazards, player, HUD, frosted-glass touch controls (`draw_glass_disc`), and the results screen. Portrait orientation shows a "ROTATE YOUR PHONE" message instead of the game.
- **`export_presets.cfg`** — single export preset named "Web", output path `game test 1/index.html`. This is the itch.io test-build export target. Committed to git (small config, not a build artifact).
- **`game test 1/`** — the exported web build (index.html/js/wasm/pck + assets). Build artifact, not source — gitignored.
- **`.gitignore`** — excludes `game test 1/` (build output) and `.DS_Store` (macOS junk file) from version control.
- **`CLAUDE.md`** — this file. The shared brief Claude Code reads at the start of every session: the plan, the non-negotiables, and where the project stands. Keep it updated as phases complete.
- **`icon.svg`** — app/project icon.
- No autoloads/singletons, no `.tscn` subscenes, no resource folders (sprites/audio) yet — all visuals are vector-drawn and there's no audio in the codebase yet.

## Tools & resources
- **Engine:** Godot 4 (GDScript)
- **Version control:** GitHub — github.com/milko-ux/the-last-game
- **Publishing/testing:** itch.io — mivasthecreator.itch.io/the-last-game
- **Asset generation:** Higgsfield (concept art, logo, cover art)
- **Leaderboard backend:** Talo (planned, not yet integrated)
