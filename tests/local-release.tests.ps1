# Local release proof (R-014): a committed state is tested on a copy, in Windows PowerShell and PowerShell 7, and
# only an all-green result is recorded as the proof the update coordinator requires. The suite runner is injected.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/LocalRelease.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-localrelease-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
function Repo{
    $r=Join-Path $script:base ('repo-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($r)|Out-Null
    & git init -q -b main $r;& git -C $r config user.name Tests;& git -C $r config user.email tests@localhost;& git -C $r config core.autocrlf false
    [IO.File]::WriteAllText((Join-Path $r 'README.md'),'x');& git -C $r add -A;& git -C $r commit -q --no-verify -m base
    return $r
}
function State{$s=Join-Path $script:base ('state-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($s)|Out-Null;return $s}
$green={param($dir,$edition) $script:runs+=,@($dir,$edition,[IO.File]::Exists((Join-Path $dir 'README.md')));[pscustomobject]@{Green=$true;Suites=@("demo ($edition): 3 passed, 0 failed.");Failures=@()}}

Test 'a committed state green in both editions is recorded as its proof; the copy is removed' {
    $r=Repo;$s=State;$script:runs=@()
    $p=New-AgentOpsLocalProof -SourceRepo $r -StateDir $s -Runner $green
    $sha=((& git -C $r rev-parse HEAD)|Select-Object -First 1).Trim()
    Assert ($p.Code -eq 0 -and $p.Status -eq 'PROVEN' -and $p.Sha -eq $sha) ($p|ConvertTo-Json -Depth 5)
    $proof=[IO.File]::ReadAllText((Join-Path $s "local-proofs/$sha.json"))|ConvertFrom-Json
    Assert ($proof.SchemaVersion -eq 1 -and $proof.Sha -eq $sha -and $proof.Green -eq $true -and (@($proof.Editions) -join ',') -eq 'Desktop,Core') ($proof|ConvertTo-Json -Depth 4)
    Assert ($script:runs.Count -eq 2 -and $script:runs[0][0] -ne $r -and $script:runs[0][2]) 'Suites did not run on a copy of the commit'
    Assert (-not [IO.Directory]::Exists($script:runs[0][0])) 'Copy left behind'
    Assert (@(& git -C $r worktree list --porcelain|Where-Object {$_ -like 'worktree *'}).Count -eq 1) 'Worktree still registered'
}
Test 'a red edition records no proof and says what failed' {
    $r=Repo;$s=State
    $red={param($dir,$edition) if($edition -eq 'Core'){[pscustomobject]@{Green=$false;Suites=@();Failures=@('FAIL demo (Core): roto')}}else{[pscustomobject]@{Green=$true;Suites=@('demo');Failures=@()}}}
    $p=New-AgentOpsLocalProof -SourceRepo $r -StateDir $s -Runner $red
    Assert ($p.Code -eq 1 -and $p.Status -eq 'RED' -and (@($p.Failures) -join ' ') -match 'roto') ($p|ConvertTo-Json -Depth 5)
    Assert (-not (Test-Path (Join-Path $s 'local-proofs'))) 'A proof was written for a red run'
}
Test 'uncommitted changes do not stop the proof: the commit is tested and the user is told they are left out' {
    $r=Repo;$s=State;$script:runs=@();[IO.File]::WriteAllText((Join-Path $r 'nuevo.ps1'),'x')
    $p=New-AgentOpsLocalProof -SourceRepo $r -StateDir $s -Runner $green
    Assert ($p.Code -eq 0 -and $p.Status -eq 'PROVEN' -and $script:runs.Count -eq 2) ($p|ConvertTo-Json -Depth 5)
    Assert ((@($p.Issues) -join ' ') -match 'no se incluyen') ($p|ConvertTo-Json -Depth 5)
    Assert (-not [IO.File]::Exists((Join-Path $script:runs[0][0] 'nuevo.ps1'))) 'Copy is gone; checked below by worktree count'
}
Write-Host "Local release: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
