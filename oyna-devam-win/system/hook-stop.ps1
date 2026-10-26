# Stop hook: the turn has ended. Decision order:
#   DONE/BLOCKED -> shut the system down | threshold exceeded -> plan suspend + wake | otherwise "keep going" (exit 2).
. (Join-Path $PSScriptRoot 'common.ps1')
$hook = Read-HookInput
if (-not (Test-Active)) { exit 0 }
if (-not (Test-InScope $hook)) { exit 0 }
$a = Get-Active
$ctl = Join-Path $U 'oyna-devam.ps1'

if (Test-Path $DONE) {
  $fs = $true
  if ($a.final_suspend -eq $false) { $fs = $false }
  Write-Log ("Stop: task DONE, shutting the system down (final_suspend=$fs)")
  & $ctl off | Out-Null
  if ($fs) {
    Start-Process -FilePath 'powershell' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Q (Join-Path $U 'final-suspend.ps1'))) | Out-Null
  }
  exit 0
}
if (Test-Path $BLOCKED) {
  $why = (Get-Content $BLOCKED -Raw).Trim()
  Write-Log ("Stop: BLOCKED ($why), shutting the system down")
  Send-Notify ("Task is blocked: " + $why)
  & $ctl off | Out-Null
  exit 0
}

# bounded read (the Stop hook has a 60 s timeout); if it fails the previous reading is used and the StopFailure hook is the backstop
Invoke-UsageRefresh 60 25
$st = Read-Json $STATE
if ($st -and $st.ts) {
  $age = (Now-Epoch) - [int64]$st.ts
  if ($age -gt 600) { Write-Log ("WARNING: limit data is stale (" + $age + "s old): /usage could not be read") }
} else { Write-Log 'WARNING: no limit data: /usage could not be read' }
$p = Get-EffectivePct
$thr = Get-Threshold
if (($null -ne $p) -and ($p -ge $thr)) {
  Write-Log ("Stop: limit $p% >= $thr%, planning suspend + wake")
  Start-Waiter
  exit 0
}

# Task not finished and the limit is safe: do not stop, keep going. Counter guards against an endless loop.
$fc = Join-Path $U 'forced.count'
$n = 1
if (Test-Path $fc) { $n = [int](Get-Content $fc | Select-Object -First 1) + 1 }
Set-Content -Path $fc -Value $n
if ($n -gt 300) {
  Write-Log 'Stop: shut down after 300 forced continuations'
  Send-Notify '300 forced continuations exceeded, Oyna Devam turned off'
  & $ctl off | Out-Null
  exit 0
}
$pTxt = '?'
if ($null -ne $p) { $pTxt = [string]$p }
[Console]::Error.WriteLine("The task is not finished yet (limit $pTxt%). Do not stop: move on to the next step. If the task is truly finished run 'powershell -NoProfile -ExecutionPolicy Bypass -File ~/.claude/oyna-devam/oyna-devam.ps1 done'; if you hit a blocker you cannot resolve run '... oyna-devam.ps1 blocked ""reason""'.")
exit 2
