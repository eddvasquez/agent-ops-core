# Stable entry point: JSON for the assistant; user interaction belongs to the host.
[CmdletBinding(SupportsShouldProcess=$true)]
param([string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'),
      [ValidateSet('Check','Prepare','Apply','Defer','Repair')][string]$Action='Check',
      [string]$SessionId='',[string]$CandidateSha='',[switch]$Background)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'UpdateCoordinator.psm1') -Force
$r=Invoke-AgentOpsUpdate -ConfigPath $ConfigPath -Action $Action -SessionId $SessionId -CandidateSha $CandidateSha -Background:$Background -BeginSession -WhatIf:$WhatIfPreference
$r|ConvertTo-Json -Depth 20
exit $r.Code
