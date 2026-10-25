# Task finished and the final summary written: wait for cloud sync, then put the computer to sleep (no wake is scheduled).
# Cancel: sleep.ps1 cancel. Testing: SLEEP_DRY=1, SLEEP_SYNC_DELAY=seconds.
. (Join-Path $PSScriptRoot 'common.ps1')
$delay = 120
if ($env:SLEEP_SYNC_DELAY) { $delay = [int]$env:SLEEP_SYNC_DELAY }
Remove-Item $CANCEL -Force -ErrorAction SilentlyContinue
Write-Log "final-sleep: computer will sleep in $delay s"
Send-Notify "Task finished. The computer will sleep in $delay s."
Start-Sleep -Seconds $delay
if (Test-Path $CANCEL) { Write-Log 'final-sleep: cancelled'; exit 0 }
if ($env:SLEEP_DRY -eq '1') { Write-Log 'DRY: sleep not called (final)'; exit 0 }
Write-Log 'final-sleep: going to sleep'
Invoke-Suspend
