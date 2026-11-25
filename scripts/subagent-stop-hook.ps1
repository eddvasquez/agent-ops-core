# Subagent stop hook (Claude Code). A reviewer subagent that edited the deliverable or passed items without citing
# is sent back once per stop (stop_hook_active prevents loops). Any error lets the subagent stop.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('claude')][string]$Harness)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'HookIO.psm1')
try{
    $event=Read-AgentOpsHookInput|ConvertFrom-Json
    if(-not ($event.PSObject.Properties['stop_hook_active'] -and $event.stop_hook_active) -and $event.cwd -and [IO.Directory]::Exists([string]$event.cwd)){
        Import-Module (Join-Path $PSScriptRoot 'Acceptance.psm1') -Force
        $v=Test-AgentOpsReviewerStop -ProjectPath ([string]$event.cwd)
        if($v.Decision -eq 'BLOCK'){Write-AgentOpsHookOutput ([ordered]@{decision='block';reason=$v.Reason}|ConvertTo-Json -Compress);exit 0}
    }
}catch{Write-AgentOpsHookNote "Agent Ops: la comprobación del subagente no pudo ejecutarse ($($_.Exception.Message))."}
exit 0
