# Compatibility entry point. Configure paths using manage-skills-watcher.ps1.
[CmdletBinding()]
param([string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'),[int]$RunSeconds=0)
& (Join-Path $PSScriptRoot '../../scripts/watch-skills.ps1') -ConfigPath $ConfigPath -RunSeconds $RunSeconds
exit $LASTEXITCODE
