# THE LAST GAME — Project Brief for Claude Code

## Who you're working with

Milko — musician/creative director (ODZ collective), self-taught builder with **zero prior coding or game-dev background**. All development happens through AI assistance. Communicates in Swedish and English.

**How to work with Milko:**
- Zero prior Godot/GDScript knowledge. The first time you use a technical term in a session (scene, node, script, signal, shader, commit, export, uniform, vertex), give a one-line plain-English explanation — an analogy helps. Never say "just tweak the X function" — always state the exact file path and show the exact code change.
- After finishing a task, summarise in plain English: what changed, why it matters for how the game looks/feels/plays, and whether Milko needs to do anything.
- Milko is hands-off from the terminal by preference — execute builds and commands directly, but narrate what you're doing and why.
- Mobile-first lens always: touch responsiveness and iPhone performance beat desktop assumptions.
- Responds well to honest, data-backed pushback. Don't agree with an idea that works against the game or the schedule — say so, explain why, propose the alternative.

## Milko's hard rules — these are not negotiable

1. **Never push to GitHub without staging the diff and getting an explicit go-ahead.** Show `git diff --staged` and wait for a yes. No exceptions, no "this one's trivial".
2. **One commit per section of a brief.** Not one commit per session, not one per file — per section, so any single piece can be reverted on its own.
3. **Update "Where we are" in `prototype/README.md` at the end of every session.** It is the canonical snapshot and the first thing the next session reads. If it's stale, the next session starts wrong.
4. **Judging how the game looks and feels is Milko's job, on his phone.** Never open a visible game window on his Mac to play or look at the game. Code only runs the game invisibly in the background (headless bots, validators and the screenshot tools).
5. **Always run Godot from scripts with a kill switch.** A script error makes a `-s` tool spin forever and there is no `timeout` on this Mac.
6. **Bots and tools set `Progress.save_enabled = false`** — never let one write the save file.
7. **Never make things more complicated than they need to be — one file per real thing.** A new song = one audio file + one beatmap. A tempo variant = audio only, scaled in code. If a change needs a second copy of something that already exists, that is the signal to stop and ask whether it needs to exist at all.

## What this project is

A mobile game built in Godot 4 (GDScript). **One endless run, driven by music.** How far can you get. The song is the level: hazards are placed from a beatmap, so the course and the track are the same thing.

- **GitHub:** github.com/milko-ux/the-last-game
- **Target platforms:** iOS, Android. A local HTTPS web build on Milko's iPhone is the testing loop.
- **Active branch:** `phase-r-prototype`. Everything new lives in `prototype/`.

**Read `prototype/README.md`'s "Where we are" section first, every session.** It's the live status. This file carries only what outlives any one phase. The phase-by-phase history is in `docs/PHASE_LOG.md`.

## The pivot — what's live and what's history

The project began as an isometric neon-synthwave maze game with 30 hand-authored levels (Phases 0–3: touch controls, difficulty tiers, a Talo backend for accounts and leaderboards). **That game still exists in the repo but is no longer what's being built.** The synthwave art direction is dropped.

The 2D game's files (`main.gd`, `main.tscn`, `entities/`, `ui/`, `levels.json`, and the `Iso`/`Profile`/`Consent`/`Talo` autoloads) are kept as history and as the Talo integration's home. **Nothing in `prototype/` may depend on them** — except `autoload/palette.gd` and `autoload/progress.gd`, which the prototype's HUD and unlock logic still read.

Briefs, in order: `PHASE_R_BRIEF.md` + `PHASE_R_ADDENDUM_1..4.md`, then `PHASE_E_BRIEF_1_ENDLESS.md` (the endless run, which supersedes the level-based game), then `PHASE_A_BRIEF_1..6` (art: creature, world, motion, props, walk, light).

## Art direction

The goal is a **premium, modern 2026 look. No AI slop.** Everything in frame should read as deliberately designed and deliberately made — not as something a generator produced and nobody looked at twice.

