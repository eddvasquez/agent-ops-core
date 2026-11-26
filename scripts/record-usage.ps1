# Records or syncs skill usage telemetry into <hub>/proposals/usage.jsonl.
[CmdletBinding()]
param([string]$Skill='',[string]$Project='(sin proyecto)',[string]$Outcome='used',[string]$SessionId='',
      [string]$Harness='unknown',[string]$HubPath='',[string]$FrameworkPath='',[string]$UsagePath='',
      [switch]$SyncFromTranscripts,[string]$ProjectPath='',
      [string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'LearningProposals.psm1') -Force
if(-not $HubPath -and [IO.File]::Exists($ConfigPath)){
    $cfg=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
    if($cfg.PSObject.Properties['HubDir'] -and $cfg.HubDir){$HubPath=[string]$cfg.HubDir}
    if(-not $FrameworkPath -and $cfg.PSObject.Properties['FrameworkDir'] -and $cfg.FrameworkDir){$FrameworkPath=[string]$cfg.FrameworkDir}
}
if($SyncFromTranscripts){
    $r=Sync-SkillUsageFromTranscripts -HubPath $HubPath -FrameworkPath $FrameworkPath -ProjectPath $ProjectPath -UsagePath $UsagePath
}else{
    $r=Register-SkillUsage -Skill $Skill -Project $Project -Outcome $Outcome -SessionId $SessionId -Harness $Harness -Source 'declared' -HubPath $HubPath -UsagePath $UsagePath
}
$r|ConvertTo-Json -Depth 6
exit $r.Code