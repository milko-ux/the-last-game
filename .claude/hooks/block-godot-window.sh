#!/bin/bash
# ============================================================
# PreToolUse hook (Bash): Godot never opens a window on Milko's Mac.
#
# A Bash command that runs Godot (godot, .../Godot.app/..., Godot_v4*,
# or a wrapper named run_godot.sh) must say --headless, or carry
# ALLOW_WINDOW=1 -- the marker for a screenshot / probe job that needs a
# renderer, batched at the end of a section and announced to Milko first
# (CLAUDE.md). Anything else: blocked (exit 2), with the reason on stderr.
#
# Matches Godot as a command word, not as part of a name: godot-cpp,
# .godot/ and godot_mcp pass. A script that runs Godot inside itself
# (tools/package_web.sh) is not seen here -- those already pass --headless.
# ============================================================

if ! command -v jq >/dev/null 2>&1; then
	echo "block-godot-window: jq is missing (brew install jq) -- cannot check the command." >&2
	exit 0
fi

cmd=$(jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

godot_re='(^|[[:space:];&|(/"'"'"'])(godot|Godot)([[:space:];&|)"'"'"']|$)|Godot\.app|Godot_v4|run_godot\.sh'
if printf '%s' "$cmd" | grep -Eq "$godot_re"; then
	case "$cmd" in
		*--headless*|*ALLOW_WINDOW=1*) exit 0 ;;
	esac
	echo "Godot without --headless opens a window. Use --headless, or batch screenshot jobs and ask Milko first." >&2
	exit 2
fi
exit 0
