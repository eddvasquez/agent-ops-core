# Audits hub + core skills for YAML health, listing budget, body length, and Jaccard + containment overlaps.
[CmdletBinding()]
param([string]$HubPath='',[string]$FrameworkPath='',[int]$DescriptionLimit=300,[int]$OfficialLimit=1024,
      [int]$MaxBodyLines=500,[int]$ListingBudget=6000,[double]$JaccardThreshold=0.45,[double]$ContainmentThreshold=0.70,
      [switch]$Strict,[string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'LearningProposals.psm1') -Force
if(-not $HubPath -and [IO.File]::Exists($ConfigPath)){
    $cfg=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
    if($cfg.PSObject.Properties['HubDir'] -and $cfg.HubDir){$HubPath=[string]$cfg.HubDir}
    if(-not $FrameworkPath -and $cfg.PSObject.Properties['FrameworkDir'] -and $cfg.FrameworkDir){$FrameworkPath=[string]$cfg.FrameworkDir}
}
$r=Test-SkillCatalog -HubPath $HubPath -FrameworkPath $FrameworkPath -DescriptionLimit $DescriptionLimit -OfficialLimit $OfficialLimit -MaxBodyLines $MaxBodyLines -ListingBudget $ListingBudget -JaccardThreshold $JaccardThreshold -ContainmentThreshold $ContainmentThreshold -Strict:$Strict
$r|ConvertTo-Json -Depth 6
exit $r.Code