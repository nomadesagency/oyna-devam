# Task finished and the final summary written: wait for cloud sync, then suspend the computer (no wake is scheduled).
# Cancel: oyna-devam.ps1 cancel. Testing: OYNA_DEVAM_DRY=1, OYNA_DEVAM_SYNC_DELAY=seconds.
. (Join-Path $PSScriptRoot 'common.ps1')
$delay = 120
if ($env:OYNA_DEVAM_SYNC_DELAY) { $delay = [int]$env:OYNA_DEVAM_SYNC_DELAY }
Remove-Item $CANCEL -Force -ErrorAction SilentlyContinue
Write-Log "final-suspend: computer will suspend in $delay s"
Send-Notify "Task finished. The computer will suspend in $delay s."
Start-Sleep -Seconds $delay
if (Test-Path $CANCEL) { Write-Log 'final-suspend: cancelled'; exit 0 }
if ($env:OYNA_DEVAM_DRY -eq '1') { Write-Log 'DRY: suspend not called (final)'; exit 0 }
Write-Log 'final-suspend: suspending'
Invoke-Suspend
