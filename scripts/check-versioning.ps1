[CmdletBinding()]
param([string]$RepositoryPath=(Get-Location).Path,[string]$Base='',[string]$Head='HEAD')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Versioning.psm1') -Force
$result=Test-AgentOpsVersioning -RepositoryPath $RepositoryPath -Base $Base -Head $Head
$result|ConvertTo-Json -Depth 6
exit $result.Code
