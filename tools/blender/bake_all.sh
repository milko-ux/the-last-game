#!/usr/bin/env bash
# Regenerates everything baked in Blender, headless, in one command
# (brief stage B, 2026-09-24). Blender is always run with -b. Each script
# writes its own outputs under assets/models/; run Godot's import (the
# packaging script does) before the game sees a new file.
#
#   tools/blender/bake_all.sh            # the pillar kit (and, as they land, the tiles and the hazards' AO)
#   tools/blender/bake_all.sh 1024 16    # a quick, rough bake (atlas px, samples)
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BLENDER="${BLENDER:-/Applications/Blender.app/Contents/MacOS/Blender}"
PX="${1:-2048}"; SAMPLES="${2:-64}"
for script in pillars.py; do
  echo "==> $script ($PX px, $SAMPLES samples)"
  "$BLENDER" -b --python "$HERE/$script" -- "$PX" "$SAMPLES" 2>&1 | grep -E "KIT DONE|TILES DONE|AO DONE|Traceback|Error" || true
done
