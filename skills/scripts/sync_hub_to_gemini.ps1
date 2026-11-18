# Compatibility entry point. The default hub is outside this checkout.
[CmdletBinding(SupportsShouldProcess=$true)]
param([string]$HubDir,[string[]]$Targets,[string]$StateDir,[string]$FrameworkDir,
      [ValidateSet('Plan','Apply','Verify')][string]$Mode='Apply',[switch]$Json)
$forward=@{};foreach($k in $PSBoundParameters.Keys){$forward[$k]=$PSBoundParameters[$k]}
if(-not $forward.ContainsKey('Mode')){$forward.Mode=$Mode}
& (Join-Path $PSScriptRoot '../../scripts/sync-skills.ps1') @forward
exit $LASTEXITCODE
