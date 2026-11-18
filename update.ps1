# Scheduled/manual checks never imply consent to activate a version.
[CmdletBinding(SupportsShouldProcess=$true)]
param([switch]$Force,[string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'),
      [ValidateSet('Check','Prepare','Apply','Defer','Repair')][string]$Action='Check',
      [string]$SessionId='',[string]$CandidateSha='',[switch]$Background)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'scripts/UpdateCoordinator.psm1') -Force
# -Force remains accepted for old daily tasks; it never bypasses approval.
$r=Invoke-AgentOpsUpdate -ConfigPath $ConfigPath -Action $Action -SessionId $SessionId -CandidateSha $CandidateSha -Background:$Background -WhatIf:$WhatIfPreference
$r|ConvertTo-Json -Depth 20
exit $r.Code
