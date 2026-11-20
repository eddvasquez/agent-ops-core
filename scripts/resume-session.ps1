# Read-only cold resume for MODO ENTRADA: was the previous session interrupted, and where exactly?
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$ProjectPath,
      [string]$ClaudeProjectsRoot=(Join-Path $env:USERPROFILE '.claude/projects'),
      [string]$CodexSessionsRoot=(Join-Path $env:USERPROFILE '.codex/sessions'),
      [int]$TurnCount=5)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SessionCheckpoint.psm1') -Force
$r=Get-SessionResume -ProjectPath $ProjectPath -ClaudeProjectsRoot $ClaudeProjectsRoot -CodexSessionsRoot $CodexSessionsRoot -TurnCount $TurnCount
$r|ConvertTo-Json -Depth 6
exit $r.Code
