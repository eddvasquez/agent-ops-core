# Project hygiene sensor entry point (read-only, JSON for the assistant). Findings are not errors: code 0.
[CmdletBinding()]
param([string]$ProjectPath=(Get-Location).Path,[string]$HubDir='')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'ProjectHygiene.psm1') -Force
$r=Get-AgentOpsProjectHygiene -ProjectPath $ProjectPath -HubDir $HubDir
$r|ConvertTo-Json -Depth 5
exit $r.Code
