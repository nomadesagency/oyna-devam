# Keeps the computer from going idle-to-sleep while the task runs (12 hours at most). Runs hidden; stopped by `sleep.ps1 off`.
param([switch]$Display)   # -Display: also keep the display on ("working" profile)
Add-Type -Namespace SleepTool -Name Awake -MemberDefinition '[DllImport("kernel32.dll")] public static extern uint SetThreadExecutionState(uint esFlags);'
$ES_CONTINUOUS = [uint32]2147483648
$ES_SYSTEM_REQUIRED = [uint32]1
$ES_DISPLAY_REQUIRED = [uint32]2
$flags = $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED
if ($Display) { $flags = $flags -bor $ES_DISPLAY_REQUIRED }
$end = (Get-Date).AddHours(12)
while ((Get-Date) -lt $end) {
  [void][SleepTool.Awake]::SetThreadExecutionState($flags)
  Start-Sleep -Seconds 30
}
[void][SleepTool.Awake]::SetThreadExecutionState($ES_CONTINUOUS)
