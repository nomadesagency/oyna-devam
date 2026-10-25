# sleep (Windows) — control command
#   sleep.ps1 on [-Project DIR] [-Threshold 90] [-Mode auto] [-Resume stream|terminal|vscode|headless]
#             [-Profile away|working] [-Watch]
#   sleep.ps1 off | status | done | blocked "reason" | cancel | watch | doctor | reset
#   sleep.ps1 prompt [-TaskFile F | "task text"] [-Threshold N] [-Mode M] [-Resume R] [-Profile away|working] [-NoWatch]
param(
  [Parameter(Position = 0)][string]$Cmd = 'status',
  [Parameter(Position = 1, ValueFromRemainingArguments = $true)][string[]]$Text,
  [string]$Project = '',
  [int]$Threshold = 90,
  [string]$Mode = 'auto',
  [string]$Resume = 'stream',
  [string]$TaskFile = '',
  [Alias('Profile')][string]$Prof = 'away',
  [switch]$Watch,
  [switch]$NoWatch
)
. (Join-Path $PSScriptRoot 'common.ps1')
New-Item -ItemType Directory -Path $U -Force | Out-Null
$textJoined = ''
if ($Text) { $textJoined = ($Text -join ' ') }

switch ($Cmd) {
  'on' {
    $proj = $Project
    if (-not $proj) { $proj = (Get-Location).Path }
    if (@('default', 'acceptEdits', 'auto', 'bypassPermissions', 'plan') -notcontains $Mode) { Write-Error "invalid -Mode: $Mode"; exit 1 }
    if (@('stream', 'terminal', 'vscode', 'headless') -notcontains $Resume) { Write-Error "invalid -Resume: $Resume (stream|terminal|vscode|headless)"; exit 1 }
    if (@('away', 'working') -notcontains $Prof) { Write-Error "invalid -Profile: $Prof (away|working)"; exit 1 }
    # away: dark display, computer sleeps at the limit and when the task ends | working: display on, computer never sleeps
    $isAway = ($Prof -eq 'away')
    foreach ($f in @($DONE, $BLOCKED, $CANCEL, (Join-Path $U 'forced.count'), (Join-Path $U 'wrapup.sent'), (Join-Path $U 'next-wake.epoch'))) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    $obj = [ordered]@{
      project = $proj; threshold = $Threshold; mode = $Mode; profile = $Prof; dark = $isAway; resume = $Resume
      final_sleep = $isAway; sleep_at_limit = $isAway; session = ''; rebind = $false
    }
    Write-Json ([pscustomobject]$obj) $ACTIVE
    Start-KeepAwake
    & (Join-Path $U 'usage-refresh.ps1')
    Write-Log "ON project=$proj threshold=$Threshold mode=$Mode resume=$Resume"
    Write-Output "sleep ON — profile: $Prof, project: $proj, threshold: $Threshold%, resume: $Resume, permission mode: $Mode"
    $s = Read-Json $STATE
    if ($s) {
      $rt = ''
      if ($s.resets_at) { $rt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$s.resets_at).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss') }
      Write-Output ("current limit reading: " + $s.five_hour_pct + "% used, resets at " + $rt)
    } else {
      Write-Output 'WARNING: could not read the limit (usage-refresh failed, see the log)'
    }
    if ($Watch) {
      # "working" profile: open the window minimized so it does not take focus away from the user
      $ws = 'Normal'; if (-not $isAway) { $ws = 'Minimized' }
      Start-Process -FilePath 'powershell' -WindowStyle $ws -ArgumentList @('-NoExit', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Q (Join-Path $U 'watch.ps1'))) | Out-Null
      Write-Output 'live status window opened (PowerShell)'
    }
    if ($isAway) { Set-MonitorOff; Start-DarkGuard }
  }
  'off' {
    foreach ($f in @($ACTIVE, (Join-Path $U 'forced.count'), (Join-Path $U 'wrapup.sent'), (Join-Path $U 'next-wake.epoch'))) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    Stop-KeepAwake
    Stop-DarkGuard
    if (Test-Path (Join-Path $U 'sleeper.pid')) {
      New-Item -ItemType File -Path $CANCEL -Force | Out-Null
      Stop-ProcessFromPidFile (Join-Path $U 'sleeper.pid')
    }
    Unregister-ScheduledTask -TaskName $WAKE_TASK -Confirm:$false -ErrorAction SilentlyContinue
    Write-Log 'OFF'
    Write-Output 'sleep OFF'
  }
  'done' { New-Item -ItemType File -Path $DONE -Force | Out-Null; Write-Log 'DONE marked'; Write-Output 'task marked as finished' }
  'blocked' {
    $why = $textJoined
    if (-not $why) { $why = 'no reason given' }
    Set-Content -Path $BLOCKED -Value $why -Encoding UTF8
    Write-Log "BLOCKED: $why"
    Write-Output 'blocker marked'
  }
  'cancel' {
    New-Item -ItemType File -Path $CANCEL -Force | Out-Null
    Unregister-ScheduledTask -TaskName $WAKE_TASK -Confirm:$false -ErrorAction SilentlyContinue
    Write-Log 'CANCEL'
    Write-Output 'pending sleep cancelled'
  }
  'watch' { & (Join-Path $U 'watch.ps1') }
  'status' {
    if (Test-Active) { Write-Output 'ON:'; Get-Content $ACTIVE -Raw -Encoding UTF8 } else { Write-Output 'OFF' }
    Write-Output 'limit status:'
    if (Test-Path $STATE) { Get-Content $STATE -Raw -Encoding UTF8 } else { Write-Output '(no data yet)' }
    Write-Output '--- log (last 10)'
    if (Test-Path $LOG) { Get-Content $LOG -Tail 10 -Encoding UTF8 }
  }
  'reset' {
    # Resets the working state (the installation stays): stops pending jobs, deletes log/progress/flag files.
    & $PSCommandPath off | Out-Null
    $names = @('DONE', 'BLOCKED', 'CANCEL', 'state.json', 'log.txt', 'progress.md', 'forced.count', 'wrapup.sent', 'next-wake.epoch',
               'resume.ps1', 'resume-prompt.txt', 'resume-raw.log', 'resume-run.log', 'resume-run.err', 'sleeper.pid', 'keepawake.pid', 'darkguard.pid', 'active.json.tmp')
    foreach ($n in $names) { Remove-Item (Join-Path $U $n) -Force -ErrorAction SilentlyContinue }
    Get-ChildItem -Path $U -Filter 'usage.out.*' -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Remove-Item (Join-Path $U 'refresh.lock') -Recurse -Force -ErrorAction SilentlyContinue
    Write-Output 'sleep state reset (installation left in place).'
  }
  'doctor' {
    $rc = 0
    function Ok([string]$m) { Write-Output ('  [ok]  ' + $m) }
    function Bad([string]$m) { Write-Output ('  [!!]  ' + $m); $script:rc = 1 }
    Write-Output 'sleep health check (Windows)'
    if ($env:OS -eq 'Windows_NT') { Ok 'Windows' } else { Bad 'not Windows (use the sleep-mac folder for macOS)' }
    Ok ('PowerShell ' + $PSVersionTable.PSVersion)
    $b = Get-ClaudeBin
    if ($b) { Ok ('claude: ' + $b) } else { Bad 'claude not found (set $env:SLEEP_CLAUDE_BIN)' }
    $sf = Join-Path $env:USERPROFILE '.claude\settings.json'
    if (Test-Path $sf) {
      $txt = Get-Content $sf -Raw -Encoding UTF8
      foreach ($h in @('hook-pretooluse', 'hook-posttool', 'hook-stop', 'hook-stopfailure')) {
        if ($txt -match ('sleep/' + $h + '\.ps1')) { Ok ('settings.json hook: ' + $h) } else { Bad ("settings.json has no $h (run install.ps1)") }
      }
    } else { Bad "$sf is missing" }
    try {
      $q = (& powercfg /query SCHEME_CURRENT SUB_SLEEP RTCWAKE) -join "`n"
      if ($q -match 'Current AC Power Setting Index:\s*0x00000001') { Ok 'wake timers (AC) enabled' }
      else { Bad 'wake timers may be disabled: Power Options > Advanced > Sleep > "Allow wake timers" = Enable' }
    } catch { Bad 'could not read powercfg' }
    if ($b) {
      # one real reading through the SAME parser the system uses; then check that the reset time was understood
      $before = [int64]0
      $s0 = Read-Json $STATE
      if ($s0 -and $s0.ts) { $before = [int64]$s0.ts }
      & (Join-Path $U 'usage-refresh.ps1')
      $s1 = Read-Json $STATE
      if (($null -eq $s1) -or (-not $s1.ts) -or ([int64]$s1.ts -le $before)) {
        Bad ("'claude -p /usage' gave no readable limit line (are you logged in? is another refresh running?) - see " + $LOG)
      } elseif ($s1.resets_estimated -eq $true) {
        Bad ('limit readable (' + $s1.five_hour_pct + '% used) but the RESET TIME was not understood: a safe estimate (+5 h) is used instead. The system still works, it just wakes at the latest possible moment. Send the "WARNING reset time not understood" line from ' + $LOG + ' to whoever maintains this.')
      } else {
        Ok ('limit readable: ' + $s1.five_hour_pct + '% used, resets ' + [DateTimeOffset]::FromUnixTimeSeconds([int64]$s1.resets_at).LocalDateTime.ToString('yyyy-MM-dd HH:mm:ss'))
      }
    }
    Write-Output '  [i]   For -Resume terminal, first run "claude --permission-mode bypassPermissions" once by hand and accept the warning; stream mode (default) does not need this.'
    exit $rc
  }
  'prompt' {
    $task = $textJoined
    if ($TaskFile) { $task = (Get-Content -Raw -Encoding UTF8 -Path $TaskFile) }
    if (-not $task) { Write-Error 'Give a task: sleep.ps1 prompt "task..."  or  -TaskFile file'; exit 1 }
    if (@('away', 'working') -notcontains $Prof) { Write-Error "invalid -Profile: $Prof (away|working)"; exit 1 }
    $flags = @()
    if (-not $NoWatch) { $flags += '-Watch' }
    if ($Prof -eq 'away') {
      $profileNote = 'Profile: AWAY - the user is away from the computer. The system turns the display off right away (the computer keeps running, so a dark screen is expected; if the user wakes the display before the task is finished it is turned off again after at most 120 s).'
      $limitNote = 'Do not put the computer to sleep yourself. After you stop, the system waits 120 s (cloud sync), creates a wake task for the moment the limit resets, puts the computer to sleep, and on wake resumes you in the same session in a visible PowerShell window; the display is turned off again 120 s after the wake.'
      $finalNote = 'Do not put the computer to sleep yourself: 120 seconds after the turn ends the system puts the computer to sleep (it waits for cloud sync). Add the note "the computer will sleep in 120 s" to your final summary.'
    } else {
      $profileNote = 'Profile: WORKING - the user keeps using the computer for other work. The display stays on and the computer is never put to sleep or the display switched off.'
      $limitNote = 'Do not put the computer to sleep yourself. After you stop, the system keeps the computer awake, notes when the limit resets, waits until then without disturbing the user, and resumes you in the same session in a window that does not take focus.'
      $finalNote = 'Do not put the computer to sleep yourself: in this profile the system does NOT put the computer to sleep, so do not mention sleep in your final summary.'
    }
    $tpl = Get-Content -Raw -Encoding UTF8 -Path (Join-Path $U 'task-template.md')
    $out = $tpl.Replace('{{TASK}}', $task).Replace('{{THRESHOLD}}', [string]$Threshold).Replace('{{MODE}}', $Mode).Replace('{{RESUME}}', $Resume).Replace('{{PROFILE}}', $Prof).Replace('{{EXTRA_FLAGS}}', ($flags -join ' ')).Replace('{{PROFILE_NOTE}}', $profileNote).Replace('{{LIMIT_NOTE}}', $limitNote).Replace('{{FINAL_NOTE}}', $finalNote)
    Write-Output $out
    try { Set-Clipboard -Value $out; [Console]::Error.WriteLine('--- (task prompt copied to the clipboard: paste it into a new session)') } catch {}
  }
  default { Write-Output 'usage: sleep.ps1 on|off|status|done|blocked|cancel|watch|doctor|reset|prompt'; exit 1 }
}
