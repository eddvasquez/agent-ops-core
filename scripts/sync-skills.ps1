[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$HubDir = (Join-Path $env:USERPROFILE '.agent-ops-hub'),
    [string[]]$Targets = @((Join-Path $env:USERPROFILE '.gemini/config/skills'), (Join-Path $env:USERPROFILE '.claude/skills'), (Join-Path $env:USERPROFILE '.agents/skills')),
    [string]$StateDir = (Join-Path $env:LOCALAPPDATA 'AgentOps'),
    [string]$FrameworkDir = (Split-Path -Parent $PSScriptRoot),
    [ValidateSet('Plan','Apply','Verify','Resolve','Prune','Restore')][string]$Mode = 'Plan',
    [string]$Key='', [string]$VersionHash='', [string[]]$SkillNames=@(), [switch]$Json
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SkillsSync.psm1') -Force
$invoke=@{HubDir=$HubDir; Targets=$Targets; StateDir=$StateDir; FrameworkDir=$FrameworkDir; Mode=$Mode; Key=$Key; VersionHash=$VersionHash; SkillNames=$SkillNames; WhatIf=[bool]$WhatIfPreference}
$result=Invoke-SkillSync @invoke
if ($Json) { $result | ConvertTo-Json -Depth 30 }
else {
    Write-Host ("Skills: code={0}; copied={1}; removed={2}; conflicts={3}; pending deletions={4}" -f $result.Code,$result.Copied,$result.Removed,$result.Conflicts.Count,$result.Deletions.Count)
    $result | Format-List
}
exit $result.Code
