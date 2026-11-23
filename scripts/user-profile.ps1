[CmdletBinding()]
param([ValidateSet('Get','Set')][string]$Action='Get',
      [string]$StateDir='',
      [string]$Role='',
      [string]$TechFamiliarity='',
      [string]$Detail='',
      [switch]$Skipped)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'UserProfile.psm1') -Force
$common=@{};if($StateDir){$common.StateDir=$StateDir}
if($Action -eq 'Get'){$result=Get-AgentOpsUserProfile @common}
else{$result=Set-AgentOpsUserProfile @common -Role $Role -TechFamiliarity $TechFamiliarity -Detail $Detail -Skipped:$Skipped}
$result|ConvertTo-Json -Depth 5
exit $result.Code
