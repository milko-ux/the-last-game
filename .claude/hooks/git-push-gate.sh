#!/bin/bash
# Milko's hard rule 1: never push without showing him what is going and getting a yes.
# PreToolUse on Bash. Returns permissionDecision "ask", so Claude Code raises a
# permission prompt with the staged diff and the outgoing commits in it. Milko
# approves or declines there.
#
# The match is done here rather than with settings.json's `if` clause on purpose:
# `if: "Bash(git push*)"` only matches a command that STARTS with git push, so
# `cd somewhere && git push` would sail straight through the gate.
cmd=$(jq -r '.tool_input.command // empty' 2>/dev/null)
printf '%s' "$cmd" | grep -Eq '(^|[;&|[:space:]])git[[:space:]]+([^;&|]*[[:space:]])?push([[:space:]]|$)' || exit 0

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

reason="PUSH GATE — your rule: nothing is pushed without your go-ahead.

Branch: $branch

Staged diff:
$staged

Commits that would be pushed:
$outgoing

Approve to push, or decline and say what you want changed first."

jq -n --arg r "$reason" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "ask",
    permissionDecisionReason: $r
  }
}'
