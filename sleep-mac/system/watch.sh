#!/bin/bash
# Live status board. Leave it open in a Terminal window; when the computer sleeps and wakes it simply continues.
# Usage: sleep.sh watch [seconds]    (quitting with Ctrl-C does NOT affect the task)
. "$(dirname "$0")/common.sh"
interval="${1:-3}"
fmt_dur() { local s=$1; [ "$s" -lt 0 ] && s=0; printf '%dh %02dm %02ds' $((s/3600)) $(((s%3600)/60)) $((s%60)); }
while true; do
  printf '\033[H\033[2J'
  now=$(date +%s)
  echo "SLEEP — live status        $(date '+%F %T')        (Ctrl-C quits; the task is not affected)"
  echo "------------------------------------------------------------------------------"
  if is_active; then
    echo "System   : ON  | project: $(jq -r .project "$ACTIVE")"
    echo "Profile  : $(jq -r '.profile // "away"' "$ACTIVE") ($([ "$(jq -r '.profile // "away"' "$ACTIVE")" = working ] && echo "computer stays awake, display on" || echo "display dark, computer sleeps at the limit and at the end"))"
    echo "Settings : threshold $(jq -r '.threshold' "$ACTIVE")% | permission mode: $(jq -r '.mode' "$ACTIVE") | resume: $(jq -r '.resume // "stream"' "$ACTIVE") | session: $(jq -r '.session // "(not bound)"' "$ACTIVE" | cut -c1-8)"
  else
    echo "System   : OFF"
  fi
  if [ -f "$STATE" ]; then
    p=$(jq -r '.five_hour_pct // "?"' "$STATE"); r=$(jq -r '.resets_at // 0' "$STATE"); ts=$(jq -r '.ts // 0' "$STATE")
    est=""; [ "$(jq -r '.resets_estimated // false' "$STATE")" = true ] && est=" (estimate: latest possible)"
    if [ "${r:-0}" -gt "$now" ]; then
      echo "Limit    : ${p}% (data $(fmt_dur $((now - ts))) old) | resets at: $(date -r "$r" '+%H:%M')$est (in $(fmt_dur $((r - now))))"
    else
      echo "Limit    : window has reset (last reading ${p}%)"
    fi
  else
    echo "Limit    : (no data yet)"
  fi
  [ -f "$DONE" ] && echo "Flag     : DONE (task marked finished)"
  [ -f "$BLOCKED" ] && echo "Flag     : BLOCKED — $(cat "$BLOCKED")"
  if [ -f "$U/sleeper.pid" ] && kill -0 "$(cat "$U/sleeper.pid")" 2>/dev/null; then
    nw=$(cat "$U/next-wake.epoch" 2>/dev/null || echo 0)
    echo "Sleep    : sleep/wake job WAITING — resumes at: $(date -r "$nw" '+%H:%M:%S') (in $(fmt_dur $((nw - now))))"
  else
    echo "Sleep    : no sleep pending"
  fi
  echo
  echo "--- progress.md (last 10 lines) ---"
  tail -10 "$PROGRESS" 2>/dev/null | cut -c1-150 || true
  echo
  echo "--- event log (last 8) ---"
  tail -8 "$LOG" 2>/dev/null | cut -c1-150 || true
  if [ -f "$U/resume-raw.log" ]; then
    echo
    echo "--- latest session output (live stream) ---"
    tail -n 60 "$U/resume-raw.log" | jq -r -f "$U/format.jq" 2>/dev/null | tail -8 | cut -c1-160
  fi
  sleep "$interval"
done
