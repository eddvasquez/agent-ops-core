[CmdletBinding()]
param([string]$RulesPath=(Join-Path (Get-Location).Path '.context/reglas_proyecto.md'),
      [Parameter(Mandatory=$true)][string[]]$Path,
      [string]$Scope='',
      [string]$ReviewOut='',
      [string]$ReviewVerdictPath='')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'RulesCheck.psm1') -Force
$result=Test-AgentOpsRules -RulesPath $RulesPath -Path $Path -Scope $Scope -ReviewOut $ReviewOut -ReviewVerdictPath $ReviewVerdictPath
$result|ConvertTo-Json -Depth 6
exit $result.Code
