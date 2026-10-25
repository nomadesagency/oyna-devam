#!/bin/bash
# Task finished and the final summary written: wait for cloud sync (Drive etc.), then put the computer to sleep (no wake is scheduled).
# Cancel: sleep.sh cancel. Testing: SLEEP_DRY=1, SLEEP_SYNC_DELAY=seconds.
. "$(dirname "$0")/common.sh"
DELAY="${SLEEP_SYNC_DELAY:-120}"
rm -f "$CANCEL"
log "final-sleep: computer will sleep in ${DELAY}s"
notify "Task finished. The computer will sleep in ${DELAY} s."
sleep "$DELAY"
if [ -f "$CANCEL" ]; then log "final-sleep: cancelled"; exit 0; fi
if [ "${SLEEP_DRY:-0}" = 1 ]; then log "DRY: pmset sleepnow not called (final)"; exit 0; fi
log "final-sleep: pmset sleepnow"
pmset sleepnow
