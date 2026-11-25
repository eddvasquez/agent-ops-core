# Runs the project's test suites (-Changed: only those covering the uncommitted code; -Parallel N: N at a time, a suite that accepts -Shard split into N parts; the default 0 picks N from the machine's free cores and memory, -Parallel 1 runs one at a time; -Snapshot runs them on a copy of the current state, so the project can keep being edited) and records green evidence for the turn gate (JSON for the assistant).
[CmdletBinding()]
param([string]$ProjectPath=(Get-Location).Path,[string[]]$Suites=@(),[int]$Parallel=0,[switch]$Changed,[switch]$Snapshot)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'TurnGate.psm1') -Force
# Through `powershell -File`, a list arrives as one string: accept "a,b" as well as an array.
$Suites=@($Suites|ForEach-Object {$_ -split ','}|ForEach-Object {$_.Trim()}|Where-Object {$_})
$r=Invoke-AgentOpsTestRun -ProjectPath $ProjectPath -Suites $Suites -Parallel $Parallel -Changed:$Changed -Snapshot:$Snapshot
$r|ConvertTo-Json -Depth 5
exit $r.Code
