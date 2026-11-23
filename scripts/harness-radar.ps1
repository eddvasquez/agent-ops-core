# Harness radar entry point (JSON for the assistant): Check (once a day per source), Notice, Ack, Detect, Validate.
[CmdletBinding()]
param([ValidateSet('Check','Notice','Ack','Detect','Validate')][string]$Action='Notice',
      [string]$StateDir=(Join-Path $env:LOCALAPPDATA 'AgentOps'),[string]$ProjectPath=(Get-Location).Path,
      [string]$Harness='',[string]$Version='')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'HarnessRadar.psm1') -Force
if($Action -eq 'Detect'){$r=[pscustomobject]@{Code=0;Status='DETECTED';Harnesses=@(Get-AgentOpsHarnessPresence -ProjectPath $ProjectPath)}}
elseif($Action -eq 'Validate'){$r=Test-AgentOpsHarnessCapabilities;$r|Add-Member -NotePropertyName Status -NotePropertyValue $(if($r.Code){'INVALID'}else{'VALID'})}
else{$r=Invoke-AgentOpsHarnessRadar -Action $Action -ProjectPath $ProjectPath -StateDir $StateDir -Harness $Harness -Version $Version}
$r|ConvertTo-Json -Depth 5
exit $r.Code
