[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ConfigPath,[Parameter(Mandatory=$true)][string]$CandidateSha,[Parameter(Mandatory=$true)][string]$SessionId)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'UpdateCoordinator.psm1') -Force
$r=Invoke-AgentOpsUpdate -ConfigPath $ConfigPath -Action Prepare -CandidateSha $CandidateSha -SessionId $SessionId -Worker
$r|ConvertTo-Json -Depth 20
exit $r.Code
