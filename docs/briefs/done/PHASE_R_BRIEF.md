# Phase R — Gray-box prototype: "An album you survive"

**Read CLAUDE.md first.** This brief supersedes the "Current status" and "Roadmap" sections there for the duration of Phase R. Do not modify the existing 2D game (`main.tscn`, `main.gd`, `levels.json`, `entities/`, `ui/`, `autoload/`) except where this brief explicitly says to reuse something. Everything new lives under `prototype/`.

## Why this exists (context for you, not for Milko)

We are pivoting. The synthwave art direction is dropped. The game becomes a **music-driven precision game where each level is a song**: the player moves forward along a track at a speed locked to the song, hazards act on the beat, and the camera sits behind and above the character. Research references: Geometry Dash (position = song time), Sayonara Wild Hearts (each level is a track on an album, unlit environments + depth fog, lit character), Stumble Guys (behind-and-above camera on forward-flowing courses).

This prototype answers one question: **does a beat-locked, forward-flowing, third-person version of this concept feel good in Milko's hand on a real phone?** It is gray-box. No art. Flat colors only. Do not spend time on visuals.

Milko's playtest verdict decides whether the whole game is rebuilt on this model. Bias toward getting it onto his phone fast.

## Non-negotiables (unchanged)

- Color logic stays as *readability*, not style: **magenta = will kill you, cyan = safe surface, amber = goal.** Use flat unlit materials in those colors and nothing else.
- Frosted-glass touch controls: reuse the existing joystick + jump UI from `ui/ui.gd` / `main.tscn` (the CanvasLayer). Do not redesign them.
- 3 lives on Standard with checkpoints; death must always be readable — the player must see what killed them coming from the *front*.
- No ads, no accounts, no Talo in this prototype.

## The input: `assets/audio/fuffens_beatmap.json` + `assets/audio/fuffens_instrumental_vers.mp3`

Milko will drop both files into `assets/audio/`. The JSON was generated from the track:

- `bpm`: 117.45 — `beat_interval_s`: 0.5108
- `duration_s`: 180.06
- `beats_s`: 313 beat timestamps. **The first beat is at 16.09 s** — the first 16 seconds are an ambient intro with no drums.
- `downbeats_s`: 78 bar starts (4/4 assumed). Bar 1 starts at 16.6 s.
- `sections`: 8 sections with a mean `energy` each. The song runs a strict 16-bar cycle: **8 bars hot (energy ≈ 0.93–1.0), then 8 bars falling (0.5 → 0.13)**, repeated five times, then a decaying outro.
- `bars[]`: per bar — `t` (start time), `energy` (0–1 normalised RMS), and `low` / `mid` / `high` band energy (0–1). `low` ≈ kick, `high` ≈ hats, `mid` ≈ everything else.

Treat this file as data. Hazard placement is generated from it, never hand-authored, so a different song produces a different level with zero code changes.

## Core model: position IS time

The player's forward position along the track is a pure function of song time:

```
z = song_time_s * TRACK_SPEED      # TRACK_SPEED in world units per second
```

Consequences you must respect:
- The player never controls forward speed. Joystick = left/right on the track. Jump button = jump. That's the whole input.
- Bar N occupies the track from `z(bar_start)` to `z(next_bar_start)`. With TRACK_SPEED chosen so **one bar ≈ 8 world units**, a beat is ≈ 2 units — hazards spaced on beats are physically readable.
- **Death rewinds time.** On death: song seeks to the checkpoint's `t`, player teleports to `z(t)`, hazards re-derive their state from time. There is no "respawn logic" separate from the song clock. Get this right and the whole game is deterministic.
- The 16-second intro is the run-up: track visible, hazards inert, player can move and jump freely to get a feel for the controls. Hazards arm on the first downbeat (16.6 s). On phone this doubles as the "get your thumbs ready" moment. Do not add a countdown UI.

## Files to create

### `prototype/beat_clock.gd` (autoload `BeatClock` — register it in Project Settings only for the prototype; it must not run in the 2D game)

Godot's recommended sync method for songs of a few minutes — system clock with latency compensation — is exactly right for a level. From the engine docs:

```gdscript
var _time_begin: int
var _time_delay: float

func start(stream_player: AudioStreamPlayer) -> void:
    _time_begin = Time.get_ticks_usec()
    _time_delay = AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
    stream_player.play()

func song_time() -> float:
    var t := (Time.get_ticks_usec() - _time_begin) / 1_000_000.0
    return max(0.0, t - _time_delay)
```

