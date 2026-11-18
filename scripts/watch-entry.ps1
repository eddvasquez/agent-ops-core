# Task action stays in the bootstrap; the runtime version is selected at startup.
[CmdletBinding()]
param([string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'),[int]$RunSeconds=0)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'UpdateCoordinator.psm1') -Force
$release=Get-AgentOpsActiveRelease -ConfigPath $ConfigPath -ForWatcher
& (Join-Path $release.Path 'scripts/watch-skills.ps1') -ConfigPath $ConfigPath -RunSeconds $RunSeconds -ReleaseSha $release.Sha
exit $LASTEXITCODE
