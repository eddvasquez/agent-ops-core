# Test runner: suites in parallel and, with -Changed, only the suites that cover what changed.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/TurnGate.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-runtests-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
function Put($r,$k,$t){$p=Join-Path $r $k;[IO.Directory]::CreateDirectory((Split-Path -Parent $p))|Out-Null;[IO.File]::WriteAllText($p,$t,$utf8)}
function Repo([hashtable]$files){
    $r=Join-Path $script:base ('repo-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($r)|Out-Null
    & git init -q -b main $r;& git -C $r config user.name Tests;& git -C $r config user.email tests@localhost;& git -C $r config core.autocrlf false
    foreach($k in $files.Keys){Put $r $k $files[$k]}
    & git -C $r add -A;& git -C $r commit -q --no-verify -m base
    return $r
}
# Each slow suite records when it ran; overlapping intervals prove they ran at the same time (no fragile timing).
$slow="`$log=Join-Path (Split-Path -Parent `$PSScriptRoot) 'runs.log'`n`$a=[datetime]::UtcNow.Ticks;Start-Sleep -Seconds 3;`$b=[datetime]::UtcNow.Ticks`n[IO.File]::AppendAllText(`$log,`"`$a `$b``n`")`nWrite-Host 'slow: 1 passed, 0 failed.'`nexit 0"
# Module graph: B imports A; suite a loads A, suite b loads B, suite c is unrelated.
$graph=@{
    'scripts/A.psm1'='function Get-A{1}'
    'scripts/B.psm1'="Import-Module (Join-Path `$PSScriptRoot 'A.psm1') -Force`nfunction Get-B{2}"
    'scripts/c-tool.ps1'="'c'"
    'tests/a.tests.ps1'="Import-Module (Join-Path `$PSScriptRoot '../scripts/A.psm1')`nexit 0"
    'tests/b.tests.ps1'="Import-Module (Join-Path `$PSScriptRoot '../scripts/B.psm1')`nexit 0"
    'tests/c.tests.ps1'="& (Join-Path `$PSScriptRoot '../scripts/c-tool.ps1')`nexit 0"
    'tests/TestFixtures.ps1'='# shared'
}

Test 'suites run in parallel: three 3-second suites take far less than 9 seconds, and evidence lists them' {
    $r=Repo @{'tests/one.tests.ps1'=$slow;'tests/two.tests.ps1'=$slow;'tests/three.tests.ps1'=$slow;'scripts/x.ps1'="'x'"}
    Put $r 'scripts/x.ps1' "'y'"
    $sw=[Diagnostics.Stopwatch]::StartNew();$run=Invoke-AgentOpsTestRun -ProjectPath $r -Parallel 3;$sw.Stop()
    Assert ($run.Code -eq 0 -and $run.Status -eq 'GREEN' -and @($run.Results).Count -eq 3) ($run|ConvertTo-Json -Depth 5)
    $spans=@([IO.File]::ReadAllLines((Join-Path $r 'runs.log'))|ForEach-Object {,([long[]]($_ -split ' '))})
    Assert ($spans.Count -eq 3 -and ($spans|ForEach-Object {$_[0]}|Measure-Object -Maximum).Maximum -lt ($spans|ForEach-Object {$_[1]}|Measure-Object -Minimum).Minimum) "Suites did not overlap: $($spans|ForEach-Object {$_ -join '-'})"
    $ev=[IO.File]::ReadAllText((Join-Path $r '.context/test-evidence.json'))|ConvertFrom-Json
    Assert (@($ev.Suites).Count -eq 3) ($ev|ConvertTo-Json -Depth 5)
}
Test 'a red suite in a parallel run records no evidence' {
    $r=Repo @{'tests/ok.tests.ps1'="exit 0";'tests/bad.tests.ps1'="Write-Host 'bad: 0 passed, 1 failed.'`nexit 1";'scripts/x.ps1'="'x'"}
    Put $r 'scripts/x.ps1' "'y'"
    $run=Invoke-AgentOpsTestRun -ProjectPath $r -Parallel 2
    Assert ($run.Code -eq 1 -and $run.Status -eq 'RED' -and @($run.Results|Where-Object {$_.Suite -eq 'bad' -and $_.Exit -ne 0}).Count -eq 1) ($run|ConvertTo-Json -Depth 5)
    Assert (-not (Test-Path (Join-Path $r '.context/test-evidence.json'))) 'Evidence written for a red run'
}
Test 'changing a module selects the suites that load it, directly or through another module' {
    $r=Repo $graph;Put $r 'scripts/A.psm1' 'function Get-A{9}'
    $sel=Get-AgentOpsSuitesForChanges -ProjectPath $r
    Assert ((@($sel.Suites)|Sort-Object) -join ',' -eq 'a,b' -and -not $sel.All) ($sel|ConvertTo-Json -Depth 5)
}
Test 'changing a suite or a script selects only what covers it' {
    $r=Repo $graph;Put $r 'tests/c.tests.ps1' "exit 0`n# cambio"
    Assert ((@((Get-AgentOpsSuitesForChanges -ProjectPath $r).Suites)) -join ',' -eq 'c') 'Suite change'
    $r=Repo $graph;Put $r 'scripts/c-tool.ps1' "'c2'"
    Assert ((@((Get-AgentOpsSuitesForChanges -ProjectPath $r).Suites)) -join ',' -eq 'c') 'Script change'
}
Test 'a change to something shared selects every suite; no code change selects none' {
    $r=Repo $graph;Put $r 'tests/TestFixtures.ps1' '# shared v2'
    $all=Get-AgentOpsSuitesForChanges -ProjectPath $r
    Assert ($all.All -and @($all.Suites).Count -eq 3) ($all|ConvertTo-Json -Depth 5)
    $r=Repo $graph;Put $r 'README.md' 'docs'
    $none=Get-AgentOpsSuitesForChanges -ProjectPath $r
    Assert (-not @($none.Suites).Count -and -not $none.All) ($none|ConvertTo-Json -Depth 5)
}
Test 'run-tests -Changed runs only the selected suites' {
    $r=Repo $graph;Put $r 'scripts/c-tool.ps1' "'c3'"
    $run=Invoke-AgentOpsTestRun -ProjectPath $r -Changed
    Assert ($run.Code -eq 0 -and (@($run.Results|ForEach-Object {$_.Suite}) -join ',') -eq 'c') ($run|ConvertTo-Json -Depth 5)
}
Write-Host "Test runner: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
