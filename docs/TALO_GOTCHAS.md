# Talo / networking gotchas (learned the hard way, 2026-08-26)

**Read this before touching `autoload/talo.gd` or any web-facing HTTP.** Pointer lives in `CLAUDE.md`.

1. **`HTTPRequest` is broken in this Godot version's web export** — every request stalls without ever reaching the browser and dies as `RESULT_TIMEOUT` with status 0. Verified: the browser-side fetch never fires, while native builds run the identical code fine. That's why `talo.gd` routes web requests through `JavaScriptBridge.eval` + the browser's own `fetch` (the `JS_HELPER` snippet). Don't "simplify" it back to `HTTPRequest` without testing a web export.
2. **`talo.cfg` must be named in the export preset's `include_filter`** (`export_presets.cfg`). `.cfg` files aren't Godot resources, so the exporter silently drops them — the build then ships dark with no error anywhere.
3. `accept_gzip` must stay off for web-facing HTTP paths; the browser already decompresses.
4. Reading leaderboards needs no login; submitting needs the session headers (`X-Talo-Alias/Player/Session`). Talo keeps one entry per player per board and only replaces it when the new score is beats the old one, so submitting every run is safe.

