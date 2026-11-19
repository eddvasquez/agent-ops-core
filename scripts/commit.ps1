# Verified commit/tag for agents: explicit paths, message by file, no tag unless the commit succeeded.
[CmdletBinding()]
param([string]$RepositoryPath=(Get-Location).Path,
      [Parameter(Mandatory=$true)][string[]]$Paths,
      [string]$Message='',[string]$MessageFile='',
      [string]$Tag='',[string]$TagMessage='',[switch]$SkipChecks)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'AgentOpsCommit.psm1') -Force
# Through `powershell -File`, a list arrives as one string: accept "a,b,c" as well as an array.
$Paths=@($Paths|ForEach-Object {$_ -split ','}|ForEach-Object {$_.Trim()}|Where-Object {$_})
$result=Invoke-AgentOpsCommit -RepositoryPath $RepositoryPath -Paths $Paths -Message $Message -MessageFile $MessageFile -Tag $Tag -TagMessage $TagMessage -SkipChecks:$SkipChecks
$result|ConvertTo-Json -Depth 5
exit $result.Code
