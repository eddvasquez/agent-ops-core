# Installs (or with -Uninstall removes) the credential guard for this user in Claude Code, Codex and Antigravity.
[CmdletBinding()]
param([switch]$Uninstall)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SecretGuard.psm1') -Force
$r=Install-AgentOpsSecretGuard -Uninstall:$Uninstall
$r|ConvertTo-Json -Depth 5
exit $r.Code
