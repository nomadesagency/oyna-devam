# Dark guard (only for `sleep.ps1 on -Profile away`): while the task is not finished, the display may stay on for at most
# SLEEP_DARK_SECS (default 120) seconds after the user wakes it (e.g. to check progress); then it is turned off again.
# Windows has no simple "is the display on" query, so user input (mouse/keyboard) is used as the signal that the display woke up.
# Started by `sleep.ps1 on -Profile away`, stopped by `sleep.ps1 off` (or when the system is no longer active). Runs hidden.
# Testing: SLEEP_FAKE_IDLE=file (contains the idle seconds), SLEEP_DRY=1 (the monitor is not switched off).
. (Join-Path $PSScriptRoot 'common.ps1')
Add-Type -ErrorAction SilentlyContinue -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SleepIdle {
  [StructLayout(LayoutKind.Sequential)] struct LASTINPUTINFO { public uint cbSize; public uint dwTime; }
  [DllImport("user32.dll")] static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
  public static double IdleSeconds() {
    LASTINPUTINFO li = new LASTINPUTINFO(); li.cbSize = (uint)Marshal.SizeOf(li);
    if (!GetLastInputInfo(ref li)) return 9999;
    return (double)((uint)Environment.TickCount - li.dwTime) / 1000.0;
  }
}
'@
$limit = 120; if ($env:SLEEP_DARK_SECS) { $limit = [int]$env:SLEEP_DARK_SECS }
$poll = 5;   if ($env:SLEEP_DARK_POLL) { $poll = [int]$env:SLEEP_DARK_POLL }

function Get-Idle {
  if ($env:SLEEP_FAKE_IDLE) { try { return [double](Get-Content $env:SLEEP_FAKE_IDLE -ErrorAction Stop | Select-Object -First 1) } catch { return 9999 } }
  return [SleepIdle]::IdleSeconds()
}

$awakeSince = $null
$last = Get-Date
Write-Log "dark guard started (display may stay on at most ${limit}s)"
while ((Test-Active) -and -not (Test-Path $DONE)) {
  $now = Get-Date
  # a big gap means the computer was asleep (the wake lights the display): count from now
  if (($now - $last).TotalSeconds -gt ($poll * 4)) { $awakeSince = $now; Write-Log "dark guard: computer woke up, display will be turned off in ${limit}s" }
  $last = $now
  # user input within the last poll interval = the display is (or just was) turned on by the user
  if ((Get-Idle) -le ($poll + 1) -and $null -eq $awakeSince) { $awakeSince = $now; Write-Log "dark guard: display woke up, will turn it off again in ${limit}s" }
  if ($null -ne $awakeSince -and ($now - $awakeSince).TotalSeconds -ge $limit) {
    if ($env:SLEEP_DRY -eq '1') { Write-Log 'DRY: monitor off not called (dark guard)' } else { Set-MonitorOff }
    Write-Log "dark guard: display turned off again after ${limit}s"
    $awakeSince = $null
    Start-Sleep -Seconds ($poll + 2)   # let the display actually switch off before listening for input again
    $last = Get-Date                   # this pause is not a computer sleep
  }
  Start-Sleep -Seconds $poll
}
Write-Log 'dark guard stopped'
