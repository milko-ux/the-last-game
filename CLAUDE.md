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
- **Phase 1 — Mobile Feel** ✅ done. Glass touch controls (confirmed working well on-device), responsiveness, portrait handling, performance on real phone hardware. Closed out with a framerate-independent pit-death fix and haptics on death/win.
- **Phase 1.5 — Architecture Refactor** 🔄 in progress. Goal: identical visual identity, more capable foundation for everything after it. Existing logic gets relocated, not rewritten from scratch.
  - ✅ Levels become data a loader reads (`levels.json`) instead of living inline in the script.
  - ✅ Player and each hazard type are their own reusable scenes; projection and palette moved to autoloads; UI moved to its own CanvasLayer.
  - ✅ Real glow/bloom on the world via HDR 2D + a `WorldEnvironment`. Scoped to the world only — the glass touch controls are excluded by sitting on their own CanvasLayer.
  - ⏭️ Remaining: particle trails (hazard/player motion trails). The goal marker already has an animated pulse from Phase 0.
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
Mid **Phase 1.5** — the code restructure is done, shaders are what's left (see Roadmap above).

- GitHub repo is live and up to date.
- ⚠️ The itch.io page (`mivasthecreator.itch.io/the-last-game`) returned "we couldn't find your page" on 2026-08-21, so the listing is currently private/unlisted/draft rather than publicly playable. Local testing does not depend on it — export and serve the build locally instead.
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
As of Phase 1.5, the game is split into small single-purpose files instead of one big script. A "scene" in Godot is a reusable building block (a `.tscn` file); an "autoload" is a script Godot loads once at startup that any other script can call.

**Autoloads (global helpers):**
- **`autoload/iso.gd`** (`Iso`) — the isometric projection. The world underneath is a plain flat grid; isometric is only how it's DRAWN, which is what keeps level files readable as text. Everything that draws calls `Iso.to_screen()` so they all agree on where things are. Also owns `TILE`, `WALL_H`, and `set_board_size()` — the view now centres itself from the actual level dimensions, so a bigger maze in `levels.json` just works.
- **`autoload/palette.gd`** (`Palette`) — the fixed colour language (magenta = death, cyan = safe, amber = goal). Every entity reads colours from here so the meaning stays consistent. **Non-negotiable — see above.** Also owns `glow()` and the `NEON` multiplier that drive the bloom (see "How the glow works" below).

**Entities (each one is its own scene):**
- **`entities/background.gd`** — the far starfield, drawn behind everything and scaled to COVER the screen so stars never stretch out of shape. (Real parallax needs a moving camera; this game's view is fixed per level, so there's nothing to move against yet — this is the node to give a slow scroll to if that changes.)
- **`entities/board.gd`** — draws the static world: rock floor tiles, pits, wall cubes (sorted back-to-front), the hanging island underside, and the goal marker. See "How the rock textures work" below.
- **`entities/player.gd`** — position, jump, gravity, wall collision (axis-separated so you slide along walls instead of sticking), and its own drawing. The physics numbers are unchanged from the original, so the feel is identical.
- **`entities/hazard.gd`** — shared base class. Owns the box-vs-circle hit test (unchanged, so difficulty is unchanged) and the `jumpable` flag.
- **`entities/hazard_line.gd`** — covers `patrol` and `sweep`; slides between two points. Low, so jumping clears it.
- **`entities/hazard_chain.gd`** — orbits a pivot. TALL: `jumpable = false`, so you must go around.
- **`entities/hazard_chaser.gd`** — homes in on the player. Low.

**UI:**
- **`ui/ui.gd`** — HUD, the frosted-glass touch controls, the results/share screen and the portrait "rotate your phone" prompt. Sits on a `CanvasLayer` so it always draws on top of the world. Owns all touch/mouse input and reports up via signals (`jump_pressed`, `restart_requested`, `copy_requested`). **The glass control drawing here is carried over unchanged from what Milko confirmed on-device — treat edits to it as touching a non-negotiable.** The CanvasLayer is also what will let world glow/bloom be added later without blooming the controls.

**Root:**
- **`main.gd`** — now just the referee: owns the run (lives, deaths, current level), loads `levels.json`, spawns entities, and decides when you died or won. Also the share/brag text and keyboard shortcuts (Space/R/C).
- **`main.tscn`** — scene tree: `Main` → `WorldEnvironment` (the glow settings), `Board`, `Entities` (hazards then player, so the player draws on top), `UI` (CanvasLayer) → `Screen`.

