#!/bin/bash
# Stop hook: the turn has ended. Decision order:
#   DONE/BLOCKED -> shut the system down | threshold exceeded -> plan sleep + wake | otherwise "keep going" (exit 2).
. "$(dirname "$0")/common.sh"
input=$(cat)
is_active || exit 0
in_scope "$input" || exit 0

if [ -f "$DONE" ]; then
  final_sleep=$(jq -r 'if .final_sleep == false then "false" else "true" end' "$ACTIVE")
  log "Stop: task DONE, shutting the system down (final_sleep=$final_sleep)"
  bash "$U/sleep.sh" off >/dev/null
  if [ "$final_sleep" = true ]; then
    perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' bash "$U/final-sleep.sh" </dev/null >>"$LOG" 2>&1 &
  fi
  exit 0
fi
if [ -f "$BLOCKED" ]; then
  log "Stop: BLOCKED ($(cat "$BLOCKED")), shutting the system down"
  notify "Task is blocked: $(cat "$BLOCKED")"
  bash "$U/sleep.sh" off >/dev/null
  exit 0
fi

# bounded read (the Stop hook has a 60 s timeout); if it fails the previous reading is used and the StopFailure hook is the backstop
refresh_usage 60 25
age=$(( $(date +%s) - $(jq -r '.ts // 0' "$STATE" 2>/dev/null || echo 0) ))
[ "$age" -gt 600 ] && log "WARNING: limit data is stale (${age}s old): /usage could not be read"
p=$(effective_pct)
thr=$(threshold)
if [ -n "$p" ] && ge "$p" "$thr"; then
  log "Stop: limit ${p}% >= ${thr}%, planning sleep + wake"
  launch_sleeper
  exit 0
fi

# Task not finished and the limit is safe: do not stop, keep going. Counter guards against an endless loop.
n=$(( $(cat "$U/forced.count" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$U/forced.count"
if [ "$n" -gt 300 ]; then
  log "Stop: shut down after 300 forced continuations"
  notify "300 forced continuations exceeded, sleep system turned off"
  bash "$U/sleep.sh" off >/dev/null
  exit 0
fi
echo "The task is not finished yet (limit ${p:-?}%). Do not stop: move on to the next step. If the task is truly finished run 'bash ~/.claude/sleep/sleep.sh done'; if you hit a blocker you cannot resolve run 'bash ~/.claude/sleep/sleep.sh blocked \"reason\"'." >&2
exit 2
