# Governed session distillation CLI (silent when no signal; sanitizes and blocks secrets before inbox capture).
[CmdletBinding()]
param([string]$ProjectPath=(Get-Location).Path,[string]$HubPath='',
      [string]$StateDir=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'}),
      [Nullable[datetime]]$Since=$null,[string[]]$RedactTerms=@(),
      [string]$ClaudeProjectsRoot=(Join-Path $env:USERPROFILE '.claude/projects'),
      [string]$CodexSessionsRoot=(Join-Path $env:USERPROFILE '.codex/sessions'),
      [string]$AntigravityBrainRoot=(Join-Path $env:USERPROFILE '.gemini/antigravity/brain'),
      [switch]$CaptureToInbox,
      [string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SessionDistill.psm1') -Force
if(-not $HubPath -and [IO.File]::Exists($ConfigPath)){
    $cfg=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
    if($cfg.PSObject.Properties['HubDir'] -and $cfg.HubDir){$HubPath=[string]$cfg.HubDir}
}
$r=Invoke-SessionDistill -ProjectPath $ProjectPath -HubPath $HubPath -StateDir $StateDir -Since $Since -RedactTerms $RedactTerms -ClaudeProjectsRoot $ClaudeProjectsRoot -CodexSessionsRoot $CodexSessionsRoot -AntigravityBrainRoot $AntigravityBrainRoot -CaptureToInbox:$CaptureToInbox
$r|ConvertTo-Json -Depth 6
exit $r.Code