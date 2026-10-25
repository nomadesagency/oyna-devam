# sleep (Windows) — shared functions. Other scripts dot-source this file:  . (Join-Path $PSScriptRoot 'common.ps1')
# Compatible with Windows PowerShell 5.1 and PowerShell 7.
# BOM-less UTF-8 (in PowerShell 5.1 a BOM can leak into stdout and corrupt the hook JSON)
$Utf8NoBom = New-Object System.Text.UTF8Encoding($false)
try { [Console]::OutputEncoding = $Utf8NoBom } catch {}
try { [Console]::InputEncoding = $Utf8NoBom } catch {}
$OutputEncoding = $Utf8NoBom

if ($env:SLEEP_HOME) { $U = $env:SLEEP_HOME } else { $U = Join-Path $env:USERPROFILE '.claude\sleep' }
$STATE    = Join-Path $U 'state.json'     # written by usage-refresh: {five_hour_pct, resets_at, ts}
$ACTIVE   = Join-Path $U 'active.json'    # written by `sleep.ps1 on`: {project, threshold, mode, resume, session, ...}
$DONE     = Join-Path $U 'DONE'
$BLOCKED  = Join-Path $U 'BLOCKED'
$CANCEL   = Join-Path $U 'CANCEL'
$LOG      = Join-Path $U 'log.txt'
$PROGRESS = Join-Path $U 'progress.md'
$WAKE_TASK = 'ClaudeSleepWake'

