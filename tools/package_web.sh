#!/usr/bin/env bash
# ============================================================
# Builds the web export and packages it for itch.io upload.
#
# WHY THIS EXISTS: it is very easy to hand over a zip that was
# built BEFORE the last change. That has already happened twice —
# once shipping a 5-level zip after 30 levels were added. Every
# file on disk looks right and nothing errors; the old build just
# quietly runs.
#
# So this script does not trust the build folder. It unzips the
# finished archive into a temp dir and checks THAT copy contains
# the current level data, and refuses to hand you a stale zip.
#
# Usage:  tools/package_web.sh  [preset]  [output.zip]
#   tools/package_web.sh                      -> "Web" (the 2D game)
#   tools/package_web.sh "Web (Phase R)"      -> the Phase R prototype
# The build folder is read from the preset's export_path, and the
# freshness token depends on the preset (last level name for the 2D
# game, the prototype scene path for Phase R).
# ============================================================
set -euo pipefail

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT="${GODOT:-/Users/benim/Downloads/Godot.app/Contents/MacOS/Godot}"
PRESET="${1:-Web}"
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
if [ "$PRESET" = "Web" ]; then
  DEFAULT_OUT="$HOME/Downloads/the-last-game-web.zip"
else
  DEFAULT_OUT="$HOME/Downloads/the-last-game-phase-r.zip"
fi
OUT="${2:-$DEFAULT_OUT}"

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

if [ "$PRESET" != "Web" ]; then
  # Prototype: the pck must contain the run scene, the menu the game now
  # opens into (Phase E section 7) and the beatmap.
  for TOKEN in "prototype/track_test" "prototype/menu" "fuffens_beatmap"; do
    if ! LC_ALL=C grep -aqF "$TOKEN" "$TMP/index.pck"; then
      echo "  STALE: \"$TOKEN\" is missing from the packaged pck. Do not use it." >&2
      exit 1
    fi
  done
  echo "  ok: packaged build contains the Phase R prototype"
  echo
  echo "Ready: $OUT  ($(du -h "$OUT" | cut -f1))"
  echo "Serve it for a phone with:  tools/serve.py tls $BUILD_REL"
  exit 0
fi

# The name of the LAST level in levels.json must appear in the packaged pck.
LAST_NAME="$(python3 -c "
import json,sys
d=json.load(open('$PROJECT/levels.json'))
print(d['levels'][-1].get('name',''))
")"
COUNT="$(python3 -c "
import json
print(len(json.load(open('$PROJECT/levels.json'))['levels']))
")"

if [ -z "$LAST_NAME" ]; then
  echo "  ! last level has no name; cannot verify freshness" >&2; exit 1
fi

if LC_ALL=C grep -aqF "$LAST_NAME" "$TMP/index.pck"; then
  echo "  ok: packaged build contains all $COUNT levels (last: \"$LAST_NAME\")"
else
  echo "  STALE: \"$LAST_NAME\" is missing from the packaged pck." >&2
  echo "  The zip does NOT match levels.json. Do not upload it." >&2
  exit 1
fi

echo
echo "Ready to upload: $OUT  ($(du -h "$OUT" | cut -f1))"
echo
echo "On itch.io:"
echo "  - upload this zip"
echo "  - tick 'This file will be played in the browser'"
echo "  - Kind of project: HTML,  embed 960x540, fullscreen button on"
echo "  - Visibility: Public"
echo "  - after uploading, hard-refresh the page on your phone; itch caches too"
