# Turns `claude -p --output-format stream-json` output (one JSON object per line) into human-readable lines.
# Usage:  claude ... | format-stream.ps1
[CmdletBinding()]
param([Parameter(ValueFromPipeline = $true)][AllowEmptyString()][string]$Line)

begin {
  function Clip([string]$t, [int]$n) {
    $t = ($t -replace '\s+', ' ').Trim()
    if ($t.Length -gt $n) { return $t.Substring(0, $n) + '...' }
    return $t
  }
  function Ts { return (Get-Date -Format 'HH:mm:ss') }
  function ToolDesc($c) {
    $i = $c.input
    if ($c.name -eq 'Bash') { if ($i.description) { return [string]$i.description } else { return [string]$i.command } }
    if (($c.name -eq 'Agent') -or ($c.name -eq 'Task')) { if ($i.description) { return [string]$i.description } else { return [string]$i.prompt } }
    if ($i.file_path) { return [string]$i.file_path }
    if ($i.pattern) { return [string]$i.pattern }
    return ($i | ConvertTo-Json -Compress -Depth 3)
  }
}
process {
  if ([string]::IsNullOrWhiteSpace($Line)) { return }
  try { $e = $Line | ConvertFrom-Json } catch { Write-Output $Line; return }
  switch ($e.type) {
    'system' {
      if ($e.subtype -eq 'init') { Write-Output ('[' + (Ts) + '] > session resumed (' + ([string]$e.session_id).Substring(0, 8) + ')') }
    }
    'assistant' {
      foreach ($c in @($e.message.content)) {
        if ($c.type -eq 'text') { Write-Output ('[' + (Ts) + '] [message] ' + (Clip ([string]$c.text) 400)) }
        elseif ($c.type -eq 'tool_use') { Write-Output ('[' + (Ts) + '] [tool] ' + $c.name + ': ' + (Clip (ToolDesc $c) 140)) }
      }
    }
    'user' {
      foreach ($c in @($e.message.content)) {
        if ($c.type -eq 'tool_result') { Write-Output ('          -> ' + (Clip (($c.content | Out-String)) 110)) }
      }
    }
    'result' {
      Write-Output ('[' + (Ts) + '] [turn finished] (' + $e.subtype + ') ' + (Clip ([string]$e.result) 300))
    }
  }
}
