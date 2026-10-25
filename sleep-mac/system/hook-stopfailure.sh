#!/bin/bash
# StopFailure (rate_limit) hook: if the limit filled up before the threshold was noticed, still plan sleep + wake.
. "$(dirname "$0")/common.sh"
input=$(cat)
is_active || exit 0
in_scope "$input" || exit 0
{ [ -f "$DONE" ] || [ -f "$BLOCKED" ]; } && exit 0
log "StopFailure rate_limit: planning sleep + wake"
refresh_usage 30 20   # best effort: a fresh reset time makes the wake exact
launch_sleeper
exit 0
