# PostToolUse hook. Two jobs:
#  1) When `oyna-devam.ps1 on` is run, bind the session that ran it to active.json (session isolation).
#  2) When the limit threshold is reached, inject a "finish the current step and stop" context into Claude (once per window).
. (Join-Path $PSScriptRoot 'common.ps1')
$hook = Read-HookInput
if ($null -eq $hook) { exit 0 }
if (-not (Test-Active)) { exit 0 }

# 1) bind the session
$cmd = ''
if ($hook.tool_input -and $hook.tool_input.command) { $cmd = [string]$hook.tool_input.command }
$sid = ''
if ($hook.session_id) { $sid = [string]$hook.session_id }
if ($sid -and ($cmd -match 'oyna-devam\.(ps1|cmd)["'']?\s+on(\s|$)')) {
  Set-ActiveProp 'session' $sid
  Set-ActiveProp 'rebind' $false
  Write-Log ("session bound: " + $sid)
}

if (-not (Test-InScope $hook)) { exit 0 }
if ((Test-Path $DONE) -or (Test-Path $BLOCKED)) { exit 0 }

Start-UsageRefreshAsync 120
$p = Get-EffectivePct
if ($null -eq $p) { exit 0 }
$thr = Get-Threshold
if ($p -lt $thr) { exit 0 }

$s = Read-Json $STATE
$r = [string]$s.resets_at
$marker = Join-Path $U 'wrapup.sent'
if ((Test-Path $marker) -and ((Get-Content $marker -Raw).Trim() -eq $r)) { exit 0 }
Set-Content -Path $marker -Value $r
Write-Log ("wrap-up context sent pct=$p resets_at=$r")

$msg = "LIMIT WARNING: the 5-hour usage limit is at $p% (threshold $thr%). Do NOT start any new sub-task. Bring the step you are working on (half-written file, command, verification) to a consistent point and finish it; then write a 'done / next step' note to ~/.claude/oyna-devam/progress.md and end your turn (do not write a final summary; the task is not finished). Do not suspend the computer yourself: the system will wait, suspend the computer, wake it when the limit resets and resume you where you left off."
$out = @{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = $msg } }
Write-Output ($out | ConvertTo-Json -Compress -Depth 5)
exit 0
