# Before-compaction hook adapter (Claude Code). Its plain stdout becomes instructions for the compaction summary.
# It never blocks a compaction: any error says nothing and the summary is made as usual.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('claude')][string]$Harness)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SessionStart.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'HookIO.psm1')
$text=''
try{
    $event=Read-AgentOpsHookInput|ConvertFrom-Json
    $dir=[string]$event.cwd
    if($dir -and [IO.Directory]::Exists($dir)){$text=Get-AgentOpsCompactInstructions -ProjectPath $dir}
}catch{Write-AgentOpsHookNote "Agent Ops: las instrucciones para el resumen no pudieron prepararse ($($_.Exception.Message))."}
Write-AgentOpsHookOutput $text
exit 0
