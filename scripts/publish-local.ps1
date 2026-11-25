# Local channel (R-014): installs on this PC, for every project, the committed HEAD of the framework repository
# once every suite is green for that exact commit in Windows PowerShell and PowerShell 7. Run it from the ACTIVE
# release ($ActivePath/scripts/publish-local.ps1), never from the working copy. -Revert returns to the last
# version GitHub confirmed. Long: start it in the background and keep working (R-013).
[CmdletBinding()]
param([string]$SourceRepo=(Get-Location).Path,[switch]$Revert,[string]$SessionId=('local-'+[guid]::NewGuid().ToString('N')),
      [string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'))
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'UpdateCoordinator.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'LocalRelease.psm1') -Force
$proof=$null
if(-not $Revert){
    $proof=New-AgentOpsLocalProof -SourceRepo $SourceRepo -StateDir (Split-Path -Parent $ConfigPath)
    if($proof.Code -ne 0){[pscustomobject]@{Code=$proof.Code;Status=$proof.Status;Sha=$proof.Sha;Failures=@($proof.Failures);Issues=@($proof.Issues)}|ConvertTo-Json -Depth 5;exit $proof.Code}
}
$r=Install-AgentOpsLocalRelease -ConfigPath $ConfigPath -SourceRepo $SourceRepo -SessionId $SessionId -Revert:$Revert
$r|Add-Member -NotePropertyName Proof -NotePropertyValue $(if($proof){$proof.Proof}else{$null}) -Force
$r|ConvertTo-Json -Depth 6
exit $r.Code
