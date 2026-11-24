# Runs the project's test suites (-Changed: only those covering the uncommitted code; -Parallel N: N at a time, off by default because timing-sensitive suites fail on a loaded machine) and records green evidence for the turn gate (JSON for the assistant).
[CmdletBinding()]
param([string]$ProjectPath=(Get-Location).Path,[string[]]$Suites=@(),[int]$Parallel=[Math]::Max(2,[Math]::Min(4,[int]([Environment]::ProcessorCount/2))),[switch]$Changed)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'TurnGate.psm1') -Force
# Through `powershell -File`, a list arrives as one string: accept "a,b" as well as an array.
$Suites=@($Suites|ForEach-Object {$_ -split ','}|ForEach-Object {$_.Trim()}|Where-Object {$_})
$r=Invoke-AgentOpsTestRun -ProjectPath $ProjectPath -Suites $Suites -Parallel $Parallel -Changed:$Changed
$r|ConvertTo-Json -Depth 5
exit $r.Code
