# Pre-commit review entry point: run by the Git hook (human message) or by agents (-Json).
[CmdletBinding()]
param([string]$RepositoryPath=(Get-Location).Path,[switch]$Json)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'PreCommitCheck.psm1') -Force
$r=Test-AgentOpsPreCommit -RepositoryPath $RepositoryPath
if($Json){$r|ConvertTo-Json -Depth 5}
elseif($r.Code -ne 0){
    [Console]::Error.WriteLine('Agent Ops frenó este guardado (commit). Nada se ha guardado todavía.')
    foreach($i in $r.Issues){
        [Console]::Error.WriteLine('- '+$i.Message)
        [Console]::Error.WriteLine('  Cómo arreglarlo: '+$i.Fix)
    }
}
exit $r.Code
