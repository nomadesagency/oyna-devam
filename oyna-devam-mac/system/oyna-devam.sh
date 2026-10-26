#!/bin/bash
# Oyna Devam — control command
#   oyna-devam.sh on [--project DIR] [--threshold 90] [--mode auto] [--resume stream|terminal|vscode|headless]
#              [--profile away|working] [--watch]
#   oyna-devam.sh off | status | done | blocked "reason" | cancel | watch | doctor | reset
#   oyna-devam.sh prompt [--task-file F | "task text"] [--threshold N] [--mode M] [--resume R] [--profile away|working] [--no-watch]
. "$(dirname "$0")/common.sh"
mkdir -p "$U"
cmd="${1:-status}"; shift || true

case "$cmd" in
  on)
    project="$PWD"; thr=90; mode="auto"; profile="away"; resume="stream"; watch=0
    while [ $# -gt 0 ]; do
      case "$1" in
        --resume) resume="$2"; shift 2 ;;
        --profile) profile="$2"; shift 2 ;;
        --project) project="$2"; shift 2 ;;
        --threshold) thr="$2"; shift 2 ;;
        --mode) mode="$2"; shift 2 ;;
        --watch) watch=1; shift ;;
        *) echo "unknown argument: $1" >&2; exit 1 ;;
      esac
    done
    case "$mode" in default|acceptEdits|auto|bypassPermissions|plan) ;; *) echo "invalid mode: $mode" >&2; exit 1 ;; esac
    case "$resume" in stream|terminal|vscode|headless) ;; *) echo "invalid resume: $resume (stream|terminal|vscode|headless)" >&2; exit 1 ;; esac
    case "$profile" in away|working) ;; *) echo "invalid profile: $profile (away|working)" >&2; exit 1 ;; esac
    # away: dark display, computer suspends at the limit and when the task ends | working: display on, computer never suspends
    if [ "$profile" = away ]; then dark=1; final_suspend=true; else dark=0; final_suspend=false; fi
    rm -f "$DONE" "$BLOCKED" "$CANCEL" "$U/forced.count" "$U/wrapup.sent" "$U/next-wake.epoch"
    jq -n --arg p "$project" --argjson t "$thr" --arg m "$mode" --argjson d "$dark" --arg r "$resume" --argjson fs "$final_suspend" --arg pr "$profile" \
      '{project:$p, threshold:$t, mode:$m, profile:$pr, dark:($d==1), resume:$r, final_suspend:$fs, suspend_at_limit:$fs, session:"", rebind:false}' > "$ACTIVE"
    start_caffeinate
    bash "$U/usage-refresh.sh"
    log "ON project=$project threshold=$thr mode=$mode resume=$resume"
    echo "Oyna Devam ON — profile: $profile, project: $project, threshold: $thr%, resume: $resume, permission mode: $mode"
    if [ -f "$STATE" ]; then echo "current limit reading: $(jq -r '.five_hour_pct' "$STATE")% used, resets at $(date -r "$(jq -r '.resets_at' "$STATE")" '+%F %T' 2>/dev/null)"; else echo "WARNING: could not read the limit (usage-refresh failed, see the log)"; fi
    if [ "$watch" = 1 ]; then
      printf '#!/bin/zsh\nexec bash %q 3\n' "$U/watch.sh" > "$U/watch.command"; chmod +x "$U/watch.command"
      # "working" profile: open the window in the background so it does not take focus away from the user
      if [ "$profile" = working ]; then open -g -a Terminal "$U/watch.command"; else open -a Terminal "$U/watch.command"; fi
      echo "live status window opened (Terminal)"
    fi
    if [ "$dark" = 1 ]; then pmset displaysleepnow; start_dark_guard; fi
    ;;
  off)
    rm -f "$ACTIVE" "$U/forced.count" "$U/wrapup.sent" "$U/next-wake.epoch"
    stop_caffeinate
    stop_dark_guard
    if [ -f "$U/waiter.pid" ]; then touch "$CANCEL"; kill "$(cat "$U/waiter.pid")" 2>/dev/null; rm -f "$U/waiter.pid"; fi
    log "OFF"
    echo "Oyna Devam OFF"
    ;;
  done)
    touch "$DONE"; log "DONE marked"; echo "task marked as finished" ;;
  blocked)
    printf '%s\n' "${1:-no reason given}" > "$BLOCKED"; log "BLOCKED: ${1:-}"; echo "blocker marked" ;;
  cancel)
    touch "$CANCEL"; log "CANCEL"; echo "pending suspend cancelled" ;;
  watch)
    exec bash "$U/watch.sh" "${1:-3}" ;;
  status)
    if is_active; then echo "ON:"; cat "$ACTIVE"; echo; else echo "OFF"; fi
    echo "limit status:"; [ -f "$STATE" ] && cat "$STATE" || echo "(no data yet)"
    if [ -f "$U/waiter.pid" ] && kill -0 "$(cat "$U/waiter.pid")" 2>/dev/null; then echo "suspend/wake job waiting (pid $(cat "$U/waiter.pid"))"; fi
    echo "--- log (last 10)"; tail -10 "$LOG" 2>/dev/null
    ;;
  reset)
    # Resets the working state (the installation stays): stops pending jobs, deletes log/progress/flag files.
    bash "$U/oyna-devam.sh" off >/dev/null 2>&1
    rm -f "$DONE" "$BLOCKED" "$CANCEL" "$STATE" "$LOG" "$PROGRESS" "$U"/*.pid "$U/forced.count" "$U/wrapup.sent" "$U/next-wake.epoch" \
          "$U/resume.command" "$U/watch.command" "$U/resume-prompt.txt" "$U/resume-raw.log" "$U/resume-run.log" "$U/usage.out."* "$U/active.json.tmp"
    rmdir "$U/refresh.lock" 2>/dev/null
    echo "Oyna Devam state reset (installation left in place)."
    ;;
  doctor)
    ok() { printf '  [ok]  %s\n' "$1"; }; bad() { printf '  [!!]  %s\n' "$1"; rc=1; }; rc=0
    echo "Oyna Devam health check"
    [ "$(uname)" = Darwin ] && ok "macOS" || bad "not macOS (pmset/caffeinate exist only on macOS)"
    for t in jq perl python3 caffeinate pmset osascript; do command -v $t >/dev/null && ok "$t" || bad "$t not found"; done
    b=$(claude_bin); [ -n "$b" ] && ok "claude: $b" || bad "claude binary not found (set OYNA_DEVAM_CLAUDE_BIN)"
    S="$HOME/.claude/settings.json"
    if [ -f "$S" ]; then
      for h in hook-pretooluse hook-posttool hook-stop hook-stopfailure; do
        grep -q "oyna-devam/$h.sh" "$S" && ok "settings.json hook: $h" || bad "settings.json has no $h (run install.sh)"
      done
    else bad "$S missing"; fi
    if sudo -n /usr/bin/pmset schedule wake "01/01/40 00:00:00" >/dev/null 2>&1; then
      sudo -n /usr/bin/pmset schedule cancel wake "01/01/40 00:00:00" >/dev/null 2>&1; ok "sudo pmset schedule wake (passwordless) works"
    else bad "no sudo pmset permission: a wake cannot be scheduled and the computer will stay awake instead (install.sh sets up the sudoers rule)"; fi
    if [ -n "$b" ]; then
      # one real reading through the SAME parser the system uses; then check that the reset time was understood
      before=$(jq -r '.ts // 0' "$STATE" 2>/dev/null || echo 0)
      bash "$U/usage-refresh.sh"
      after=$(jq -r '.ts // 0' "$STATE" 2>/dev/null || echo 0)
      if [ "${after:-0}" -le "${before:-0}" ] || [ ! -f "$STATE" ]; then
        bad "'claude -p /usage' gave no readable limit line (are you logged in? is another refresh running?) - see $LOG"
      else
        pct=$(jq -r '.five_hour_pct' "$STATE"); rs=$(jq -r '.resets_at' "$STATE"); est=$(jq -r '.resets_estimated // false' "$STATE")
        if [ "$est" = true ]; then
          bad "limit readable ($pct% used) but the RESET TIME was not understood: a safe estimate (+5 h) is used instead. The system still works, it just wakes at the latest possible moment. Send the 'WARNING reset time not understood' line from $LOG to whoever maintains this."
        else
          ok "limit readable: $pct% used, resets $(date -r "$rs" '+%F %T')"
        fi
      fi
    fi
    echo "  [i]   For --resume terminal, first run 'claude --permission-mode bypassPermissions' once by hand and accept the warning; stream mode (default) does not need this."
    exit $rc
    ;;
  prompt)
    mode="auto"; thr=90; resume="stream"; profile="away"; watchf="--watch"; task=""; tfile=""
    while [ $# -gt 0 ]; do
      case "$1" in
        --task-file) tfile="$2"; shift 2 ;;
        --mode) mode="$2"; shift 2 ;;
        --threshold) thr="$2"; shift 2 ;;
        --resume) resume="$2"; shift 2 ;;
        --profile) profile="$2"; shift 2 ;;
        --no-watch) watchf=""; shift ;;
        *) task="${task:+$task }$1"; shift ;;
      esac
    done
    [ -n "$tfile" ] && task="$(cat "$tfile")"
    [ -z "$task" ] && { echo "Give a task: oyna-devam.sh prompt \"task...\"  or  --task-file file" >&2; exit 1; }
    case "$profile" in away|working) ;; *) echo "invalid profile: $profile (away|working)" >&2; exit 1 ;; esac
    if [ "$profile" = away ]; then
      profile_note="Profile: AWAY - the user is away from the computer. The system turns the display off right away (the computer keeps running, so a dark screen is expected; if the user wakes the display before the task is finished it is turned off again after at most 120 s)."
      limit_note="Do not suspend the computer yourself and do not run \`pmset\`. After you stop, the system waits 120 s (cloud sync), schedules a wake for the moment the limit resets, suspends the computer, and on wake resumes you in the same session in a visible window; the display is turned off again 120 s after the wake."
      final_text="Do not suspend the computer yourself: 120 seconds after the turn ends the system suspends the computer (it waits for cloud sync). Add the note \"the computer will suspend in 120 s\" to your final summary."
    else
      profile_note="Profile: WORKING - the user keeps using the computer for other work. The display stays on and the computer is never suspended or the display switched off."
      limit_note="Do not suspend the computer yourself and do not run \`pmset\`. After you stop, the system keeps the computer awake, notes when the limit resets, waits until then without disturbing the user, and resumes you in the same session in a window that does not take focus."
      final_text="Do not suspend the computer yourself: in this profile the system does NOT suspend the computer, so do not mention suspend in your final summary."
    fi
    out=$(TASK="$task" THR="$thr" MODE="$mode" RESUME="$resume" PROFILE="$profile" FLAGS="$watchf" PNOTE="$profile_note" LNOTE="$limit_note" FINAL="$final_text" python3 - "$U/task-template.md" <<'PY'
import os,sys
t=open(sys.argv[1],encoding='utf-8').read()
for k,v in {"{{TASK}}":os.environ["TASK"],"{{THRESHOLD}}":os.environ["THR"],"{{MODE}}":os.environ["MODE"],"{{RESUME}}":os.environ["RESUME"],"{{PROFILE}}":os.environ["PROFILE"],"{{EXTRA_FLAGS}}":os.environ["FLAGS"],"{{PROFILE_NOTE}}":os.environ["PNOTE"],"{{LIMIT_NOTE}}":os.environ["LNOTE"],"{{FINAL_NOTE}}":os.environ["FINAL"]}.items():
    t=t.replace(k,v)
sys.stdout.write(t)
PY
)
    printf '%s\n' "$out"
    if command -v pbcopy >/dev/null; then printf '%s\n' "$out" | pbcopy; echo "--- (task prompt copied to the clipboard: paste it into a new session)" >&2; fi
    ;;
  *) echo "usage: oyna-devam.sh on|off|status|done|blocked|cancel|watch|doctor|reset|prompt" >&2; exit 1 ;;
esac
