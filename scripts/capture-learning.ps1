# Captures a learning candidate in the hub inbox (proposals/inbox). Never modifies a skill.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Signal,[Parameter(Mandatory=$true)][string]$Project,
      [Parameter(Mandatory=$true)][string]$Harness,[Parameter(Mandatory=$true)][string]$Summary,
      [Parameter(Mandatory=$true)][string]$Evidence,[string]$Skill='',[string]$HubPath='',
      [string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'LearningProposals.psm1') -Force
if(-not $HubPath){
    if(-not [IO.File]::Exists($ConfigPath)){throw "No HubPath given and no installation configuration at $ConfigPath."}
    $HubPath=(Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json).HubDir
}$r=New-LearningCandidate -HubPath $HubPath -Signal $Signal -Project $Project -Harness $Harness -Summary $Summary -Evidence $Evidence -Skill $Skill
$r|ConvertTo-Json -Depth 6
exit $r.Code