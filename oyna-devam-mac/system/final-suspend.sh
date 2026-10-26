#!/bin/bash
# Task finished and the final summary written: wait for cloud sync (Drive etc.), then suspend the computer (no wake is scheduled).
# Cancel: oyna-devam.sh cancel. Testing: OYNA_DEVAM_DRY=1, OYNA_DEVAM_SYNC_DELAY=seconds.
. "$(dirname "$0")/common.sh"
DELAY="${OYNA_DEVAM_SYNC_DELAY:-120}"
rm -f "$CANCEL"
log "final-suspend: computer will suspend in ${DELAY}s"
notify "Task finished. The computer will suspend in ${DELAY} s."
sleep "$DELAY"
if [ -f "$CANCEL" ]; then log "final-suspend: cancelled"; exit 0; fi
if [ "${OYNA_DEVAM_DRY:-0}" = 1 ]; then log "DRY: pmset sleepnow not called (final)"; exit 0; fi
log "final-suspend: pmset sleepnow"
pmset sleepnow
