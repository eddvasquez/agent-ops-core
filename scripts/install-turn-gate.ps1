# Installs the end-of-turn check for Claude Code, Codex and Antigravity (pilot: framework repository only).
[CmdletBinding()]
param([string]$ProjectPath=(Get-Location).Path)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'TurnGate.psm1') -Force
$r=Install-AgentOpsTurnGate -ProjectPath $ProjectPath
$r|ConvertTo-Json -Depth 5
exit $r.Code