On seek (checkpoint rewind): call `stream_player.seek(t)` and reset `_time_begin` so `song_time()` returns `t`. Add a `seek(t)` method that does exactly that.

Responsibilities:
- Load `fuffens_beatmap.json` on `_ready`.
- Expose: `song_time()`, `current_beat() -> int`, `current_bar() -> int`, `beat_phase() -> float` (0..1 within the current beat), `bar_energy(bar) -> float`, `bar_band(bar, "low"|"mid"|"high") -> float`.
- Emit signals: `beat(index: int)`, `downbeat(bar: int)`, `section_changed(section_id: int)`. Fire them from `_process` by comparing the previous frame's beat/bar index to the current one. Never fire from a Timer — timers drift from the audio clock.
- **Add a 30 ms `SYNC_OFFSET_S` constant** subtracted from `song_time()` for hazard *visuals* only, so the visual hit lands with the audible transient rather than after it. Make it a single tunable; Milko will feel whether it's right.

### `prototype/track_test.tscn` + `prototype/track_test.gd` (the scene to run)

Node tree:

```
TrackTest (Node3D)
├── WorldEnvironment            # background color near-black, fog enabled, no glow (see Renderer)
├── Music (AudioStreamPlayer)   # stream = fuffens_instrumental_vers.mp3
├── Track (Node3D)              # generated by track_builder.gd
├── Player (CharacterBody3D)    # prototype/player3d.tscn
├── CameraRig (Node3D)          # prototype/camera_rig.gd
│   └── Camera3D
└── UI (CanvasLayer)            # instance the existing glass-controls layer here; adapt signals
```

### `prototype/track_builder.gd`

Builds a **straight** track (no curves in Phase R) from the beatmap:

- One `MeshInstance3D` box segment per bar: 8 units long (z), 6 units wide (x, three implicit lanes of 2 units), 0.5 thick. Flat cyan unlit material. Small 0.1-unit gap between segments so bar boundaries are visible.
- Before bar 1: a 16-second run-up of plain segments covering `z(0)` to `z(bar_1)`.
- After bar 78: three plain segments and an amber goal gate (box, unlit amber) at the end.
- Hazards are children of their bar segment, positioned using beat offsets *within* the bar so the placement generator can talk in beats.
- Below the track: nothing. Falling off the edge is a death (a large `Area3D` kill-plane at y = -5).

### `prototype/placement.gd`

Deterministic hazard placement from `bars[]`. Rules — implement exactly these first, we tune after the playtest:

| Bar energy | Density | Meaning |
|---|---|---|
| ≥ 0.85 | **Gauntlet** | a hazard on every beat (4 per bar) |
| 0.55 – 0.85 | **Pressure** | hazards on beats 1 and 3 |
| 0.35 – 0.55 | **Breather** | one hazard on beat 1, and a **checkpoint marker** if this bar is the *first* bar of a section |
| < 0.35 | **Rest** | no hazards; lane-wide cyan floor only |

Which hazard type a beat gets is chosen by the dominant band of that bar:
- `low` dominant → **Slammer**: a magenta bar that drops onto one lane on the beat and lifts by the next beat. Readable: it hovers above the lane one beat early.
- `high` dominant → **Pulser**: a magenta pillar in one lane that is *up* (lethal) for half a beat then *down*. Visible in the "down" state as a dark magenta plate on the floor so the player can see the pattern ahead.
- `mid` dominant → **Sweeper**: a magenta wall that crosses all three lanes over exactly one bar, leaving one lane open at any moment. Use `beat_phase()` and bar progress to drive its x position — never a tween.