function Q([string]$p) { return '"' + $p + '"' }
function Now-Epoch { return [int64][DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

function Write-Log([string]$msg) {
  try { Add-Content -Path $LOG -Value ('{0} {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $msg) -Encoding UTF8 } catch {}
}

function Read-Json([string]$path) {
  if (-not (Test-Path $path)) { return $null }
  try { return (Get-Content -Path $path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Write-Json($obj, [string]$path) {
  $json = $obj | ConvertTo-Json -Depth 20
  $tmp = "$path.tmp"
  [System.IO.File]::WriteAllText($tmp, $json, (New-Object System.Text.UTF8Encoding($false)))
  Move-Item -Path $tmp -Destination $path -Force
}

function Test-Active { return (Test-Path $ACTIVE) }
function Get-Active { return (Read-Json $ACTIVE) }

# Profile of the running task: "away" (user is away: dark display, computer sleeps at the limit and at the end)
# or "working" (user keeps working: display on, the computer never sleeps).
function Get-Profile { $a = Get-Active; if ($a -and $a.profile) { return [string]$a.profile } else { return 'away' } }

function Set-ActiveProp([string]$name, $value) {
  $a = Get-Active
  if ($null -eq $a) { return }
  $a | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force
  Write-Json $a $ACTIVE
}

function Get-Threshold {
  $a = Get-Active
  if ($a -and $a.threshold) { return [double]$a.threshold }
  return 90
}

# If the window has already reset (resets_at in the past) usage counts as 0. Returns $null when there is no data.
function Get-EffectivePct {
  $s = Read-Json $STATE
  if ($null -eq $s -or $null -eq $s.five_hour_pct) { return $null }
  if ([int64]$s.resets_at -le (Now-Epoch)) { return 0 }
  return [double]$s.five_hour_pct
}

function Test-UsageStale([int]$secs) {
  $s = Read-Json $STATE
  if ($null -eq $s -or $null -eq $s.ts) { return $true }
  return (((Now-Epoch) - [int64]$s.ts) -ge $secs)
}

# $maxWait bounds how long /usage may take (hooks have timeouts)
function Invoke-UsageRefresh([int]$secs = 120, [int]$maxWait = 60) {
  if (Test-UsageStale $secs) {
    $oldTmo = $env:SLEEP_USAGE_TIMEOUT
    $env:SLEEP_USAGE_TIMEOUT = "$maxWait"
    try { & (Join-Path $U 'usage-refresh.ps1') | Out-Null } finally { $env:SLEEP_USAGE_TIMEOUT = $oldTmo }
  }
}

function Start-UsageRefreshAsync([int]$secs = 120) {
  if (Test-UsageStale $secs) {
    Start-Process -FilePath 'powershell' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Q (Join-Path $U 'usage-refresh.ps1'))) | Out-Null
  }
}

# Find the claude binary: SLEEP_CLAUDE_BIN > VS Code extension (newest) > PATH > common locations
function Get-ClaudeBin {
  if ($env:SLEEP_CLAUDE_BIN -and (Test-Path $env:SLEEP_CLAUDE_BIN)) { return $env:SLEEP_CLAUDE_BIN }
  $ext = Join-Path $env:USERPROFILE '.vscode\extensions'
  if (Test-Path $ext) {
    $dirs = Get-ChildItem -Path $ext -Directory -Filter 'anthropic.claude-code-*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending
    foreach ($d in $dirs) {
      $p = Join-Path $d.FullName 'resources\native-binary\claude.exe'
      if (Test-Path $p) { return $p }
    }
  }
  $cmd = Get-Command claude -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) { return $cmd.Source }
  # Claude desktop app bundles its own Claude Code binary: <root>\claude-code\<version>\claude.exe
  #  - the app sees it under %APPDATA%\Claude\claude-code (verified in public bug reports)
  #  - Microsoft Store / MSIX installs virtualize %APPDATA%: other programs only see the real file under
  #    %LOCALAPPDATA%\Packages\Claude_<id>\LocalCache\Roaming\Claude\claude-code\<version>\claude.exe
  $roots = @()
  if ($env:APPDATA) { $roots += (Join-Path $env:APPDATA 'Claude\claude-code') }
  if ($env:LOCALAPPDATA) {
    $pk = Join-Path $env:LOCALAPPDATA 'Packages'
    if (Test-Path $pk) {
      foreach ($pd in (Get-ChildItem -Path $pk -Directory -Filter 'Claude_*' -ErrorAction SilentlyContinue)) {
        $roots += (Join-Path $pd.FullName 'LocalCache\Roaming\Claude\claude-code')
      }
    }
  }
  $found = @()
  foreach ($r in $roots) {
    if (-not (Test-Path $r)) { continue }
    foreach ($d in (Get-ChildItem -Path $r -Directory -ErrorAction SilentlyContinue)) {
      $p = Join-Path $d.FullName 'claude.exe'
      if (Test-Path $p) {
        $v = [version]'0.0.0'
        try { $v = [version]$d.Name } catch {}
        $found += [pscustomobject]@{ Path = $p; Ver = $v }
      }
    }
  }
  if ($found.Count -gt 0) { return ($found | Sort-Object Ver -Descending | Select-Object -First 1).Path }
  $cands = @((Join-Path $env:USERPROFILE '.local\bin\claude.exe'), (Join-Path $env:USERPROFILE '.claude\local\claude.exe'))
  if ($env:APPDATA) { $cands += (Join-Path $env:APPDATA 'npm\claude.cmd') }
  foreach ($p in $cands) { if (Test-Path $p) { return $p } }
  return $null
}

function Send-Notify([string]$msg) {
  Write-Log ("NOTIFICATION: " + $msg)
  try {
    if (Get-Command New-BurntToastNotification -ErrorAction SilentlyContinue) { New-BurntToastNotification -Text 'sleep', $msg | Out-Null }
  } catch {}
}

function Stop-ProcessFromPidFile([string]$file) {
  if (-not (Test-Path $file)) { return }
  try {
    $id = [int](Get-Content $file -ErrorAction SilentlyContinue | Select-Object -First 1)
    $pr = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($pr -and ($pr.ProcessName -match 'powershell|pwsh')) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
  } catch {}
  Remove-Item $file -Force -ErrorAction SilentlyContinue
}

# Keep the computer from going idle-to-sleep on its own while the task runs (the display may still turn off).
function Start-KeepAwake {
  Stop-KeepAwake
  $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Q (Join-Path $U 'keepawake.ps1')))
  if ((Get-Profile) -eq 'working') { $args2 += '-Display' }   # working profile: keep the display on too
  $p = Start-Process -FilePath 'powershell' -WindowStyle Hidden -PassThru -ArgumentList $args2
  Set-Content -Path (Join-Path $U 'keepawake.pid') -Value $p.Id
}
function Stop-KeepAwake { Stop-ProcessFromPidFile (Join-Path $U 'keepawake.pid') }

# Dark guard: turns the display off again if the user wakes it before the task is finished (see dark-guard.ps1)
function Start-DarkGuard {
  Stop-DarkGuard
  $p = Start-Process -FilePath 'powershell' -WindowStyle Hidden -PassThru -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Q (Join-Path $U 'dark-guard.ps1')))
  Set-Content -Path (Join-Path $U 'darkguard.pid') -Value $p.Id
}
function Stop-DarkGuard { Stop-ProcessFromPidFile (Join-Path $U 'darkguard.pid') }

