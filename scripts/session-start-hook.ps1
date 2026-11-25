# Session start hook adapter. Reads the harness's SessionStart event, builds the brief for a project governed
# by Agent Ops Core and answers in that harness's own format. Any error says nothing: the session starts as
# before and AGENTS.md still asks for MODO ENTRADA (the floor).
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('claude','codex','antigravity')][string]$Harness)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SessionStart.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'HookIO.psm1')
$brief=''
try{
    $event=Read-AgentOpsHookInput|ConvertFrom-Json
    if($Harness -eq 'antigravity'){$dir=[string](@($event.workspacePaths)[0]);$source='startup'}
    else{$dir=[string]$event.cwd;$source=$(if($event.PSObject.Properties['source'] -and @('startup','resume','clear','compact','fork') -contains [string]$event.source){[string]$event.source}else{'startup'})}
    if($dir -and [IO.Directory]::Exists($dir)){$brief=Get-AgentOpsSessionBrief -ProjectPath $dir -Source $source}
    # The skills watcher must not stay off unnoticed: repair it at every session start (silent unless something happened).
    try{Import-Module (Join-Path $PSScriptRoot 'WatcherGuard.psm1') -Force;$w=Repair-AgentOpsWatcher;if($w.Message -and $brief){$brief+="`n- $($w.Message)"}}catch{}
}catch{Write-AgentOpsHookNote "Agent Ops: el aviso de inicio de sesión no pudo prepararse ($($_.Exception.Message)); sigue AGENTS.md."}
Write-AgentOpsHookOutput (ConvertTo-AgentOpsSessionStartOutput $Harness $brief)
exit 0
