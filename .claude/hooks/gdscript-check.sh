#!/bin/bash
# Parse-check a .gd file the moment it is written. Takes ~0.5 s. There are no tests in
# this project, and a broken script makes a `godot -s` tool spin for ever with no
# `timeout` on this Mac — so the cheapest possible check is worth having.
#
# PostToolUse on Write|Edit. Silent when the file parses.
cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

f=$(jq -r '.tool_response.filePath // .tool_input.file_path // empty' 2>/dev/null)
case "$f" in *.gd) ;; *) exit 0 ;; esac

rel="${f#"$PWD"/}"
[ -f "$rel" ] || exit 0

GODOT="${GODOT:-/Users/benim/Downloads/Godot.app/Contents/MacOS/Godot}"
[ -x "$GODOT" ] || exit 0

# Kill switch (project rule): never let a Godot invocation hang the session.
# The watcher's own streams MUST be redirected: a background job that inherits the
# command substitution's stdout holds that pipe open for its whole sleep, so the
# check would take the full timeout every time instead of half a second.
out=$("$GODOT" --headless --path . --check-only --script "$rel" 2>&1 &
      pid=$!
      ( sleep 20; kill -9 $pid 2>/dev/null ) >/dev/null 2>&1 &
      w=$!
      wait $pid 2>/dev/null
      kill -9 $w 2>/dev/null)

# --check-only does not register autoloads, so every file that uses one reports a
# false "Identifier not found". Those seven names are the project's autoloads.
out=$(printf '%s\n' "$out" \
  | grep -E 'SCRIPT ERROR|Parse Error|Compile Error' \
  | grep -vE 'Identifier not found: (BeatClock|Progress|Palette|Iso|Profile|Consent|Talo)')

[ -z "$out" ] && exit 0

msg="GDSCRIPT CHECK failed for $rel:

$out"

jq -n --arg m "$msg" '{
  systemMessage: $m,
  hookSpecificOutput: { hookEventName: "PostToolUse", additionalContext: $m }
}'
