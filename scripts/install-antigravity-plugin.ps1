# Installs (or with -Uninstall removes) the Agent Ops Core plugin for Antigravity in ~/.gemini/config/plugins.
# It replaces the framework's loose entries in ~/.gemini/config/hooks.json only after the plugin validated.
[CmdletBinding()]
param([switch]$Uninstall)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'AntigravityPlugin.psm1') -Force
$r=Install-AgentOpsAntigravityPlugin -Uninstall:$Uninstall
$r|ConvertTo-Json -Depth 4
exit $r.Code
