# Compatibility entry point: rescue and reconcile using the common safe engine.
[CmdletBinding(SupportsShouldProcess=$true)]
param([string]$HubDir,[Alias('Targets')][string[]]$Sources,[string]$StateDir,[string]$FrameworkDir,[switch]$Json)
$forward=@{Mode='Apply'}
foreach($k in $PSBoundParameters.Keys){if($k -eq 'Sources'){$forward.Targets=$Sources}else{$forward[$k]=$PSBoundParameters[$k]}}
& (Join-Path $PSScriptRoot '../../scripts/sync-skills.ps1') @forward
exit $LASTEXITCODE
