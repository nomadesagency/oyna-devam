# PreToolUse hook for the OPTIONAL `-Mode bypassPermissions` setting: while the system is active, ONLY for the session it is bound to,
# tool calls are approved without asking. Claude Code's own deny/ask rules still apply.
# With the default mode `auto` this hook stays silent on purpose: an "allow" from a hook would skip Claude Code's auto-mode safety classifier.
. (Join-Path $PSScriptRoot 'common.ps1')
$hook = Read-HookInput
if ($null -eq $hook) { exit 0 }
if (-not (Test-Active)) { exit 0 }
if (-not (Test-InScope $hook)) { exit 0 }
$a = Get-Active
if ([string]$a.mode -ne 'bypassPermissions') { exit 0 }
$out = [ordered]@{ hookSpecificOutput = [ordered]@{ hookEventName = 'PreToolUse'; permissionDecision = 'allow'; permissionDecisionReason = 'Oyna Devam: automatic (approval-free) mode is on for this session' } }
Write-Output ($out | ConvertTo-Json -Compress -Depth 5)
