#!/bin/bash
# Dark guard (only for `oyna-devam.sh on --profile away`): while the task is not finished, the display may stay on for at most
# OYNA_DEVAM_DARK_SECS (default 120) seconds after the user wakes it (e.g. to check progress); then it is turned off again.
# Started by `oyna-devam.sh on --profile away`, stopped by `oyna-devam.sh off` (or when the system is no longer active).
# Testing: OYNA_DEVAM_FAKE_DISPLAY=file (contains 1 = display on, 0 = off), OYNA_DEVAM_DRY=1 (pmset is not called).
. "$(dirname "$0")/common.sh"
LIMIT="${OYNA_DEVAM_DARK_SECS:-120}"
POLL="${OYNA_DEVAM_DARK_POLL:-5}"

display_on() {
  if [ -n "${OYNA_DEVAM_FAKE_DISPLAY:-}" ]; then [ "$(cat "$OYNA_DEVAM_FAKE_DISPLAY" 2>/dev/null)" = 1 ]; return; fi
  python3 - <<'PY'
import ctypes, sys
cg = ctypes.CDLL('/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics')
cg.CGMainDisplayID.restype = ctypes.c_uint32
cg.CGDisplayIsAsleep.argtypes = [ctypes.c_uint32]
cg.CGDisplayIsAsleep.restype = ctypes.c_int
sys.exit(1 if cg.CGDisplayIsAsleep(cg.CGMainDisplayID()) else 0)
PY
}

display_off() {
  if [ -n "${OYNA_DEVAM_FAKE_DISPLAY:-}" ]; then echo 0 > "$OYNA_DEVAM_FAKE_DISPLAY"; fi
  if [ "${OYNA_DEVAM_DRY:-0}" = 1 ]; then log "DRY: pmset displaysleepnow not called (dark guard)"; else pmset displaysleepnow; fi
}

awake_since=0; last=$(date +%s)
log "dark guard started (display may stay on at most ${LIMIT}s)"
while is_active && [ ! -f "$DONE" ]; do
  now=$(date +%s)
  # a big gap means the computer was suspended: do not count the suspend as display-on time
  [ $((now - last)) -gt $((POLL * 4)) ] && awake_since=0
  last=$now
  if display_on; then
    [ "$awake_since" -eq 0 ] && { awake_since=$now; log "dark guard: display woke up, will turn it off again in ${LIMIT}s"; }
    if [ $((now - awake_since)) -ge "$LIMIT" ]; then
      display_off; log "dark guard: display turned off again after ${LIMIT}s"; awake_since=0
    fi
  else
    awake_since=0
  fi
  sleep "$POLL"
done
log "dark guard stopped"
