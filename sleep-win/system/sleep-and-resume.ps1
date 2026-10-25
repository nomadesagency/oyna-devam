# Runs detached in the background: wait for cloud sync -> create a wake task -> sleep -> after waking wait until the limit resets
# -> resume the session where it left off (in a visible window).
# For testing: SLEEP_DRY=1 (no sleeping/task creation/window), SLEEP_SYNC_DELAY=seconds, SLEEP_WAKE_MARGIN=seconds.
param(
  [Parameter(Mandatory = $true)][int64]$Resets,
  [Parameter(Mandatory = $true)][string]$Project
)
. (Join-Path $PSScriptRoot 'common.ps1')

$SyncDelay = 120
if ($env:SLEEP_SYNC_DELAY) { $SyncDelay = [int]$env:SLEEP_SYNC_DELAY }
$WakeMargin = 120            # extra margin after the reset (seconds)
if ($env:SLEEP_WAKE_MARGIN) { $WakeMargin = [int]$env:SLEEP_WAKE_MARGIN }
$WakeEarly = 60              # the scheduled wake is this many seconds before the target so the network can come up
$Dry = ($env:SLEEP_DRY -eq '1')

$pidFile = Join-Path $U 'sleeper.pid'
$wakeFile = Join-Path $U 'next-wake.epoch'
Set-Content -Path $pidFile -Value $PID
$wakeAt = $Resets + $WakeMargin
$wakeLocal = [DateTimeOffset]::FromUnixTimeSeconds($wakeAt - $WakeEarly).LocalDateTime
Set-Content -Path $wakeFile -Value $wakeAt
Write-Log ("sleeper started: resets_at=$Resets target=" + [DateTimeOffset]::FromUnixTimeSeconds($wakeAt).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss') + " scheduled wake=" + $wakeLocal.ToString('yyyy-MM-dd HH:mm:ss') + " sync_wait=${SyncDelay}s dry=$Dry")
Remove-Item $CANCEL -Force -ErrorAction SilentlyContinue

function Remove-WakeTask { Unregister-ScheduledTask -TaskName $WAKE_TASK -Confirm:$false -ErrorAction SilentlyContinue }
function Exit-Sleeper { Remove-Item $pidFile, $wakeFile -Force -ErrorAction SilentlyContinue }

# Profile: "away" -> sleep the computer and wake it at the reset | "working" -> never sleep, just wait awake until the reset.
$prof = Get-Profile
$winStyle = 'Normal'
if ($prof -eq 'working') { $SyncDelay = 0; $winStyle = 'Minimized' }
Write-Log ("profile=${prof}: " + $(if ($prof -eq 'working') { 'staying awake, waiting until ' + [DateTimeOffset]::FromUnixTimeSeconds($wakeAt).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss') } else { 'will sleep and wake' }))

# 1) Wake task: a one-time scheduled task with "WakeToRun" so it wakes the computer
$canSleep = $false
if ($prof -eq 'working') {
  # the computer is never put to sleep and no wake task is created
} elseif ($Dry) {
  Write-Log 'DRY: wake task not created'
  $canSleep = $true
} else {
  try {
    $action = New-ScheduledTaskAction -Execute 'cmd.exe' -Argument '/c exit 0'
    $trigger = New-ScheduledTaskTrigger -Once -At $wakeLocal
    $settings = New-ScheduledTaskSettingsSet -WakeToRun -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $WAKE_TASK -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
    $canSleep = $true
    Write-Log ("wake task scheduled: " + $wakeLocal.ToString('yyyy-MM-dd HH:mm:ss'))
  } catch {
    Write-Log ("WARNING: could not create the wake task: " + $_.Exception.Message + " Staying awake and resuming when the limit resets.")
    Send-Notify 'Could not schedule a wake; the computer will stay awake and resume when the limit resets.'
  }
}

if ($SyncDelay -gt 0) { Start-Sleep -Seconds $SyncDelay }    # for cloud sync (Drive etc.)
if (Test-Path $CANCEL) {
  Write-Log 'cancelled (CANCEL), sleeper exiting'
  if (-not $Dry) { Remove-WakeTask }
  Exit-Sleeper; exit 0
}

# 2) Sleep
if ($canSleep) {
  if ($Dry) {
    Write-Log 'DRY: sleep not called'
  } else {
    Write-Log 'going to sleep'
    Stop-KeepAwake
    Invoke-Suspend
    Write-Log 'woke up'
    Start-KeepAwake
  }
}

# 3) Wait for the target time (after waking the clock has moved on)
Write-Log ("woke/waiting: target time " + [DateTimeOffset]::FromUnixTimeSeconds($wakeAt).LocalDateTime.ToString('HH:mm:ss'))
while ((Now-Epoch) -lt $wakeAt) {
  if (Test-Path $CANCEL) { break }
  Start-Sleep -Seconds 5
}
if ((Test-Path $CANCEL) -or -not (Test-Active)) {
  Write-Log 'cancelled/turned off while waiting; not resuming'
  if (-not $Dry) { Remove-WakeTask }
  Exit-Sleeper; exit 0
}
Start-Sleep -Seconds 20   # network
if (-not $Dry) { Remove-WakeTask }

# 4) Resume the session
$a = Get-Active
$mode = 'auto'
if ($a.mode) { $mode = [string]$a.mode }
$sid = [string]$a.session
$resumeMode = 'stream'
if ($a.resume) { $resumeMode = [string]$a.resume }
$bin = Get-ClaudeBin
$thr = Get-Threshold
$prompt = "RESUME AFTER SLEEP: the 5-hour limit has reset. Read ~/.claude/sleep/progress.md and the task definition in the conversation history, and carry on from where you left off without stopping. The same automatic sleep/resume rules apply (threshold $thr%, run 'powershell -NoProfile -ExecutionPolicy Bypass -File ~/.claude/sleep/sleep.ps1 done' when finished)."

if (-not $bin) {
  Write-Log 'ERROR: claude binary not found, cannot resume'
  Send-Notify 'claude not found, could not resume'
  Exit-Sleeper; exit 1
}
$promptFile = Join-Path $U 'resume-prompt.txt'
[System.IO.File]::WriteAllText($promptFile, $prompt, (New-Object System.Text.UTF8Encoding($false)))

# Resume the known session id, otherwise the latest conversation. If the id changes the hook rebinds.
$sel = '--continue'
if ($sid) { $sel = "--resume $sid" }
Set-ActiveProp 'rebind' $true
Remove-Item (Join-Path $U 'forced.count') -Force -ErrorAction SilentlyContinue
Exit-Sleeper

$rawLog = Join-Path $U 'resume-raw.log'
$fmt = Join-Path $U 'format-stream.ps1'
$esc = { param($t) return ([string]$t).Replace("'", "''") }

if ($resumeMode -eq 'terminal') {
  $tpl = @'
[Console]::OutputEncoding = (New-Object System.Text.UTF8Encoding($false))
Set-Location -LiteralPath '__PROJECT__'
Write-Host ("=== sleep: resuming the session (" + (Get-Date -Format 'HH:mm:ss') + ") ===")
$prompt = Get-Content -Raw -Encoding UTF8 -LiteralPath '__PROMPT__'
& '__BIN__' __SEL__ --permission-mode __MODE__ $prompt
'@
} else {
  $tpl = @'
[Console]::OutputEncoding = (New-Object System.Text.UTF8Encoding($false))
Set-Location -LiteralPath '__PROJECT__'
Write-Host ("=== sleep: resuming the session (" + (Get-Date -Format 'HH:mm:ss') + ") ===")
$prompt = Get-Content -Raw -Encoding UTF8 -LiteralPath '__PROMPT__'
& '__BIN__' -p __SEL__ --permission-mode __MODE__ --output-format stream-json --verbose $prompt | ForEach-Object { Add-Content -Path '__RAW__' -Value $_ -Encoding UTF8; $_ } | & '__FMT__'
Write-Host ''
Write-Host '=== turn finished. If the limit fills up the sleep/wake loop continues; to follow progress: powershell -File ~/.claude/sleep/sleep.ps1 watch ==='
'@
}
$content = $tpl.Replace('__PROJECT__', (& $esc $Project)).Replace('__PROMPT__', (& $esc $promptFile)).Replace('__BIN__', (& $esc $bin)).Replace('__SEL__', $sel).Replace('__MODE__', $mode).Replace('__RAW__', (& $esc $rawLog)).Replace('__FMT__', (& $esc $fmt))
$resumeScript = Join-Path $U 'resume.ps1'
[System.IO.File]::WriteAllText($resumeScript, ([string][char]0xFEFF) + $content, (New-Object System.Text.UTF8Encoding($false)))

if ($Dry) {
  Write-Log "DRY: resume ($resumeMode) not started"
} elseif (($resumeMode -eq 'vscode') -and $sid) {
  # EXPERIMENTAL: opens the session in the VS Code Claude panel. The prompt is typed into the box but may not be sent automatically.
  Write-Log "starting resume (vscode): session=$sid"
  Start-Process ("vscode://anthropic.claude-code/open?session=" + $sid + "&prompt=" + [System.Uri]::EscapeDataString($prompt))
} elseif ($resumeMode -eq 'headless') {
  Write-Log "starting resume (headless): $bin -p $sel (mode=$mode)"
  $argList = @('-p') + ($sel -split ' ') + @('--permission-mode', $mode, (Q $prompt))
  Start-Process -FilePath $bin -ArgumentList $argList -WorkingDirectory $Project -WindowStyle Hidden -RedirectStandardOutput (Join-Path $U 'resume-run.log') -RedirectStandardError (Join-Path $U 'resume-run.err') | Out-Null
} else {
  Write-Log "starting resume ($resumeMode, PowerShell window): $bin $sel (mode=$mode)"
  Start-Process -FilePath 'powershell' -WindowStyle $winStyle -WorkingDirectory $Project -ArgumentList @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Q $resumeScript)) | Out-Null
}
# "away" profile: the wake lights the display; dark-guard.ps1 turns it off again 120 s after the wake (nothing to do here).
