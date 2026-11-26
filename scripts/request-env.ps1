# Safe .env credential request CLI (Prepare / Check). Never prints secret values.
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Prepare','Check')][string]$Action,
      [string]$ProjectPath=(Get-Location).Path,
      [Parameter(Mandatory)][string[]]$Keys)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'EnvRequest.psm1') -Force
$r=$(switch($Action){
    'Prepare'{New-AgentOpsEnvRequest -ProjectPath $ProjectPath -Keys $Keys}
    'Check'{Test-AgentOpsEnvKeys -ProjectPath $ProjectPath -Keys $Keys}
})
$r|ConvertTo-Json -Depth 5
exit $r.Code