# How the 2D game's glow / bloom works

**Read this before touching `Palette`, the `WorldEnvironment`, or the HDR settings.** Pointer lives in `CLAUDE.md`.

The game renders in HDR (`rendering/viewport/hdr_2d` in `project.godot`), which lets a colour be *brighter than pure white*. The bloom pass in `main.tscn` only picks up things brighter than white (`glow_hdr_threshold = 1.0`). So:

- Anything drawn through `Palette.glow(colour, amount)` blooms. Anything not drawn through it never does.
- That's why the dark floor stays dark, and why the frosted-glass touch controls keep their exact look — `ui/ui.gd` never calls `glow()`, and the UI CanvasLayer is excluded via `background_canvas_max_layer = 0`.
- **Boost amounts are per-element on purpose.** A colour with a zero channel (cyan `EDGE`, `#00fff2`) can be boosted hard (2.5x) and keeps its hue. A colour with high channels (the player's `#7dfaff`) clips toward white and goes grey-white if pushed — so those get a gentle 1.2–1.3x. If you raise a boost and something turns white, that's why.

**Two switches if performance is a problem on a real phone:** set `Palette.NEON` to `1.0` to drop the over-bright everywhere, or `glow_enabled = false` on the Environment in `main.tscn` to remove the bloom pass entirely. Both are safe, reversible, and leave gameplay untouched.
