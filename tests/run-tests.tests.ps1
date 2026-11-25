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
# One file per suite: concurrent appends to a shared file can be refused by Windows and silently lose a line.
$slow="`$log=Join-Path (Split-Path -Parent `$PSScriptRoot) ('runs-'+(Split-Path -Leaf `$PSCommandPath)+'.log')`n`$a=[datetime]::UtcNow.Ticks;Start-Sleep -Seconds 3;`$b=[datetime]::UtcNow.Ticks`n[IO.File]::AppendAllText(`$log,`"`$a `$b``n`")`nWrite-Host 'slow: 1 passed, 0 failed.'`nexit 0"
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
    $spans=@(Get-ChildItem -LiteralPath $r -Filter 'runs-*.log'|ForEach-Object {[IO.File]::ReadAllLines($_.FullName)}|ForEach-Object {,([long[]]($_ -split ' '))})
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
Test 'shards split a suite into disjoint parts that together cover every test' {
    foreach($n in 1,2,3,4){
        $owners=foreach($i in 1..29){@(1..$n|Where-Object {Test-InTestShard $i "$_/$n"}).Count}
        Assert (@($owners|Where-Object {$_ -ne 1}).Count -eq 0) "With $n shards some test runs zero or several times"
    }
    Assert (Test-InTestShard 7 '') 'Without a shard every test must run'
    foreach($bad in '0/3','4/3','a/b','3','1/0','-1/2'){
        $threw=$false;try{Test-InTestShard 1 $bad|Out-Null}catch{$threw=$true}
        Assert $threw "Accepted invalid shard '$bad'"
    }
}
Test 'with -Parallel a suite that accepts -Shard runs as that many parts and reports as one suite' {
    $sharded="param([string]`$Shard='')`n[IO.File]::WriteAllText((Join-Path (Split-Path -Parent `$PSScriptRoot) ('shard-'+`$Shard.Replace('/','of')+'.log')),`$Shard)`nif(`$Shard -eq '2/2' -and (Test-Path (Join-Path (Split-Path -Parent `$PSScriptRoot) 'fail-second'))){Write-Host 'part: 0 passed, 1 failed.';exit 1}`nWrite-Host ('part '+`$Shard+': 1 passed, 0 failed.')`nexit 0"
    $r=Repo @{'tests/big.tests.ps1'=$sharded;'tests/plain.tests.ps1'="Write-Host 'plain: 1 passed, 0 failed.'`nexit 0"}
    $run=Invoke-AgentOpsTestRun -ProjectPath $r -Parallel 2
    Assert ($run.Code -eq 0 -and @($run.Results).Count -eq 2) ($run|ConvertTo-Json -Depth 5)
    $big=@($run.Results|Where-Object {$_.Suite -eq 'big'})[0]
    Assert ($big.Exit -eq 0 -and $big.Summary -match '1/2' -and $big.Summary -match '2/2') ($big|ConvertTo-Json)
    Assert ((Test-Path (Join-Path $r 'shard-1of2.log')) -and (Test-Path (Join-Path $r 'shard-2of2.log')) -and -not (Test-Path (Join-Path $r 'shard-.log'))) 'Suite not split into its two parts'
    Put $r 'fail-second' 'x'
    $run=Invoke-AgentOpsTestRun -ProjectPath $r -Parallel 2
    Assert ($run.Code -ne 0 -and @($run.Results|Where-Object {$_.Suite -eq 'big'})[0].Exit -ne 0) 'A red part must make its suite red'
    $run=Invoke-AgentOpsTestRun -ProjectPath $r -Suites big
    Assert ($run.Code -eq 0 -and (Test-Path (Join-Path $r 'shard-.log'))) 'Without -Parallel the suite must run whole'
}
Test 'the parts of a split (slow) suite start before the whole suites' {
    $stamp="[IO.File]::WriteAllText((Join-Path (Split-Path -Parent `$PSScriptRoot) ('start-'+(Split-Path -Leaf `$PSCommandPath)+`$(if(`$Shard){'-'+`$Shard.Replace('/','of')})+'.log')),[datetime]::UtcNow.Ticks.ToString())`nStart-Sleep -Seconds 2`nWrite-Host 'x: 1 passed, 0 failed.'`nexit 0"
    $r=Repo @{'tests/aaa.tests.ps1'="`$Shard=''`n$stamp";'tests/zzz.tests.ps1'="param([string]`$Shard='')`n$stamp"}
    $run=Invoke-AgentOpsTestRun -ProjectPath $r -Parallel 2
    Assert ($run.Code -eq 0) ($run|ConvertTo-Json -Depth 5)
    $t={param($n)[long][IO.File]::ReadAllText((Join-Path $r $n))}
    $plain=& $t 'start-aaa.tests.ps1.log'
    Assert ((& $t 'start-zzz.tests.ps1-1of2.log') -lt $plain -and (& $t 'start-zzz.tests.ps1-2of2.log') -lt $plain) 'A whole suite started before the parts of the split one'
}
Test 'automatic parallelism follows the free cores and memory, with no fixed ceiling (R-012)' {
    # Measured on 8 logical cores: 4 parts 155 s, 6 parts no faster and timing-sensitive tests failed: half the cores.
    Assert ((Get-AgentOpsTestSlots -Cores 8 -FreeMB 4000) -eq 4) '8 cores should give 4'
    Assert ((Get-AgentOpsTestSlots -Cores 16 -FreeMB 8000) -eq 8) 'A bigger machine must use its capacity (16 cores -> 8)'
    Assert ((Get-AgentOpsTestSlots -Cores 32 -FreeMB 16000) -eq 16) '32 cores with enough memory -> 16'
    Assert ((Get-AgentOpsTestSlots -Cores 4 -FreeMB 4000) -eq 2) '4 cores should give 2'
    Assert ((Get-AgentOpsTestSlots -Cores 1 -FreeMB 4000) -eq 1) 'At least 1'
    Assert ((Get-AgentOpsTestSlots -Cores 8 -FreeMB 500) -eq 2) 'Little free memory must lower it (250 MB per part)'
    Assert ((Get-AgentOpsTestSlots -Cores 8 -FreeMB 100) -eq 1) 'Almost no memory: one at a time'
    $auto=Get-AgentOpsTestSlots
    Assert ($auto -ge 1 -and $auto -le [Math]::Max(1,[Math]::Floor([Environment]::ProcessorCount/2))) "Measured value out of range: $auto"
}
Test 'run-tests uses the automatic parallelism by default (R-012)' {
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $source 'scripts/run-tests.ps1'),[ref]$tokens,[ref]$errors)
    $p=@($ast.ParamBlock.Parameters|Where-Object {$_.Name.VariablePath.UserPath -eq 'Parallel'})[0]
    Assert ($p -and $p.DefaultValue.Extent.Text -eq '0') "Default -Parallel is $($p.DefaultValue.Extent.Text), expected 0 (automatic)"
}
Write-Host "Test runner: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
