#!/bin/bash
# Oyna Devam — shared functions (every script sources this file)
U="${OYNA_DEVAM_HOME:-$HOME/.claude/oyna-devam}"
STATE="$U/state.json"      # written by usage-refresh: {five_hour_pct, resets_at, ts}
ACTIVE="$U/active.json"    # written by `oyna-devam.sh on`: {project, threshold, mode, resume, session, ...}
DONE="$U/DONE"
BLOCKED="$U/BLOCKED"
CANCEL="$U/CANCEL"
LOG="$U/log.txt"
PROGRESS="$U/progress.md"

log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >> "$LOG"; }

is_active() { [ -f "$ACTIVE" ]; }

# Profile of the running task: "away" (user is away: dark display, computer suspends at the limit and at the end)
# or "working" (user keeps working: display on, the computer never suspends).
profile() { jq -r '.profile // "away"' "$ACTIVE" 2>/dev/null || echo away; }

threshold() { jq -r '.threshold // 90' "$ACTIVE" 2>/dev/null || echo 90; }

# If the window has already reset (resets_at in the past) usage counts as 0.
effective_pct() {
  [ -f "$STATE" ] || return 0
  local r p
  r=$(jq -r '.resets_at // 0' "$STATE" 2>/dev/null)
  p=$(jq -r '.five_hour_pct // empty' "$STATE" 2>/dev/null)
  [ -z "$p" ] && return 0
  if [ "${r:-0}" -le "$(date +%s)" ]; then echo 0; else echo "$p"; fi
}

# Refresh usage via /usage when the data is older than $1 seconds (synchronous / background)
usage_stale() {
  local now ts
  now=$(date +%s); ts=$(jq -r '.ts // 0' "$STATE" 2>/dev/null || echo 0)
  [ $((now - ${ts:-0})) -ge "${1:-120}" ]
}
# refresh_usage <max-age-secs> <max-wait-secs>: the 2nd argument bounds how long /usage may take (hooks have timeouts)
refresh_usage() { usage_stale "${1:-120}" && OYNA_DEVAM_USAGE_TIMEOUT="${2:-60}" bash "$U/usage-refresh.sh"; return 0; }
refresh_usage_async() {
  usage_stale "${1:-120}" || return 0
  perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' bash "$U/usage-refresh.sh" </dev/null >/dev/null 2>&1 &
}

ge() { awk -v a="$1" -v b="$2" 'BEGIN{exit !(a+0 >= b+0)}'; }

# Find the claude binary: OYNA_DEVAM_CLAUDE_BIN > VS Code extension (newest) > PATH > common locations
claude_bin() {
  if [ -n "$OYNA_DEVAM_CLAUDE_BIN" ] && [ -x "$OYNA_DEVAM_CLAUDE_BIN" ]; then echo "$OYNA_DEVAM_CLAUDE_BIN"; return; fi
  local b
  b=$(ls -d "$HOME"/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude 2>/dev/null | sort -V | tail -1)
  if [ -x "$b" ]; then echo "$b"; return; fi
  b=$(command -v claude 2>/dev/null)
  if [ -n "$b" ]; then echo "$b"; return; fi
  # Claude desktop app bundles its own Claude Code binary
  b=$(ls -d "$HOME"/Library/Application\ Support/Claude/claude-code/*/claude.app/Contents/MacOS/claude 2>/dev/null | sort -V | tail -1)
  if [ -x "$b" ]; then echo "$b"; return; fi
  for b in "$HOME/.local/bin/claude" "$HOME/.claude/local/claude" /opt/homebrew/bin/claude /usr/local/bin/claude; do
    [ -x "$b" ] && { echo "$b"; return; }
  done
}

notify() { osascript -e "display notification \"$1\" with title \"Oyna Devam\"" >/dev/null 2>&1 || true; }

stop_caffeinate() {
  if [ -f "$U/caffeinate.pid" ]; then kill "$(cat "$U/caffeinate.pid")" 2>/dev/null; rm -f "$U/caffeinate.pid"; fi
}

start_caffeinate() {
  stop_caffeinate
  # -i: prevent idle suspend. "working" profile also keeps the display on (-d). 12-hour safety limit.
  local flags="-i"; [ "$(profile)" = working ] && flags="-d -i"
  perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' caffeinate $flags -t 43200 </dev/null >/dev/null 2>&1 &
  echo $! > "$U/caffeinate.pid"
}

stop_dark_guard() {
  if [ -f "$U/darkguard.pid" ]; then kill "$(cat "$U/darkguard.pid")" 2>/dev/null; rm -f "$U/darkguard.pid"; fi
}

start_dark_guard() {
  stop_dark_guard
  perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' bash "$U/dark-guard.sh" </dev/null >/dev/null 2>&1 &
  echo $! > "$U/darkguard.pid"
}

cwd_in_project() {
  local cwd project
  cwd=$(jq -r '.cwd // empty' <<<"$1")
  project=$(jq -r '.project // empty' "$ACTIVE")
  [ -z "$cwd" ] && return 0
  case "$cwd" in "$project"|"$project"/*) return 0 ;; *) return 1 ;; esac
}

# Does this hook call belong to the session that ran `oyna-devam.sh on`?
#  - once a session is bound (active.json .session) only that session is affected; others are left alone.
#  - the session id may change after a resume: while .rebind=true the first hook from inside the project rebinds.
#  - if nothing is bound yet, the decision is made by project directory (cwd).
in_scope() {
  local input="$1" sid bound rebind
  sid=$(jq -r '.session_id // empty' <<<"$input")
  bound=$(jq -r '.session // empty' "$ACTIVE")
  rebind=$(jq -r '.rebind // false' "$ACTIVE")
  if [ -n "$bound" ]; then
    [ "$sid" = "$bound" ] && return 0
    if [ "$rebind" = true ] && [ -n "$sid" ] && cwd_in_project "$input"; then
      jq --arg s "$sid" '.session=$s | .rebind=false' "$ACTIVE" > "$ACTIVE.tmp" && mv "$ACTIVE.tmp" "$ACTIVE"
      log "session rebound: $sid"
      return 0
    fi
    return 1
  fi
  cwd_in_project "$input"
}

launch_waiter() {
  local resets now
  resets=$(jq -r '.resets_at // 0' "$STATE" 2>/dev/null || echo 0)
  now=$(date +%s)
  if [ "${resets:-0}" -le "$now" ]; then
    # the stored reset time is unusable: take one fresh reading (bounded) before falling back to the latest possible reset
    refresh_usage 0 20
    resets=$(jq -r '.resets_at // 0' "$STATE" 2>/dev/null || echo 0); now=$(date +%s)
  fi
  if [ "${resets:-0}" -le "$now" ]; then
    resets=$((now + 18000))
    log "resets_at unknown/past; falling back to +5 hours"
  fi
  if [ -f "$U/waiter.pid" ] && kill -0 "$(cat "$U/waiter.pid")" 2>/dev/null; then
    log "waiter already running"; return 0
  fi
  # the waiter writes its own PID to waiter.pid
  perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' bash "$U/suspend-and-resume.sh" "$resets" "$(jq -r '.project' "$ACTIVE")" </dev/null >>"$LOG" 2>&1 &
}
