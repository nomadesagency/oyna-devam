#!/bin/bash
# Runs detached in the background: wait for cloud sync -> schedule a wake -> suspend -> after waking wait until the limit resets
# -> resume the session where it left off (in a visible window).
# For testing: OYNA_DEVAM_DRY=1 (no pmset/sudo/open calls), OYNA_DEVAM_SYNC_DELAY=seconds, OYNA_DEVAM_WAKE_MARGIN=seconds.
. "$(dirname "$0")/common.sh"
resets="$1"; project="$2"
SYNC_DELAY="${OYNA_DEVAM_SYNC_DELAY:-120}"
WAKE_MARGIN="${OYNA_DEVAM_WAKE_MARGIN:-120}"     # extra margin after the reset (seconds)
WAKE_EARLY=60       # scheduled wake is this many seconds before the target so the network can come up
DRY="${OYNA_DEVAM_DRY:-0}"

echo $$ > "$U/waiter.pid"
wake_at=$((resets + WAKE_MARGIN))
wake_str=$(date -r "$((wake_at - WAKE_EARLY))" '+%m/%d/%y %H:%M:%S')
echo "$wake_at" > "$U/next-wake.epoch"
log "waiter started: resets_at=$resets target=$(date -r "$wake_at" '+%F %T') scheduled wake=$wake_str sync_wait=${SYNC_DELAY}s dry=$DRY"
rm -f "$CANCEL"

# Profile: "away" -> suspend the computer and wake it at the reset | "working" -> never suspend, just wait awake until the reset.
PROFILE=$(profile)
CAF="-i"; OPEN="open -a Terminal"
if [ "$PROFILE" = working ]; then CAF="-d -i"; OPEN="open -g -a Terminal"; SYNC_DELAY=0; fi
log "profile=$PROFILE: $([ "$PROFILE" = working ] && echo "staying awake, waiting until $(date -r "$wake_at" '+%F %T')" || echo "will suspend and wake")"

can_suspend=0
if [ "$PROFILE" = working ]; then
  : # the computer is never suspended and no wake is scheduled
elif [ "$DRY" = 1 ]; then
  log "DRY: sudo pmset schedule wake \"$wake_str\" not called"; can_suspend=1
elif sudo -n /usr/bin/pmset schedule wake "$wake_str" >>"$LOG" 2>&1; then
  can_suspend=1; log "wake scheduled: $wake_str"
else
  log "WARNING: sudo pmset schedule wake failed (no sudoers rule? was install.sh run?). Staying awake and resuming when the limit resets."
  notify "Could not schedule a wake; the computer will stay awake and resume when the limit resets."
fi

[ "$SYNC_DELAY" -gt 0 ] && sleep "$SYNC_DELAY"   # for cloud sync (Drive etc.)
if [ -f "$CANCEL" ]; then
  log "cancelled (CANCEL), waiter exiting"
  [ "$DRY" = 1 ] || sudo -n /usr/bin/pmset schedule cancel wake "$wake_str" >>"$LOG" 2>&1
  rm -f "$U/waiter.pid" "$U/next-wake.epoch"; exit 0
fi

if [ "$can_suspend" = 1 ]; then
  if [ "$DRY" = 1 ]; then log "DRY: pmset sleepnow not called"; else log "pmset sleepnow"; pmset sleepnow; fi
fi

# After waking (the process is frozen during suspend and continues here) wait until the target time.
log "woke/waiting: target time $(date -r "$wake_at" '+%T')"
if [ "$DRY" = 1 ]; then
  while [ "$(date +%s)" -lt "$wake_at" ]; do sleep 1; [ -f "$CANCEL" ] && break; done
else
  while [ "$(date +%s)" -lt "$wake_at" ]; do caffeinate $CAF -t 30 sleep 10; [ -f "$CANCEL" ] && break; done
fi
if [ -f "$CANCEL" ] || ! is_active; then log "cancelled/turned off while waiting; not resuming"; rm -f "$U/waiter.pid" "$U/next-wake.epoch"; exit 0; fi
sleep 20  # network

