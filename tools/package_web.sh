#!/usr/bin/env bash
# ============================================================
# Builds the web export and packages it as a zip.
#
# WHY THIS EXISTS: it is very easy to hand over a zip that was
# built BEFORE the last change. That has already happened twice.
# Every file on disk looks right and nothing errors; the old build
# just quietly runs.
#
# So this script does not trust the build folder. It unzips the
# finished archive into a temp dir and checks THAT copy contains
# the run scene, the menu and the beatmap, and refuses to hand you
# a stale zip.
#
# Usage:  tools/package_web.sh  [preset]  [output.zip]
#   tools/package_web.sh                      -> "Web (Phase R)", the game
# The build folder is read from the preset's export_path (outside the
# project, ../the-last-game-build/, on purpose: a build folder inside
# res:// is scanned by Godot and the next export packs it into itself).
# (The 2D game's "Web" preset and its levels.json check went with the
# 2D game, 2026-09-23.)
# ============================================================
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Users/benim/Downloads/Godot.app/Contents/MacOS/Godot}"
PRESET="${1:-Web (Phase R)}"
BUILD_REL="$(python3 -c "
import re,sys
txt=open('$PROJECT/export_presets.cfg').read()
for block in txt.split('[preset.')[1:]:
    if re.search(r'^name=\"%s\"$' % re.escape('$PRESET'), block, re.M):
        m=re.search(r'^export_path=\"(.*)\"$', block, re.M)
        print(m.group(1).rsplit('/',1)[0]); sys.exit(0)
sys.exit('no preset named $PRESET in export_presets.cfg')
")"
BUILD="$PROJECT/$BUILD_REL"
OUT="${2:-$HOME/Downloads/the-last-game-phase-r.zip}"

command -v "$GODOT" >/dev/null 2>&1 || [ -x "$GODOT" ] || {
  echo "Godot not found at: $GODOT   (set GODOT=/path/to/Godot)" >&2; exit 1; }

echo "==> importing (so a freshly added asset is never silently dropped)"
"$GODOT" --headless --path "$PROJECT" --import >/dev/null 2>&1 || true

echo "==> exporting preset \"$PRESET\" -> $BUILD_REL"
mkdir -p "$BUILD"
EXPORT_LOG="$(mktemp)"
"$GODOT" --headless --path "$PROJECT" --export-release "$PRESET" "$BUILD/index.html" >"$EXPORT_LOG" 2>&1 || true
if grep -iEq "SCRIPT ERROR|Parse Error|ERROR:" "$EXPORT_LOG"; then
  echo "export reported errors:" >&2
  grep -iE "SCRIPT ERROR|Parse Error|ERROR:" "$EXPORT_LOG" >&2
  rm -f "$EXPORT_LOG"; exit 1
fi
rm -f "$EXPORT_LOG"

echo "==> packaging"
rm -f "$OUT"
( cd "$BUILD" && zip -q -j "$OUT" \
    index.html index.js index.wasm index.pck index.png \
    index.icon.png index.apple-touch-icon.png \
    index.audio.worklet.js index.audio.position.worklet.js )

echo "==> verifying the ZIP (not the build folder)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
unzip -q -o "$OUT" -d "$TMP"

# The pck must contain the run scene, the menu the game opens into and the beatmap.
for TOKEN in "prototype/track_test" "prototype/menu" "fuffens_beatmap"; do
  if ! LC_ALL=C grep -aqF "$TOKEN" "$TMP/index.pck"; then
    echo "  STALE: \"$TOKEN\" is missing from the packaged pck. Do not use it." >&2
    exit 1
  fi
done
echo "  ok: packaged build contains the game"
echo
echo "Ready: $OUT  ($(du -h "$OUT" | cut -f1))"
echo "Serve it for a phone with:  tools/serve.py tls $BUILD_REL"
