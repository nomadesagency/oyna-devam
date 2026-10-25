# sleep (Windows) installer. Double-click install.bat, or run:
#   powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 [-NoPowercfg]
#   - copies the scripts to %USERPROFILE%\.claude\sleep\
#   - adds 4 hooks + a permission rule to %USERPROFILE%\.claude\settings.json (backed up first)
#   - tries to enable "wake timers" (powercfg)
# Safe to run again. To remove: uninstall.bat
param([switch]$NoPowercfg)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = (New-Object System.Text.UTF8Encoding($false)) } catch {}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path $here 'system'
if ($env:SLEEP_HOME) { $dest = $env:SLEEP_HOME } else { $dest = Join-Path $env:USERPROFILE '.claude\sleep' }
if ($env:SLEEP_SETTINGS) { $settingsPath = $env:SLEEP_SETTINGS } else { $settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json' }

function Say([string]$m) { Write-Host $m -ForegroundColor Cyan }
function Save-Settings([string]$path, [string]$json) {
  # atomic write (temp file, then replace); a linked settings.json is written in place instead
  $enc = New-Object System.Text.UTF8Encoding($false)
  $item = Get-Item -Path $path -ErrorAction SilentlyContinue
  if ($item -and $item.LinkType) { [System.IO.File]::WriteAllText($path, $json, $enc); return }
  $tmp = $path + '.sleep-tmp'
  [System.IO.File]::WriteAllText($tmp, $json, $enc)
  Move-Item -Path $tmp -Destination $path -Force
}

# Safety guard: only ever install into / delete a folder that is literally named "sleep" (never the user profile, a drive root or a relative path)
$refuseDest = $true   # fail closed: any doubt or error below leaves this at $true
try {
  $destT = ([string]$dest).TrimEnd('\', '/')
  $destLeaf = ($destT -split '[\\/]')[-1]
  $refuseDest = ([string]::IsNullOrEmpty($destT) -or (-not [System.IO.Path]::IsPathRooted([string]$dest)) -or ($destLeaf -ne 'sleep') -or ($destT -ieq ([string]$env:USERPROFILE).TrimEnd('\', '/')))
} catch { $refuseDest = $true }
if ($refuseDest) { Write-Host "Refusing: the install folder must be an absolute path named 'sleep' ($dest)"; exit 1 }

if ($env:OS -ne 'Windows_NT') { Write-Host 'This installer is for Windows only (use the sleep-mac folder on macOS).'; exit 1 }
if (-not (Test-Path $src)) { Write-Host "system folder not found: $src"; exit 1 }

Say ('1/4  Copying files -> ' + $dest)
New-Item -ItemType Directory -Path $dest -Force | Out-Null
# Leave working-state files (log, progress, state...) alone; only update the system files.
Get-ChildItem -Path $src -File | ForEach-Object { Copy-Item -Path $_.FullName -Destination (Join-Path $dest $_.Name) -Force }
Get-ChildItem -Path $dest -File | Unblock-File -ErrorAction SilentlyContinue
Write-Host ('     ' + (Get-ChildItem -Path $src -File).Count + ' files copied.')

Say "2/4  Adding Claude Code hooks -> $settingsPath"
New-Item -ItemType Directory -Path (Split-Path -Parent $settingsPath) -Force | Out-Null
if (-not (Test-Path $settingsPath)) { [System.IO.File]::WriteAllText($settingsPath, '{}', (New-Object System.Text.UTF8Encoding($false))) }
Copy-Item -Path $settingsPath -Destination ($settingsPath + '.sleep-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
# keep only the 3 newest backups so repeated installs do not pile up files
Get-ChildItem -Path (Split-Path -Parent $settingsPath) -Filter ((Split-Path -Leaf $settingsPath) + '.sleep-backup-*') -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -Skip 3 | Remove-Item -Force -ErrorAction SilentlyContinue

$raw = Get-Content -Path $settingsPath -Raw -Encoding UTF8
if ([string]::IsNullOrWhiteSpace($raw)) { $raw = '{}' }
$s = $raw | ConvertFrom-Json
if (-not $s.PSObject.Properties['hooks']) { $s | Add-Member -NotePropertyName hooks -NotePropertyValue ([pscustomobject]@{}) }
$hooks = $s.hooks

# Remove earlier hooks of this same system (re-install); other people's hooks are never touched
$destFwd0 = $dest.Replace('\', '/')
function Test-Ours([string]$c) { return (($c.Replace('\', '/') -like ('*' + $destFwd0 + '/hook-*')) -or ($c -match '[\\/]\.claude[\\/]sleep[\\/]hook-')) }
foreach ($ev in @($hooks.PSObject.Properties.Name)) {
  $newGroups = @()
  foreach ($g in @($hooks.$ev)) {
    $keep = @(@($g.hooks) | Where-Object { -not (Test-Ours ([string]$_.command)) })
    if ($keep.Count -gt 0) { $g.hooks = $keep; $newGroups += $g }
  }
  if ($newGroups.Count -gt 0) { $hooks.$ev = $newGroups } else { $hooks.PSObject.Properties.Remove($ev) }
}

$destFwd = $dest.Replace('\', '/')
function Add-Hook([string]$ev, [string]$script, [int]$timeout, [string]$matcher) {
  $cmd = 'powershell -NoProfile -ExecutionPolicy Bypass -File "' + $destFwd + '/' + $script + '"'
  $entry = [ordered]@{ type = 'command'; command = $cmd; timeout = $timeout }
  $grp = [ordered]@{}
  if ($matcher) { $grp['matcher'] = $matcher }
  $grp['hooks'] = @([pscustomobject]$entry)
  $newGrp = [pscustomobject]$grp
  if ($hooks.PSObject.Properties[$ev]) { $hooks.$ev = @($hooks.$ev) + @($newGrp) }
  else { $hooks | Add-Member -NotePropertyName $ev -NotePropertyValue @($newGrp) }
}
Add-Hook 'PreToolUse' 'hook-pretooluse.ps1' 10 ''
Add-Hook 'PostToolUse' 'hook-posttool.ps1' 10 ''
Add-Hook 'Stop' 'hook-stop.ps1' 60 ''
Add-Hook 'StopFailure' 'hook-stopfailure.ps1' 60 'rate_limit'

# Let the system's own control command run without a prompt, even before the session is bound (the first command of a task is `sleep.ps1 on`).
if (-not $s.PSObject.Properties['permissions']) { $s | Add-Member -NotePropertyName permissions -NotePropertyValue ([pscustomobject]@{}) }
if (-not $s.permissions.PSObject.Properties['allow']) { $s.permissions | Add-Member -NotePropertyName allow -NotePropertyValue @() }
$allow = @(@($s.permissions.allow) | Where-Object { (([string]$_).Replace('\', '/') -notlike ('*' + $destFwd0 + '/sleep.ps1*')) -and (([string]$_) -notmatch '[\\/]\.claude[\\/]sleep[\\/]sleep\.ps1') })
$allow += ('Bash(powershell -NoProfile -ExecutionPolicy Bypass -File "$HOME/.claude/sleep/sleep.ps1":*)')
$allow += ('Bash(powershell -NoProfile -ExecutionPolicy Bypass -File "' + $destFwd + '/sleep.ps1":*)')
$s.permissions.allow = $allow
$json = $s | ConvertTo-Json -Depth 30
Save-Settings $settingsPath $json
Write-Host '     hooks written (PreToolUse, PostToolUse, Stop, StopFailure) + permission rule for sleep.ps1.'

Say '3/4  Wake timers'
if ($NoPowercfg) {
  Write-Host '     skipped (-NoPowercfg). If waking does not work: Power Options > Advanced > Sleep > "Allow wake timers" = Enable.'
} else {
  try {
    & powercfg /setacvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 1 | Out-Null
    & powercfg /setdcvalueindex SCHEME_CURRENT SUB_SLEEP RTCWAKE 1 | Out-Null
    & powercfg /setactive SCHEME_CURRENT | Out-Null
    Write-Host '     enabled (plugged in and on battery).'
  } catch {
    Write-Host '     WARNING: could not change the powercfg setting. By hand: Power Options > Advanced > Sleep > "Allow wake timers" = Enable.'
  }
}

Say '4/4  Health check'
try { & (Join-Path $dest 'sleep.ps1') doctor } catch { Write-Host ('     could not run the check: ' + $_.Exception.Message) }

Write-Host ''
Write-Host 'INSTALLED.  Next steps:' -ForegroundColor Green
Write-Host '  1) Generate a task prompt (copied to the clipboard):'
Write-Host ('     "' + $dest + '\sleep.cmd" prompt "the task to do..."')
Write-Host '  2) Open a new Claude Code session and paste it. (Claude runs sleep.ps1 on as its first step.)'
Write-Host '  3) Progress: the "live status" window that opens, or  sleep.cmd watch'
Write-Host 'NOTE: hooks take effect after restarting Claude Code (VS Code: reload the window).'
