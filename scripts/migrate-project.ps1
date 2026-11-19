[CmdletBinding(SupportsShouldProcess=$true)]
param([Parameter(Mandatory=$true)][string]$ProjectPath,
      [string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'),
      [ValidateSet('Plan','Apply','Rollback','Defer')][string]$Mode='Plan',[string[]]$ImportSources=@(),
      [string]$AgentsCandidatePath='',[string]$ExpectedAgentsHash='',[string]$ApprovedRemovalsPath='',
      [string]$Journal='',[switch]$Commit)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ProjectMigration.psm1') -Force
$r=Invoke-ProjectMigration -ProjectPath $ProjectPath -ConfigPath $ConfigPath -Mode $Mode -ImportSources $ImportSources -AgentsCandidatePath $AgentsCandidatePath -ExpectedAgentsHash $ExpectedAgentsHash -ApprovedRemovalsPath $ApprovedRemovalsPath -Journal $Journal -Commit:$Commit -WhatIf:$WhatIfPreference
$r|ConvertTo-Json -Depth 20
exit $r.Code