### How the rock textures work (read before touching it)
All art lives in `assets/`, downscaled from the originals (the source art was 2048²/2752px, ~24MB total — far too heavy for a phone; it's 3.6MB now):

- `space_far.png` — starfield background
- `rock_floor.png` — tiled across walkable floor tiles AND wall tops
- `rock_wall.png` — tiled across the vertical wall faces
- `island_underside.png` — the hanging underside (transparent PNG)

Three things that are easy to get wrong here:

1. **UVs come from WORLD position, not from the tile.** That's what makes the rock flow continuously across neighbouring tiles instead of restarting on each one. `_world_uvs()` does this; `texture_repeat` is enabled on the Board in `_ready()`.
2. **Wall faces need a much bigger texture scale than the floor** (`WALL_TEX_WORLD` 900 vs `FLOOR_TEX_WORLD` 384). The isometric angle squashes a wall face to roughly a third of its width on screen, so at floor scale the rock detail compresses into what looks like a picket fence.
3. **The island underside is narrower than the board on purpose.** Its art has a straight top edge, but the board is a rhombus whose thickness tapers to nothing at the left and right corners — so a straight edge has nothing to hide behind out there and shows as a hard horizontal line across the screen. `0.66 × board width` keeps both top corners inside the board's thickness. It's drawn FIRST so the board's own rock sides cover the join.

The rock is deliberately dark — the `TINT_*` constants multiply the mid-grey source art down so neon stays the brightest thing on screen. Raise them to lighten the rock. Pits stay flat black (no texture) so they still read as holes.

### How the glow works (read before touching it)
The game renders in HDR (`rendering/viewport/hdr_2d` in `project.godot`), which lets a colour be *brighter than pure white*. The bloom pass in `main.tscn` only picks up things brighter than white (`glow_hdr_threshold = 1.0`). So:

- Anything drawn through `Palette.glow(colour, amount)` blooms. Anything not drawn through it never does.
- That's why the dark floor stays dark, and why the frosted-glass touch controls keep their exact look — `ui/ui.gd` never calls `glow()`, and the UI CanvasLayer is excluded via `background_canvas_max_layer = 0`.
- **Boost amounts are per-element on purpose.** A colour with a zero channel (cyan `EDGE`, `#00fff2`) can be boosted hard (2.5x) and keeps its hue. A colour with high channels (the player's `#7dfaff`) clips toward white and goes grey-white if pushed — so those get a gentle 1.2–1.3x. If you raise a boost and something turns white, that's why.

**Two switches if performance is a problem on a real phone:** set `Palette.NEON` to `1.0` to drop the over-bright everywhere, or `glow_enabled = false` on the Environment in `main.tscn` to remove the bloom pass entirely. Both are safe, reversible, and leave gameplay untouched.
- **`levels.json`** — all level data: ASCII grids (`#` wall, `.` floor, `P` start, `G` goal, `O` pit) plus a `hazards` list per level. 5 levels. **Milko can edit this file directly in any text editor to design levels — no Godot or code needed.** The `_readme` block at the top documents the symbols and hazard types.
- **`project.godot`** — engine config. Base viewport 960x540, stretch `canvas_items` / aspect `expand` (what makes the itch.io embed scale instead of clip), `mobile` renderer, and the two autoloads above.
- **`export_presets.cfg`** — single "Web" preset, output `game test 1/index.html`. Committed (small config, not a build artifact).
- **`game test 1/`** — the exported web build. Build artifact — gitignored.
- **`.gitignore`** — excludes `game test 1/`, `.DS_Store`, `.godot/`.
- **`CLAUDE.md`** — this file. Keep it updated as phases complete.
- **`icon.svg`** — app/project icon.
- Still no sprite/audio assets — all visuals are vector-drawn, no audio yet.

## Tools & resources
- **Engine:** Godot 4 (GDScript)
- **Version control:** GitHub — github.com/milko-ux/the-last-game
- **Publishing/testing:** itch.io — mivasthecreator.itch.io/the-last-game
- **Asset generation:** Higgsfield (concept art, logo, cover art)
- **Leaderboard backend:** Talo (planned, not yet integrated)
