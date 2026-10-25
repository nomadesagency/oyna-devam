# StopFailure (rate_limit) hook: if the limit filled up before the threshold was noticed, still plan sleep + wake.
. (Join-Path $PSScriptRoot 'common.ps1')
$hook = Read-HookInput
if (-not (Test-Active)) { exit 0 }
if (-not (Test-InScope $hook)) { exit 0 }
if ((Test-Path $DONE) -or (Test-Path $BLOCKED)) { exit 0 }
Write-Log 'StopFailure rate_limit: planning sleep + wake'
Invoke-UsageRefresh 30 20   # best effort: a fresh reset time makes the wake exact
Start-Sleeper
exit 0
