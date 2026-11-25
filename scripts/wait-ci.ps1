# Waits for the GitHub tests of a commit and prints one JSON line when they end (R-013: start it in the background
# and keep working). Codes: 0 green, 1 red, 2 timeout, 3 offline, 4 invalid input or not a GitHub repository.
[CmdletBinding()]
param([string]$ProjectPath=(Get-Location).Path,[string]$Sha='',[int]$TimeoutMinutes=15,[int]$IntervalSeconds=60)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'CIWait.psm1') -Force
$ErrorActionPreference='Continue'
if(-not $Sha){$Sha=((& git -C $ProjectPath rev-parse HEAD 2>$null)|Select-Object -First 1)}
$remote=((& git -C $ProjectPath remote get-url origin 2>$null)|Select-Object -First 1)
$repo=ConvertTo-AgentOpsGitHubRepository ([string]$remote)
if(-not $repo){[pscustomobject]@{Code=4;Status='NOT_GITHUB';Sha=$Sha}|ConvertTo-Json -Compress;exit 4}
$r=Wait-AgentOpsCI -Repository $repo -Sha ([string]$Sha).Trim() -TimeoutMinutes $TimeoutMinutes -IntervalSeconds $IntervalSeconds
$r|ConvertTo-Json -Depth 5 -Compress
exit $r.Code
