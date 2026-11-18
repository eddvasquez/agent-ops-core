[CmdletBinding()]
param([string]$RepositoryPath='',[string]$Commit='HEAD')
$ErrorActionPreference='Stop'
if(-not $PSBoundParameters.ContainsKey('RepositoryPath')){$RepositoryPath=Split-Path -Parent $PSScriptRoot}
Import-Module (Join-Path $PSScriptRoot 'UpdateCoordinator.psm1') -Force
$r=Get-AgentOpsReleasePolicy -RepositoryPath $RepositoryPath -Commit $Commit
$r|ConvertTo-Json -Depth 10
exit $r.Code
