[CmdletBinding(SupportsShouldProcess=$true)]
param([Parameter(Mandatory=$true)][string]$ManifestPath,
      [Parameter(Mandatory=$true)][string]$SourceRoot,
      [Parameter(Mandatory=$true)][string]$Destination)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SkillsSync.psm1') -Force
$r=Restore-SkillRescue -ManifestPath $ManifestPath -SourceRoot $SourceRoot -Destination $Destination -WhatIf:$WhatIfPreference
$r|ConvertTo-Json -Depth 10
exit $r.Code
