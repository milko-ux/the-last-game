#!/bin/bash
# Milko's hard rule 1: Milko pushes, Claude does not.
# PreToolUse on Bash. Returns permissionDecision "deny". It was "ask", but his
# session runs in an auto-approve mode that satisfies the call before an "ask"
# can become a prompt -- the gate was tested on 2026-09-22 and the push went
# straight through. "deny" is not overridden that way.
#
# This blocks CLAUDE's git push. It does not block Milko: a command he types
# himself with the `!` prefix runs in his shell, not as a tool call, so no
# PreToolUse hook sees it. MEASURED, not just reasoned: on 2026-09-22 Milko
# pushed ba2e2ee with `! git push origin phase-r-prototype` and the gate never
# fired. The escape hatch is proven from his side.
#
# The match is done here rather than with settings.json's `if` clause on purpose:
# `if: "Bash(git push*)"` only matches a command that STARTS with git push, so
# `cd somewhere && git push` would sail straight through the gate.
#
# Two things the match has to get right, both learned by getting them wrong:
#  - it must only fire on git at a COMMAND POSITION (line start, or after ; & |).
#    The first version grepped the whole string, so merely WRITING about the
#    command -- in an echo, a commit message, a doc -- was denied as if it were
#    one.
#  - it must ignore heredoc bodies for the same reason: a script written to disk
#    through `cat <<EOF` is data, not commands.
cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null)
body=$(printf '%s\n' "$cmd" | awk '
  /<<-?[[:space:]]*['"'"'"]?[A-Za-z_][A-Za-z0-9_]*['"'"'"]?/ && !skip {
    match($0, /<<-?[[:space:]]*['"'"'"]?[A-Za-z_][A-Za-z0-9_]*/)
    tag = substr($0, RSTART, RLENGTH)
    gsub(/^<<-?[[:space:]]*['"'"'"]?/, "", tag)
    skip = 1; print; next
  }
  skip { if ($0 ~ "^[[:space:]]*" tag "[[:space:]]*$") skip = 0; next }
  { print }
')
printf '%s\n' "$body" | grep -Eq '(^|[;&|])[[:space:]]*git[[:space:]]+([^;&|]*[[:space:]]+)?push([[:space:]]|$)' || exit 0

cd "${CLAUDE_PROJECT_DIR:-.}" || exit 0

staged=$(git diff --staged --stat 2>/dev/null)
[ -z "$staged" ] && staged="(nothing staged — these changes are already committed)"

if git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
  outgoing=$(git log --oneline '@{u}..HEAD' 2>/dev/null)
  [ -z "$outgoing" ] && outgoing="(nothing to push — local branch matches its remote)"
else
  outgoing=$(git log --oneline -10 2>/dev/null)
  outgoing="no upstream set; the 10 most recent local commits are:
$outgoing"
fi

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

reason="Show Milko the commits and wait. Milko pushes himself.

Branch: $branch

Staged diff:
$staged

Commits waiting to be pushed:
$outgoing

Milko pushes with:   ! git push origin $branch"

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: $r
  }
}'
