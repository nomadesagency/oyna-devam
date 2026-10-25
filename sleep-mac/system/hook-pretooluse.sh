#!/bin/bash
# PreToolUse hook for the OPTIONAL `--mode bypassPermissions` setting: while the system is active, ONLY for the session it is bound to,
# tool calls are approved without asking. Claude Code's own deny/ask rules still apply.
# With the default mode `auto` this hook stays silent on purpose: an "allow" from a hook would skip Claude Code's auto-mode safety classifier.
. "$(dirname "$0")/common.sh"
input=$(cat)
is_active || exit 0
in_scope "$input" || exit 0
[ "$(jq -r '.mode // empty' "$ACTIVE")" = bypassPermissions ] || exit 0
jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse", permissionDecision:"allow", permissionDecisionReason:"sleep: automatic (approval-free) mode is on for this session"}}'
