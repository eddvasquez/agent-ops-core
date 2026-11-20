# Reports pending learning candidates and proposals, and the active skill count against the ceiling.
[CmdletBinding()]
param([string]$HubPath='',[string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'LearningProposals.psm1') -Force
if(-not $HubPath){
    if(-not [IO.File]::Exists($ConfigPath)){throw "No HubPath given and no installation configuration at $ConfigPath."}
    $HubPath=(Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json).HubDir
}$r=Get-LearningQueue -HubPath $HubPath
$r|ConvertTo-Json -Depth 6
exit $r.Code