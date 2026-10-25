# sleep (Windows) uninstaller. Double-click uninstall.bat, or run:
#   powershell -NoProfile -ExecutionPolicy Bypass -File uninstall.ps1 [-KeepData]
#   - stops running sleep/wake jobs, the wake task and the keep-awake process
#   - removes the sleep hooks from settings.json (backed up first)
#   - deletes %USERPROFILE%\.claude\sleep\ (-KeepData: leaves the log/progress files)
param([switch]$KeepData)
try { [Console]::OutputEncoding = (New-Object System.Text.UTF8Encoding($false)) } catch {}
if ($env:SLEEP_HOME) { $dest = $env:SLEEP_HOME } else { $dest = Join-Path $env:USERPROFILE '.claude\sleep' }
if ($env:SLEEP_SETTINGS) { $settingsPath = $env:SLEEP_SETTINGS } else { $settingsPath = Join-Path $env:USERPROFILE '.claude\settings.json' }
# Safety guard: only ever install into / delete a folder that is literally named "sleep" (never the user profile, a drive root or a relative path)
$refuseDest = $true   # fail closed: any doubt or error below leaves this at $true
try {
  $destT = ([string]$dest).TrimEnd('\', '/')
  $destLeaf = ($destT -split '[\\/]')[-1]
  $refuseDest = ([string]::IsNullOrEmpty($destT) -or (-not [System.IO.Path]::IsPathRooted([string]$dest)) -or ($destLeaf -ne 'sleep') -or ($destT -ieq ([string]$env:USERPROFILE).TrimEnd('\', '/')))
} catch { $refuseDest = $true }
if ($refuseDest) { Write-Host "Refusing: the install folder must be an absolute path named 'sleep' ($dest)"; exit 1 }
function Save-Settings([string]$path, [string]$json) {
  # atomic write (temp file, then replace); a linked settings.json is written in place instead
  $enc = New-Object System.Text.UTF8Encoding($false)
  $item = Get-Item -Path $path -ErrorAction SilentlyContinue
  if ($item -and $item.LinkType) { [System.IO.File]::WriteAllText($path, $json, $enc); return }
  $tmp = $path + '.sleep-tmp'
  [System.IO.File]::WriteAllText($tmp, $json, $enc)
  Move-Item -Path $tmp -Destination $path -Force
}
$destFwd0 = $dest.Replace('\', '/')

Write-Host '1/4 stopping running jobs'
foreach ($d in @($dest)) {
  if (-not (Test-Path $d)) { continue }
  New-Item -ItemType File -Path (Join-Path $d 'CANCEL') -Force | Out-Null
  foreach ($pf in @('sleeper.pid', 'keepawake.pid', 'darkguard.pid')) {
    $f = Join-Path $d $pf
    if (Test-Path $f) {
      try {
        $id = [int](Get-Content $f | Select-Object -First 1)
        $pr = Get-Process -Id $id -ErrorAction SilentlyContinue
        if ($pr -and ($pr.ProcessName -match 'powershell|pwsh')) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
      } catch {}
    }
  }
}
# leftover watch/final-sleep processes
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe' OR Name = 'pwsh.exe'" -ErrorAction SilentlyContinue |
  Where-Object { $_.CommandLine -match 'claude[\\/]sleep[\\/](watch|final-sleep|sleep-and-resume|keepawake|dark-guard)\.ps1' -and $_.ProcessId -ne $PID } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
foreach ($t in @('ClaudeSleepWake')) { Unregister-ScheduledTask -TaskName $t -Confirm:$false -ErrorAction SilentlyContinue }

Write-Host '2/4 cleaning the hooks in settings.json'
try {
$ErrorActionPreference = 'Stop'
if (Test-Path $settingsPath) {
  Copy-Item -Path $settingsPath -Destination ($settingsPath + '.sleep-backup-' + (Get-Date -Format 'yyyyMMdd-HHmmss')) -Force
  Get-ChildItem -Path (Split-Path -Parent $settingsPath) -Filter ((Split-Path -Leaf $settingsPath) + '.sleep-backup-*') -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -Skip 3 | Remove-Item -Force -ErrorAction SilentlyContinue
  $raw = Get-Content -Path $settingsPath -Raw -Encoding UTF8
  if (-not [string]::IsNullOrWhiteSpace($raw)) {
    $s = $raw | ConvertFrom-Json
    $removed = 0
    if ($s.PSObject.Properties['hooks']) {
      $hooks = $s.hooks
      foreach ($ev in @($hooks.PSObject.Properties.Name)) {
        $newGroups = @()
        foreach ($g in @($hooks.$ev)) {
          $all = @($g.hooks)
          $keep = @($all | Where-Object { -not ((([string]$_.command).Replace('\', '/') -like ('*' + $destFwd0 + '/hook-*')) -or ([string]$_.command -match '[\\/]\.claude[\\/]sleep[\\/]hook-')) })
          $removed += ($all.Count - $keep.Count)
          if ($keep.Count -gt 0) { $g.hooks = $keep; $newGroups += $g }
        }
        if ($newGroups.Count -gt 0) { $hooks.$ev = $newGroups } else { $hooks.PSObject.Properties.Remove($ev) }
      }
      if (@($hooks.PSObject.Properties).Count -eq 0) { $s.PSObject.Properties.Remove('hooks') }
    }
    # permission rules added by the installer
    if ($s.PSObject.Properties['permissions'] -and $s.permissions.PSObject.Properties['allow']) {
      $before = @($s.permissions.allow).Count
      $rules = @(@($s.permissions.allow) | Where-Object { (([string]$_).Replace('\', '/') -notlike ('*' + $destFwd0 + '/sleep.ps1*')) -and (([string]$_) -notmatch '[\\/]\.claude[\\/]sleep[\\/]sleep\.ps1') })
      $removed += ($before - $rules.Count)
      if ($rules.Count -gt 0) { $s.permissions.allow = $rules } else { $s.permissions.PSObject.Properties.Remove('allow') }
      if (@($s.permissions.PSObject.Properties).Count -eq 0) { $s.PSObject.Properties.Remove('permissions') }
    }
    Save-Settings $settingsPath ($s | ConvertTo-Json -Depth 30)
    Write-Host "   $removed hook(s)/permission rule(s) removed."
  }
}
} catch {
  Write-Host ('   Could not clean settings.json: ' + $_.Exception.Message)
  Write-Host '   Nothing was deleted, so the hooks keep working. Fix settings.json (or remove the sleep hooks by hand) and run this uninstaller again.'
  exit 1
} finally {
  $ErrorActionPreference = 'Continue'
}

Write-Host '3/4 deleting files'
if (Test-Path $dest) {
  if ($KeepData) {
    Get-ChildItem -Path $dest -File | Where-Object { $_.Extension -in @('.ps1', '.cmd', '.md') -and $_.Name -ne 'progress.md' } | Remove-Item -Force -ErrorAction SilentlyContinue
    Write-Host "   -KeepData: log/progress files left in place ($dest)"
  } else {
    Remove-Item -Path $dest -Recurse -Force -ErrorAction SilentlyContinue
  }
}

Write-Host '4/4 wake task'
Write-Host '   ClaudeSleepWake task (if any) removed.'
Write-Host 'Removed. (Reload Claude Code / VS Code.)'
