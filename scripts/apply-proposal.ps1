# Governed learning apply CLI (applies approved blocks from a validated proposal, bumps SemVer and changelog).
[CmdletBinding()]
param([string]$HubPath='',[Parameter(Mandatory=$true)][string]$Path,[int[]]$ApprovedBlocks=@(),
      [switch]$Reject,[string]$Reason='',[string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'LearningProposals.psm1') -Force
if(-not $HubPath){
    if(-not [IO.File]::Exists($ConfigPath)){throw "No HubPath given and no installation configuration at $ConfigPath."}
    $HubPath=(Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json).HubDir
}
$r=Invoke-LearningProposalApply -HubPath $HubPath -Path $Path -ApprovedBlocks $ApprovedBlocks -Reject:$Reject -Reason $Reason
$r|ConvertTo-Json -Depth 6
exit $r.Code