# Reads the 5-hour limit percentage and reset time from `claude -p "/usage"` and writes them to state.json.
# Testing: SLEEP_USAGE_FIXTURE=file | SLEEP_USAGE_TIMEOUT=seconds (how long to wait for /usage, default 60)
. (Join-Path $PSScriptRoot 'common.ps1')

# One refresh at a time (a stale lock is cleared after 2 minutes)
$lock = Join-Path $U 'refresh.lock'
if (Test-Path $lock) {
  if (((Get-Date) - (Get-Item $lock).LastWriteTime).TotalMinutes -lt 2) { exit 0 }
  Remove-Item $lock -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $lock -Force | Out-Null

try {
  $out = ''
  if ($env:SLEEP_USAGE_FIXTURE) {
    $out = Get-Content -Raw -Encoding UTF8 -Path $env:SLEEP_USAGE_FIXTURE
  } else {
    $bin = Get-ClaudeBin
    if (-not $bin) { Write-Log 'usage-refresh: claude binary not found'; exit 1 }
    $tmp = Join-Path $U ('usage.out.' + $PID)
    $p = Start-Process -FilePath $bin -ArgumentList @('-p', '/usage') -WorkingDirectory $env:TEMP -NoNewWindow -PassThru -RedirectStandardOutput $tmp -RedirectStandardError ($tmp + '.err')
    $tmoSecs = 60
    if ($env:SLEEP_USAGE_TIMEOUT) { $tmoSecs = [int]$env:SLEEP_USAGE_TIMEOUT }
    if (-not $p.WaitForExit($tmoSecs * 1000)) { try { $p.Kill() } catch {} }
    if (Test-Path $tmp) { $out = Get-Content -Raw -Encoding UTF8 -Path $tmp }
    Remove-Item $tmp, ($tmp + '.err') -Force -ErrorAction SilentlyContinue
  }

  $line = ($out -split "`r?`n" | Where-Object { $_ -match '^Current session:' } | Select-Object -First 1)
  if (-not $line) { Write-Log "usage-refresh: 'Current session' line not found"; exit 1 }
  if ($line -notmatch '^Current session:\s+([0-9.]+)%\s+used') { Write-Log ("usage-refresh: could not parse percentage: " + $line); exit 1 }
  $pct = [double]::Parse($Matches[1], [System.Globalization.CultureInfo]::InvariantCulture)

  # Reset-time formats understood (case-insensitive, time zone in parentheses optional):
  #   "resets Oct 26 at 3:59am (Europe/London)" | "resets 3:59am (Europe/London)" (today, or tomorrow if past) | "resets 15:59"
  # If it cannot be parsed or is not plausible for a 5-hour window, a SAFE ESTIMATE (now + 5 h, the latest possible reset)
  # is stored with resets_estimated = true: the system still triggers at the threshold, it just wakes at the latest possible moment.
  $resets = [int64]0
  $rx = '(?i)resets\s+(?:(?<mon>[a-z]{3})[a-z]*\.?\s+(?<day>\d{1,2})(?:st|nd|rd|th)?,?\s*(?:at\s+)?|(?:at\s+)?)(?<h>\d{1,2})(?::(?<mi>\d{2}))?\s*(?<ap>[ap]m)?\b(?:\s*\((?<tz>[^)]*)\))?'
  $m = [regex]::Match($line, $rx)
  if ($m.Success -and ($m.Groups['ap'].Success -or $m.Groups['mi'].Success)) {
    try {
      $h = [int]$m.Groups['h'].Value
      $mi = 0
      if ($m.Groups['mi'].Success) { $mi = [int]$m.Groups['mi'].Value }
      $ap = $m.Groups['ap'].Value.ToLower()
      if (($ap -eq 'pm') -and ($h -lt 12)) { $h += 12 }
      if (($ap -eq 'am') -and ($h -eq 12)) { $h = 0 }
      # time zone named in the line (IANA names work on PowerShell 7; on 5.1 the lookup fails and this computer's zone is used)
      $tzi = [TimeZoneInfo]::Local
      if ($m.Groups['tz'].Success -and $m.Groups['tz'].Value.Trim()) {
        try { $tzi = [TimeZoneInfo]::FindSystemTimeZoneById($m.Groups['tz'].Value.Trim()) } catch { $tzi = [TimeZoneInfo]::Local }
      }
      $nowOff = [DateTimeOffset]::UtcNow
      $nowTz = [TimeZoneInfo]::ConvertTime($nowOff, $tzi)
      if ($m.Groups['mon'].Success) {
        $monthNum = [array]::IndexOf(@('jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'), $m.Groups['mon'].Value.ToLower()) + 1
        if ($monthNum -lt 1) { throw 'month' }
        $dt = New-Object -TypeName DateTime -ArgumentList $nowTz.Year, $monthNum, ([int]$m.Groups['day'].Value), $h, $mi, 0
        $cand = New-Object -TypeName DateTimeOffset -ArgumentList $dt, $tzi.GetUtcOffset($dt)
        if ($cand -lt $nowOff.AddDays(-1)) {   # year rollover (e.g. Dec -> Jan)
          $dt = $dt.AddYears(1)
          $cand = New-Object -TypeName DateTimeOffset -ArgumentList $dt, $tzi.GetUtcOffset($dt)
        }
      } else {
        $dt = New-Object -TypeName DateTime -ArgumentList $nowTz.Year, $nowTz.Month, $nowTz.Day, $h, $mi, 0
        $cand = New-Object -TypeName DateTimeOffset -ArgumentList $dt, $tzi.GetUtcOffset($dt)
        if ($cand -lt $nowOff) {
          $dt = $dt.AddDays(1)
          $cand = New-Object -TypeName DateTimeOffset -ArgumentList $dt, $tzi.GetUtcOffset($dt)
        }
      }
      $resets = [int64]$cand.ToUnixTimeSeconds()
    } catch { $resets = [int64]0 }
  }

  # Plausibility: a 5-hour window resets within the next 5 h (10 min slack) and is not in the past.
  $now = Now-Epoch
  $est = $false
  if (($resets -lt ($now - 300)) -or ($resets -gt ($now + 18600))) {
    Write-Log ("usage-refresh: WARNING reset time not understood (parsed=$resets), using safe estimate now+5h. Raw line: " + $line)
    $resets = $now + 18000
    $est = $true
  }

  $obj = [ordered]@{ five_hour_pct = $pct; resets_at = $resets; resets_estimated = $est; ts = $now }
  Write-Json ([pscustomobject]$obj) $STATE
  Write-Log ("usage-refresh: $pct% resets_at=$resets estimated=$est")
} finally {
  Remove-Item $lock -Recurse -Force -ErrorAction SilentlyContinue
}
