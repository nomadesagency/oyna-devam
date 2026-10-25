# Live status board. Leave it open in a PowerShell window; when the computer sleeps and wakes it simply continues.
# Usage: sleep.ps1 watch    (quitting with Ctrl-C does NOT affect the task)
param([int]$Interval = 3)
. (Join-Path $PSScriptRoot 'common.ps1')

function Fmt-Dur([int64]$s) {
  if ($s -lt 0) { $s = 0 }
  return ('{0}h {1:00}m {2:00}s' -f [math]::Floor($s / 3600), [math]::Floor(($s % 3600) / 60), ($s % 60))
}
function Tail-File([string]$path, [int]$n) {
  if (Test-Path $path) { return @(Get-Content -Path $path -Tail $n -Encoding UTF8) }
  return @()
}

while ($true) {
  Clear-Host
  $now = Now-Epoch
  Write-Host ('SLEEP — live status        ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '        (Ctrl-C quits; the task is not affected)')
  Write-Host ('-' * 78)
  $a = Get-Active
  if ($a) {
    $sess = '(not bound)'
    if ($a.session) { $sess = ([string]$a.session).Substring(0, [math]::Min(8, ([string]$a.session).Length)) }
    Write-Host ('System   : ON  | project: ' + $a.project)
    $pf = 'away'; if ($a.profile) { $pf = [string]$a.profile }
    if ($pf -eq 'working') { Write-Host 'Profile  : working (computer stays awake, display on)' } else { Write-Host 'Profile  : away (display dark, computer sleeps at the limit and at the end)' }
    Write-Host ('Settings : threshold ' + $a.threshold + '% | permission mode: ' + $a.mode + ' | resume: ' + $a.resume + ' | session: ' + $sess)
  } else {
    Write-Host 'System   : OFF'
  }
  $s = Read-Json $STATE
  if ($s) {
    $r = [int64]$s.resets_at
    if ($r -gt $now) {
      $rt = [DateTimeOffset]::FromUnixTimeSeconds($r).LocalDateTime.ToString('HH:mm')
      if ($s.resets_estimated -eq $true) { $rt = $rt + ' (estimate: latest possible)' }
      Write-Host ('Limit    : ' + $s.five_hour_pct + '% (data ' + (Fmt-Dur ($now - [int64]$s.ts)) + ' old) | resets at: ' + $rt + ' (in ' + (Fmt-Dur ($r - $now)) + ')')
    } else {
      Write-Host ('Limit    : window has reset (last reading ' + $s.five_hour_pct + '%)')
    }
  } else {
    Write-Host 'Limit    : (no data yet)'
  }
  if (Test-Path $DONE) { Write-Host 'Flag     : DONE (task marked finished)' }
  if (Test-Path $BLOCKED) { Write-Host ('Flag     : BLOCKED — ' + (Get-Content $BLOCKED -Raw).Trim()) }
  $sp = Join-Path $U 'sleeper.pid'
  $sleeping = $false
  if (Test-Path $sp) { $sid = [int](Get-Content $sp | Select-Object -First 1); if (Get-Process -Id $sid -ErrorAction SilentlyContinue) { $sleeping = $true } }
  if ($sleeping) {
    $nw = [int64](Get-Content (Join-Path $U 'next-wake.epoch') -ErrorAction SilentlyContinue | Select-Object -First 1)
    $nwt = [DateTimeOffset]::FromUnixTimeSeconds($nw).LocalDateTime.ToString('HH:mm:ss')
    Write-Host ('Sleep    : sleep/wake job WAITING — resumes at: ' + $nwt + ' (in ' + (Fmt-Dur ($nw - $now)) + ')')
  } else {
    Write-Host 'Sleep    : no sleep pending'
  }
  Write-Host ''
  Write-Host '--- progress.md (last 10 lines) ---'
  Tail-File $PROGRESS 10 | ForEach-Object { if ($_.Length -gt 150) { $_.Substring(0, 150) } else { $_ } }
  Write-Host ''
  Write-Host '--- event log (last 8) ---'
  Tail-File $LOG 8 | ForEach-Object { if ($_.Length -gt 150) { $_.Substring(0, 150) } else { $_ } }
  $raw = Join-Path $U 'resume-raw.log'
  if (Test-Path $raw) {
    Write-Host ''
    Write-Host '--- latest session output (live stream) ---'
    $lines = @(Tail-File $raw 60 | & (Join-Path $U 'format-stream.ps1'))
    $lines | Select-Object -Last 8 | ForEach-Object { if ($_.Length -gt 160) { $_.Substring(0, 160) } else { $_ } }
  }
  Start-Sleep -Seconds $Interval
}
