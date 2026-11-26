# Evaluates skill pruning candidates (90-day inactivity and repeated hurt/error outcomes) without deleting files.
[CmdletBinding()]
param([string]$HubPath='',[string]$FrameworkPath='',[string]$UsagePath='',[int]$InactiveDays=90,[int]$HurtThreshold=2,
      [switch]$EmitProposals,[switch]$SyncFirst,[string]$ProjectPath='',
      [string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'LearningProposals.psm1') -Force
if(-not $HubPath -and [IO.File]::Exists($ConfigPath)){
    $cfg=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
    if($cfg.PSObject.Properties['HubDir'] -and $cfg.HubDir){$HubPath=[string]$cfg.HubDir}
    if(-not $FrameworkPath -and $cfg.PSObject.Properties['FrameworkDir'] -and $cfg.FrameworkDir){$FrameworkPath=[string]$cfg.FrameworkDir}
}
if($SyncFirst){Sync-SkillUsageFromTranscripts -HubPath $HubPath -FrameworkPath $FrameworkPath -ProjectPath $ProjectPath -UsagePath $UsagePath|Out-Null}
$r=Get-SkillPruningCandidates -HubPath $HubPath -FrameworkPath $FrameworkPath -UsagePath $UsagePath -InactiveDays $InactiveDays -HurtThreshold $HurtThreshold -EmitProposals:$EmitProposals
$r|ConvertTo-Json -Depth 6
exit $r.Code