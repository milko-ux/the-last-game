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
# Matches Godot where a command starts -- a line's start, after ; & | or
# $( or a backtick, after VAR=value prefixes, as the last part of a path
# (.../MacOS/Godot) -- not as a word inside text: the first version
# blocked a commit message saying "(Godot runs headless only now)". A
# line of text that STARTS with "Godot" is still blocked (a multi-line
# script's own Godot line must be caught); reword it. Names pass:
# godot-cpp, .godot/, godot_mcp. A script that runs Godot inside itself
# (tools/package_web.sh) is not seen here -- those already pass --headless.
# ============================================================

if ! command -v jq >/dev/null 2>&1; then
	echo "block-godot-window: jq is missing (brew install jq) -- cannot check the command." >&2
	exit 0
fi

cmd=$(jq -r '.tool_input.command // empty')
[ -z "$cmd" ] && exit 0

start='(^|[;&|`]|\$\()[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*'
path='"?([^[:space:]"=]*/)?'
name='(godot|Godot|Godot_v4[^[:space:]"]*|run_godot\.sh)'
godot_re="${start}${path}${name}([[:space:]\";&|)]|\$)"
if printf '%s' "$cmd" | grep -Eq "$godot_re"; then
	case "$cmd" in
		*--headless*|*ALLOW_WINDOW=1*) exit 0 ;;
	esac
	echo "Godot without --headless opens a window. Use --headless, or batch screenshot jobs and ask Milko first." >&2
	exit 2
fi
exit 0