# Read the hook input (JSON on stdin)
function Read-HookInput {
  try {
    $raw = [Console]::In.ReadToEnd()
    if ($raw) { return ($raw | ConvertFrom-Json) }
  } catch {}
  return $null
}

function Test-CwdInProject($hook) {
  $a = Get-Active
  if ($null -eq $hook -or -not $hook.cwd) { return $true }
  $p = ([string]$a.project).Replace('/', '\').TrimEnd('\')
  $c = ([string]$hook.cwd).Replace('/', '\').TrimEnd('\')
  if ($c -ieq $p) { return $true }
  return $c.StartsWith($p + '\', [System.StringComparison]::OrdinalIgnoreCase)
}

# Does this hook call belong to the session that ran `sleep.ps1 on`?
#  - once a session is bound only that session is affected; other sessions are left alone.
#  - the session id may change after a resume: while rebind=true the first hook from inside the project rebinds.
#  - if nothing is bound yet, the decision is made by project directory (cwd).
function Test-InScope($hook) {
  $a = Get-Active
  $sid = ''
  if ($hook -and $hook.session_id) { $sid = [string]$hook.session_id }
  $bound = [string]$a.session
  if ($bound) {
    if ($sid -eq $bound) { return $true }
    if (($a.rebind -eq $true) -and $sid -and (Test-CwdInProject $hook)) {
      Set-ActiveProp 'session' $sid
      Set-ActiveProp 'rebind' $false
      Write-Log ("session rebound: " + $sid)
      return $true
    }
    return $false
  }
  return (Test-CwdInProject $hook)
}

function Start-Sleeper {
  $s = Read-Json $STATE
  $resets = 0
  if ($s -and $s.resets_at) { $resets = [int64]$s.resets_at }
  $now = Now-Epoch
  if ($resets -le $now) {
    # the stored reset time is unusable: take one fresh reading (bounded) before falling back to the latest possible reset
    Invoke-UsageRefresh 0 20
    $s = Read-Json $STATE
    if ($s -and $s.resets_at) { $resets = [int64]$s.resets_at }
    $now = Now-Epoch
  }
  if ($resets -le $now) { $resets = $now + 18000; Write-Log 'resets_at unknown/past; falling back to +5 hours' }
  $pf = Join-Path $U 'sleeper.pid'
  if (Test-Path $pf) {
    $id = [int](Get-Content $pf | Select-Object -First 1)
    if (Get-Process -Id $id -ErrorAction SilentlyContinue) { Write-Log 'sleeper already running'; return }
  }
  $a = Get-Active
  Start-Process -FilePath 'powershell' -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Q (Join-Path $U 'sleep-and-resume.ps1')), '-Resets', "$resets", '-Project', (Q ([string]$a.project))) | Out-Null
}

# Turn the display off (Away profile). The computer keeps running.
function Set-MonitorOff {
  try {
    Add-Type -Namespace SleepTool -Name Win -MemberDefinition '[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);' -ErrorAction SilentlyContinue
    [void][SleepTool.Win]::SendMessage([IntPtr]0xFFFF, 0x0112, [IntPtr]0xF170, [IntPtr]2)
  } catch {}
}

# Put the computer to sleep (not hibernate). The function returns after the computer wakes.
function Invoke-Suspend {
  Add-Type -Namespace SleepTool -Name Power -MemberDefinition '[DllImport("powrprof.dll", SetLastError=true)] public static extern bool SetSuspendState(bool hibernate, bool forceCritical, bool disableWakeEvent);' -ErrorAction SilentlyContinue
  [void][SleepTool.Power]::SetSuspendState($false, $false, $false)
}
