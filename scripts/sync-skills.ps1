[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$HubDir = (Join-Path $env:USERPROFILE '.agent-ops-hub'),
    [string[]]$Targets = @((Join-Path $env:USERPROFILE '.gemini/config/skills'), (Join-Path $env:USERPROFILE '.claude/skills'), (Join-Path $env:USERPROFILE '.agents/skills')),
    [string]$StateDir = (Join-Path $env:LOCALAPPDATA 'AgentOps'),
    [string]$FrameworkDir = '',
    [ValidateSet('Plan','Apply','Verify','Resolve','Prune','Restore')][string]$Mode = 'Plan',
    [string]$Key='', [string]$VersionHash='', [string[]]$SkillNames=@(), [switch]$Json
)
$ErrorActionPreference='Stop'
if(-not $PSBoundParameters.ContainsKey('FrameworkDir')){$FrameworkDir=Split-Path -Parent $PSScriptRoot}
$enginePath=Join-Path $PSScriptRoot 'SkillsSync.psm1'
if(-not $PSBoundParameters.ContainsKey('FrameworkDir') -and [IO.File]::Exists((Join-Path $StateDir 'update-state.json'))){
    Import-Module (Join-Path $PSScriptRoot 'UpdateCoordinator.psm1') -Force
    $FrameworkDir=(Get-AgentOpsActiveRelease -ConfigPath (Join-Path $StateDir 'watch-config.json')).Path
    $enginePath=Join-Path $FrameworkDir 'scripts/SkillsSync.psm1'
}
$syncEngine=Import-Module $enginePath -Force -PassThru
$invoke=@{HubDir=$HubDir; Targets=$Targets; StateDir=$StateDir; FrameworkDir=$FrameworkDir; Mode=$Mode; Key=$Key; VersionHash=$VersionHash; SkillNames=$SkillNames; WhatIf=[bool]$WhatIfPreference}
$result=& $syncEngine {param($p) Invoke-SkillSync @p} $invoke
if ($Json) { $result | ConvertTo-Json -Depth 30 }
else {
    Write-Host ("Skills: code={0}; copied={1}; removed={2}; conflicts={3}; pending deletions={4}" -f $result.Code,$result.Copied,$result.Removed,$result.Conflicts.Count,$result.Deletions.Count)
    $result | Format-List
}
exit $result.Code
