# Runs the project's test suites and records green evidence for the turn gate (JSON for the assistant).
[CmdletBinding()]
param([string]$ProjectPath=(Get-Location).Path,[string[]]$Suites=@())
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'TurnGate.psm1') -Force
# Through `powershell -File`, a list arrives as one string: accept "a,b" as well as an array.
$Suites=@($Suites|ForEach-Object {$_ -split ','}|ForEach-Object {$_.Trim()}|Where-Object {$_})
$r=Invoke-AgentOpsTestRun -ProjectPath $ProjectPath -Suites $Suites
$r|ConvertTo-Json -Depth 5
exit $r.Code
