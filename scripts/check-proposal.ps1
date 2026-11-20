# Validates a learning proposal (ficha) before it is presented for a human decision.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Path,[string]$HubPath='',
      [string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'LearningProposals.psm1') -Force
if(-not $HubPath){
    if(-not [IO.File]::Exists($ConfigPath)){throw "No HubPath given and no installation configuration at $ConfigPath."}
    $HubPath=(Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json).HubDir
}$r=Test-LearningProposal -Path $Path -HubPath $HubPath
$r|ConvertTo-Json -Depth 6
exit $r.Code