Lane choice for Slammers/Pulsers: pseudo-random with a fixed seed derived from the bar index, so the level is identical every run. Guarantee that on any beat at least one lane is safe (check against the previous beat's hazards — a player must always have a reachable safe lane within one lane-width of movement per beat).

Every hazard reads `BeatClock` state in `_process` and *derives* whether it's lethal from time. Hazards do not have their own timelines. This is what makes rewind-on-death free.

### `prototype/player3d.tscn` / `player3d.gd`

- `CharacterBody3D` with a `CapsuleMesh` — flat white. **No character art.** The character direction is being decided separately.
- x movement from the joystick: max lateral speed such that crossing one full lane (2 units) takes ~0.25 s. Snappy. Clamp x to the track width.
- z is set every frame from `BeatClock.song_time() * TRACK_SPEED` — not from velocity.
- Jump: reuse the jump feel numbers from `entities/player.gd` (read them — Milko has confirmed on-device that the current jump feels right). Jump apex should clear a Slammer; landing on a raised Pulser is death.
- Death on contact with any hazard in its lethal state. On death: freeze 0.35 s, camera micro-shake, then `BeatClock.seek(checkpoint_t)`.
- Keep the existing haptics call on death and on goal.

### `prototype/camera_rig.gd`

- Camera3D at local offset `(0, 5.5, -8.5)` from the player, looking at a point 4 units *ahead* of the player (so the frame shows what's coming, not the player's back). FOV 65.
- Follow with a small lag on x only (lerp 0.12) — z tracks exactly, because z is time and any lag there reads as sync error.
- On each `downbeat`: a 2 % FOV punch that decays over one beat. That's the only "juice" allowed in Phase R — it's there so Milko can *feel* the beat clock through the camera.
- Portrait vs landscape: landscape only, same as the current game.

### `prototype/env` (in the scene, not a file)

- `WorldEnvironment`: background = flat color `#07070c`. Fog: enabled, depth-based, starts at 18 units, fully opaque by 45. Fog color = background color. This is the Sayonara trick — unlit world, depth fog hides the track's end, and it costs nothing.
- **No glow / bloom.** See Renderer.

## Renderer

Set `rendering/renderer/rendering_method` = `mobile` and `rendering/renderer/rendering_method.mobile` = `mobile` for native, and let the **Web export use `gl_compatibility`** (it has no choice — web export is Compatibility-only). Everything in this brief is designed to look identical on both: unlit materials, depth fog, no HDR, no glow. If you find yourself reaching for a feature that only exists in Forward+/Mobile, stop — the itch/LAN web build is how Milko playtests, and it must look the same as native.

## Reuse from the existing game (read, don't rewrite)

- Joystick + jump button UI: the glass-controls CanvasLayer in `main.tscn` / `ui/ui.gd`. Instance it; wire its move vector and jump signal into `player3d.gd`.
- Jump physics numbers from `entities/player.gd`.
- Haptics calls (wherever Phase 1 put them).
- The results/share screen can wait. On reaching the amber gate, just print time-to-goal and death count to a Label for now.

## Build & test loop

1. Branch: `git checkout -b phase-r-prototype`. All Phase R work on this branch. **Stage diffs for Milko's approval before any push**, per CLAUDE.md.
2. Add a second run scene: keep `main.tscn` as the project's main scene; run the prototype via `godot --path . prototype/track_test.tscn` and document that command at the top of `prototype/README.md`.
3. Add a Web export that exports `prototype/track_test.tscn` as the main scene (a second preset in `export_presets.cfg` named "Web (Phase R)"; do not touch the existing "Web" preset).
4. Package with `tools/package_web.sh` (adapt it to accept the preset name) and serve with `tools/serve.py tls` so Milko can open it on his phone over the LAN. The serve script's no-cache and HTTPS notes in CLAUDE.md apply.
5. Before handing over, run it yourself in a desktop browser and verify: (a) hazards visibly move on the beat, (b) dying and rewinding puts the song back where the checkpoint is. (Item (c), a full playtest to the goal, was dropped 2026-09-15 — Milko does the on-device test himself.)

## Acceptance — what Milko is judging on his phone

1. **Sync:** hazards land on the beat, not after it. If they feel late, tune `SYNC_OFFSET_S` (try 30 → 60 ms) before touching anything else.
2. **Readability:** every death was visible coming. Nothing kills from behind or from off-screen.
3. **Feel:** the joystick lane-switch and the jump feel as good as the 2D game's. If they don't, that is a Phase R blocker, not a polish item.
4. **The run-up:** the 16-second intro feels like anticipation, not waiting.

Report back with: the LAN URL, which `SYNC_OFFSET_S` you shipped, the death count from your own test run, and anything in the placement rules that produced an unfair beat.

## Out of scope for Phase R — do not do these

- Character model, animation, any art, textures, particles, glow.
- Curved or branching track. Straight only.
- Difficulty tiers beyond Standard. Hard/Extreme come after the model is proven.
- Talo, accounts, leaderboards, consent, share screen.
- Touching the 2D game or `levels.json`.
