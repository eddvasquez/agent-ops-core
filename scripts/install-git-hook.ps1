# Installs the Agent Ops pre-commit review in a project's Git hooks folder (idempotent; never replaces another tool's hook).
[CmdletBinding(SupportsShouldProcess=$true)]
param([string]$ProjectPath=(Get-Location).Path)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PreCommitCheck.psm1') -Force
$r=Install-AgentOpsGitHook -ProjectPath $ProjectPath -WhatIf:$WhatIfPreference
$r|ConvertTo-Json -Depth 5
exit $r.Code
