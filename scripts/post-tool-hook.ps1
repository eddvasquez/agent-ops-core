# After-action hook adapter: records the action in the project's activity log and answers each harness in its format
# (Antigravity expects {}; Claude Code and Codex run it in the background and expect nothing). Never fails the action.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('claude','codex','antigravity')][string]$Harness)
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($false)
try{
    Import-Module (Join-Path $PSScriptRoot 'ActivityLog.psm1') -Force
    $file=$env:AGENT_OPS_HOOK_INPUT_FILE
    $json=$(if($file -and [IO.File]::Exists($file)){$utf8.GetString([IO.File]::ReadAllBytes($file))}else{$b=New-Object IO.MemoryStream;[Console]::OpenStandardInput().CopyTo($b);$utf8.GetString($b.ToArray())})
    $state=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'})
    Add-AgentOpsActivity -StateDir $state -Harness $Harness -Event $json
}catch{}
if($Harness -eq 'antigravity'){$o=[Console]::OpenStandardOutput();$bytes=$utf8.GetBytes('{}');$o.Write($bytes,0,$bytes.Length);$o.Flush()}
exit 0