mode=$(jq -r '.mode // "auto"' "$ACTIVE")
sid=$(jq -r '.session // empty' "$ACTIVE")
resume_mode=$(jq -r '.resume // "stream"' "$ACTIVE")
bin=$(claude_bin)
prompt="RESUME AFTER SUSPEND: the 5-hour limit has reset. Read ~/.claude/oyna-devam/progress.md and the task definition in the conversation history, and carry on from where you left off without stopping. The same automatic suspend/resume rules apply (threshold $(threshold)%, run 'bash ~/.claude/oyna-devam/oyna-devam.sh done' when finished)."

if [ -z "$bin" ]; then
  log "ERROR: claude binary not found, cannot resume"; notify "claude not found, could not resume"
  rm -f "$U/waiter.pid" "$U/next-wake.epoch"; exit 1
fi
printf '%s' "$prompt" > "$U/resume-prompt.txt"

# Resume the known session id, otherwise the latest conversation. If the id changes the hook rebinds.
if [ -n "$sid" ]; then sel=(--resume "$sid"); else sel=(--continue); fi
jq '.rebind=true' "$ACTIVE" > "$ACTIVE.tmp" && mv "$ACTIVE.tmp" "$ACTIVE"
rm -f "$U/forced.count" "$U/waiter.pid" "$U/next-wake.epoch"

# resume.command runs in a Terminal window so progress is VISIBLE live.
#   stream   : the claude -p stream is turned into readable lines (no permission/approval dialogs, fully automatic)
#   terminal : interactive claude session (may ask to confirm 'bypass permissions' the first time)
q() { printf '%q' "$1"; }
{
  echo '#!/bin/zsh'
  echo "cd $(q "$project") || exit 1"
  echo 'echo "=== Oyna Devam: resuming the session ($(date +%T)) ==="'
  case "$resume_mode" in
    terminal)
      echo "exec caffeinate $CAF $(q "$bin") ${sel[*]} --permission-mode $mode \"\$(cat $(q "$U/resume-prompt.txt"))\"" ;;
    *)
      echo "caffeinate $CAF $(q "$bin") -p ${sel[*]} --permission-mode $mode --output-format stream-json --verbose \"\$(cat $(q "$U/resume-prompt.txt"))\" 2>&1 | tee -a $(q "$U/resume-raw.log") | jq -r --unbuffered -f $(q "$U/format.jq")"
      echo 'echo; echo "=== turn finished. If the limit fills up the suspend/wake loop continues; to follow progress: bash ~/.claude/oyna-devam/oyna-devam.sh watch ==="'
      echo 'exec zsh -i' ;;
  esac
} > "$U/resume.command"
chmod +x "$U/resume.command"

if [ "$DRY" = 1 ]; then
  log "DRY: resume ($resume_mode) not started"
elif [ "$resume_mode" = headless ]; then
  # No window: continues the same conversation in the background, output goes to resume-run.log.
  log "starting resume (headless): $bin -p ${sel[*]} (mode=$mode)"
  ( cd "$project" && perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' caffeinate $CAF "$bin" -p "${sel[@]}" --permission-mode "$mode" "$prompt" </dev/null >>"$U/resume-run.log" 2>&1 & )
elif [ "$resume_mode" = vscode ] && [ -n "$sid" ]; then
  # EXPERIMENTAL: opens the session in the VS Code Claude panel. The prompt is typed into the box but may not be sent automatically.
  enc=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$prompt")
  log "starting resume (vscode): session=$sid"
  open "vscode://anthropic.claude-code/open?session=$sid&prompt=$enc"
else
  log "starting resume ($resume_mode, Terminal window): $bin ${sel[*]} (mode=$mode)"
  $OPEN "$U/resume.command"
fi
# "away" profile: the wake lights the display; dark-guard.sh turns it off again 120 s after the wake (nothing to do here).
