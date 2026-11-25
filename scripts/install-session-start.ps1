# Installs (or with -Uninstall removes) the session start notice for this user in Claude Code, Codex and Antigravity.
# It only speaks in projects governed by Agent Ops Core; other folders get nothing.
[CmdletBinding()]
param([switch]$Uninstall)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SessionStart.psm1') -Force
$r=Install-AgentOpsSessionStart -Uninstall:$Uninstall
$r|ConvertTo-Json -Depth 5
exit $r.Code
