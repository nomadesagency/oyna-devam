#!/bin/bash
# PostToolUse hook. Two jobs:
#  1) When `oyna-devam.sh on` is run, bind the session that ran it to active.json (session isolation).
#  2) When the limit threshold is reached, inject a "finish the current step and stop" context into Claude (once per window).
. "$(dirname "$0")/common.sh"
input=$(cat)
is_active || exit 0

# 1) bind the session
cmd=$(jq -r '.tool_input.command // empty' <<<"$input")
sid=$(jq -r '.session_id // empty' <<<"$input")
if [ -n "$sid" ] && [[ "$cmd" =~ oyna-devam\.sh[\"\']?[[:space:]]+on([[:space:]]|$) ]]; then
  jq --arg s "$sid" '.session=$s | .rebind=false' "$ACTIVE" > "$ACTIVE.tmp" && mv "$ACTIVE.tmp" "$ACTIVE"
  log "session bound: $sid"
fi

in_scope "$input" || exit 0
{ [ -f "$DONE" ] || [ -f "$BLOCKED" ]; } && exit 0

refresh_usage_async 120
p=$(effective_pct)
[ -z "$p" ] && exit 0
thr=$(threshold)
ge "$p" "$thr" || exit 0

r=$(jq -r '.resets_at // 0' "$STATE")
[ "$(cat "$U/wrapup.sent" 2>/dev/null)" = "$r" ] && exit 0
echo "$r" > "$U/wrapup.sent"
log "wrap-up context sent pct=$p resets_at=$r"

msg="LIMIT WARNING: the 5-hour usage limit is at ${p}% (threshold ${thr}%). Do NOT start any new sub-task. Bring the step you are working on (half-written file, command, verification) to a consistent point and finish it; then write a 'done / next step' note to ~/.claude/oyna-devam/progress.md and end your turn (do not write a final summary; the task is not finished). Do not suspend the computer yourself and do not run pmset: the system will wait, suspend the computer, wake it when the limit resets and resume you where you left off."
jq -n --arg m "$msg" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$m}}'
