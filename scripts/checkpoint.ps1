# Record a cheap resume point after each step (no commit), or close it in MODO SALIDA with -Close.
[CmdletBinding(DefaultParameterSetName='Write')]
param([Parameter(Mandatory=$true)][string]$ProjectPath,
      [Parameter(ParameterSetName='Write',Mandatory=$true)][string]$Agent,
      [Parameter(ParameterSetName='Write',Mandatory=$true)][string]$Step,
      [Parameter(ParameterSetName='Write',Mandatory=$true)][string]$Next,
      [Parameter(ParameterSetName='Write')][string[]]$Files=@(),
      [Parameter(ParameterSetName='Write')][string]$Request='',
      [Parameter(ParameterSetName='Close',Mandatory=$true)][switch]$Close)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SessionCheckpoint.psm1') -Force
$r=if($Close){Close-SessionCheckpoint -ProjectPath $ProjectPath}else{Write-SessionCheckpoint -ProjectPath $ProjectPath -Agent $Agent -Step $Step -Next $Next -Files $Files -Request $Request}
$r|ConvertTo-Json -Depth 6
exit $r.Code
