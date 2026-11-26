# Pre-deploy WSTG-CONF-03 audit CLI (read-only). Returns JSON and exit code 0 (CLEAN) or 1 (BLOCKED/FAILED).
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Path)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'DeployAudit.psm1') -Force
$r=Test-AgentOpsDeploySurface -Path $Path
$r|ConvertTo-Json -Depth 6
exit $r.Code