- **Stone monoliths and slabs.** A dark stone field, faceted pillars, carved buildings receding into grey fog. Not black — grey fog, dim seams, one bright rim.
- **Clay beings.** The player is a one-eyed clay creature with four flippers and two legs. It walks, it tucks in the air, it spins once per jump.
- **Procedural textures only.** Materials are generated in shader code from noise and vertex colours. **No AI image textures in the game** — vertex colours sampled from a bake are allowed; a generated image file is not.
- **Higgsfield is a pre-production tool, not a production one.** Use it for concept references and for image-to-3D model generation. Never for in-game textures.
- **Colour logic is fixed and means something:** **magenta = will kill you · cyan = safe · amber = goal.** Every colour in the world lives in `prototype/palette.gd` (`WorldPalette`) and nowhere else.

## Rules that were learned the hard way — keep them

- **`levels/verdicts.json` ships the fairness verdicts of laps 0–9.** After touching `placement.gd`, `rules.gd`, `hazard_math.gd`, `fairness.gd`, the curriculum or the beatmap, **bump `LapGen.LAYOUT_VERSION`** and re-run `godot --headless --path . -s tools/lap_stats.gd -- laps=0-9 write=1` (~3 min). Forget, and the phone validates every lap live — that's the difference between a 2.2 s load and a 6.5 s one.
- **The validator bot must be judged at `fps=60`.** At 30 it can graze a wall by centimetres.
- **Layout hashes are the proof a refactor changed nothing.** `tools/plan_stats.gd` prints `HASH level=N`; they must not change.
- **Any new material or particle effect must be added to `prototype/prewarm.gd`**, or its first use is a frame hitch on the phone.
- **Knobs are ALWAYS an argument** (`field.knobs_of(spec)`, `Rules.x(k)`), never a global.
- **Nothing that can raise, and no `JavaScriptBridge`, inside a `RenderingServer.frame_post_draw` callback.**
- **Every loading gate needs a ceiling** (`FrameMeter.LABEL_TIMEOUT_MS`, 2 s, then carry on and mark the line `TIMED OUT`).
- **A branch behind `OS.has_feature("web")`, or anything reading a file the exporter transforms, has been tested by nothing on this Mac.**
- **An acceptance number must measure the thing that can break.** "Zero drift during stance" was true and useless — nothing in it said how far a planted foot could be from its hip.
- **`tools/shot.gd` is flaky for a paired screenshot** (its clock disagrees with the run's after a fast load). Use `tools/shot_walk.gd` (`--fixed-fps 60`, `cam=game`) when a frame must be reproducible.

## Build, serve, test

Godot 4.7.1 lives at `/Users/benim/Downloads/Godot.app/Contents/MacOS/Godot` — not on PATH, call the full path.

```
tools/package_web.sh "Web (Phase R)"     # export + zip, refuses a stale zip
tools/serve.py tls                       # HTTPS on the LAN, port 8443, self-signed
```

Builds are written to `../the-last-game-build/` — **outside the project on purpose.** A build folder inside `res://` is scanned by Godot, so the next export packs the previous export's icons into itself.

A Godot web build needs a **secure context**: plain `http://<LAN-IP>` fails with *"Secure Context — Check web server configuration"*. That's the expected failure, not a broken build. The phone accepts the certificate warning once.

**Always serve with `Cache-Control: no-store`.** Browsers cache `index.pck` hard, and a stale `.pck` silently runs an OLD build while every file on disk looks correct.

**Dev URL switches** (all behind `FrameMeter.enabled()`): `?level=N` · `?scale=X` · `?autoplay=1&live=1` · `?grad=1`.

### Before any release export — checklist

- [ ] Set `Progress.UNLOCK_ALL = false` (this also turns off the frame readout and the dev URL switches).
- [ ] Confirm the Phase R preset's `exclude_filter` still keeps `docs/` and `addons/` out of the pack.
- [x] The Godot MCP plugin is OFF (2026-09-22) — see below.
- [ ] Still shipping: the old 2D game. Its scripts cannot simply be filtered out, because `project.godot` still registers `Iso` / `Profile` / `Consent` / `Talo` as autoloads and an exported game cannot load an autoload that is not in the pack. `tools/` and the two tempo-shifted MP3s stay in deliberately — `?autoplay=1` loads `res://tools/autoplay.gd`, and `?level=N` needs those songs.

### The Godot MCP plugin is disabled on purpose

`project.godot` has `[editor_plugins] enabled=PackedStringArray()`. Turning the plugin OFF is the only thing that makes this stick: `addons/godot_mcp/plugin.gd` re-injects its three `MCP*Bridge` autoloads into `project.godot` and calls `ProjectSettings.save()` every time it starts, so deleting those lines by hand is a change that undoes itself the next time the editor opens.

They were running in the shipped phone build — two of them checking the filesystem for a command file on **every frame**, and one of them injecting synthetic input if it found one.

To get it back for a session: Project → Project Settings → Plugins → enable `godot_mcp`. It re-injects itself, so remember to turn it off again. Nothing in the project needs it — `tools/shot_walk.gd` is deterministic where the MCP screenshot is not, `tools/autoplay.gd` drives the game far more precisely than synthetic taps, and `tools/frame_probe.gd` covers performance.

## Repo map

**`prototype/` — the game.** `beat_clock.gd` (autoload `BeatClock`: song time, beats, seek) · `rules.gd` (constants, per-level knobs, death rules) · `hazard_math.gd` (where is it / is it lethal at time t) · `placement.gd` (deterministic layout from the beatmap) · `fairness.gd` (the mandatory validator) · `lap_gen.gd` (`LAYOUT_VERSION`) · `field.gd` (builds tiles, hazards, notes; floor/pit queries) · `hazard3d.gd` + `hazard_{slammer,sweeper,gate,orbiter,volley}.gd` · `player3d.gd` (movement, jump, hit box) · `creature.gd` (everything you see: pose, walk, dust, death) · `camera_rig.gd` · `monoliths.gd` · `props/props.gd` · `flat_mats.gd` · `motion.gd` · `palette.gd` (`WorldPalette`) · `prewarm.gd` · `frame_meter.gd` · `hud.gd` · `track_test.gd/.tscn` (the run scene) · `level_select.gd/.tscn`.

**`tools/`** — dev-only. Note they are still *packed* into the web build: `?autoplay=1` loads `res://tools/autoplay.gd` at runtime, so filtering them out would break that switch. They cost a few KB. `autoplay.gd` (headless bots) · `plan_stats.gd` (layout + `HASH`) · `lap_stats.gd` (regenerates `verdicts.json`) · `shot.gd` / `shot_walk.gd` / `shot_creature.gd` · `frame_probe.gd` · `package_web.sh` · `serve.py` · `make_endless_audio.py` · `decimate_models.py`.

**`levels/`** — `curriculum.json` (knobs per level) · `verdicts.json` (shipped fairness verdicts).

**`assets/`** — `audio/fuffens_endless.ogg` + `fuffens_beatmap.json` (the live pair) · `models/` (source GLBs) · `models/lod/` (the decimated copies the game actually loads).

**Legacy, not the current game:** `main.gd`, `main.tscn`, `entities/`, `ui/`, `levels.json`, `autoload/{iso,profile,consent,talo}.gd`, `tools/check_levels.py`.

## Deep-dives, read on demand

`docs/PHASE_LOG.md` (the phase-by-phase history) · `docs/2D_GLOW.md` · `docs/2D_HAZARD_COLLISION.md` · `docs/2D_ROCK_TEXTURES.md` · `docs/TALO_GOTCHAS.md` · `docs/TALO_SETUP.md` — the four 2D docs concern the legacy game; the Talo ones matter again if accounts return.
