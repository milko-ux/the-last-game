#!/bin/bash
# The rule the README lists as one that bit us: change anything that decides what a
# lap LOOKS like, and prototype/lap_gen.gd's LAYOUT_VERSION must be bumped and
# levels/verdicts.json regenerated. Forget, and the shipped verdict fingerprint stops
# matching, so the PHONE validates every lap live: a 2.2 s load becomes 6.5 s.
#
# PostToolUse on Write|Edit. Silent unless a layout source was just edited without a
# matching LAYOUT_VERSION bump in the same working tree.
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

f=$(jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null)
[ -z "$f" ] && exit 0

case "${f#"$PWD"/}" in
  prototype/placement.gd|prototype/rules.gd|prototype/hazard_math.gd|\
  prototype/fairness.gd|prototype/lap_gen.gd|levels/curriculum.json|\
  assets/audio/fuffens_beatmap.json) ;;
  *) exit 0 ;;
esac

# Bumped already in this working tree? Then there is nothing to say.
if git diff HEAD -- prototype/lap_gen.gd 2>/dev/null | grep -q '^+const LAYOUT_VERSION'; then
  exit 0
fi

now=$(grep -m1 '^const LAYOUT_VERSION' prototype/lap_gen.gd 2>/dev/null | tr -dc '0-9')
msg="LAYOUT_VERSION GUARD: you just edited ${f#"$PWD"/}, which changes what a lap looks like, but prototype/lap_gen.gd still has LAYOUT_VERSION := ${now:-?} unchanged.

Before this is called done:
  1. bump LAYOUT_VERSION in prototype/lap_gen.gd
  2. godot --headless --path . -s tools/lap_stats.gd -- laps=0-9 write=1   (~3 min)

Skip it and the phone validates every lap live on load (2.2 s becomes 6.5 s)."

jq -n --arg m "$msg" '{
  systemMessage: $m,
  hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: $m }
}'
