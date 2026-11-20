[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath,
      [string]$RulesPath='',
      [string]$ClaudeProjectsRoot=(Join-Path $env:USERPROFILE '.claude/projects'),
      [string]$CodexSessionsRoot=(Join-Path $env:USERPROFILE '.codex/sessions'),
      [string]$AntigravityBrainRoot=(Join-Path $env:USERPROFILE '.gemini/antigravity/brain'),
      [Nullable[datetime]]$Since=$null,
      [string]$OutPath='')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'InstructionHarvest.psm1') -Force
$r=Invoke-InstructionHarvest -ProjectPath $ProjectPath -RulesPath $RulesPath -ClaudeProjectsRoot $ClaudeProjectsRoot -CodexSessionsRoot $CodexSessionsRoot -AntigravityBrainRoot $AntigravityBrainRoot -Since $Since -OutPath $OutPath
$r|ConvertTo-Json -Depth 8
exit $r.Code
