# Automatic review before every commit (Git pre-commit hook). All repositories are temporary fixtures.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/PreCommitCheck.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-precommit-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
function Put($r,$k,$t){$p=Join-Path $r $k;[IO.Directory]::CreateDirectory((Split-Path -Parent $p))|Out-Null;[IO.File]::WriteAllText($p,$t,$utf8)}
function Repo{
    $r=Join-Path $script:base ('Proyecto con espacios '+[guid]::NewGuid().ToString('N').Substring(0,6))
    [IO.Directory]::CreateDirectory($r)|Out-Null
    & git init -q -b main $r
    & git -C $r config user.name 'Tests'
    & git -C $r config user.email 'tests@localhost'
    & git -C $r config core.autocrlf false
    Put $r 'CHANGELOG.md' "# Changelog`n`n## [Unreleased]`n"
    Put $r 'app.txt' 'v1'
    & git -C $r add -- CHANGELOG.md app.txt
    & git -C $r commit -q --no-verify -m base
    return $r
}
# A fake installation whose active release is this source tree, so the launcher can be tested end to end.
function State{
    $s=Join-Path $script:base ('state-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    [IO.Directory]::CreateDirectory($s)|Out-Null
    $state=@{Mode='MANAGED';Active=@{Sha=('a'*40);Path=$source}}|ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $s 'update-state.json'),$state,$utf8)
    return $s
}
function GitCommit($r,$stateDir,$msg){
    # The hook writes its explanation to stderr; under 'Stop' Windows PowerShell would turn that into an exception.
    $old=$env:AGENT_OPS_STATE_DIR;$env:AGENT_OPS_STATE_DIR=$stateDir;$pref=$ErrorActionPreference;$ErrorActionPreference='Continue'
    try{$out=& git -C $r commit -q -m $msg 2>&1|Out-String;return @{Exit=$LASTEXITCODE;Output=$out}}
    finally{$env:AGENT_OPS_STATE_DIR=$old;$ErrorActionPreference=$pref}
}
$fakeToken='ghp_'+('A1b2C3d4E5'*4)

Test 'a staged change with its changelog entry passes' {
    $r=Repo;Put $r 'app.txt' 'v2';Put $r 'CHANGELOG.md' "# Changelog`n`n## [Unreleased]`n- Cambio en app.`n"
    & git -C $r add -- app.txt CHANGELOG.md
    $res=Test-AgentOpsPreCommit -RepositoryPath $r
    Assert ($res.Code -eq 0 -and $res.Status -eq 'PASSED') ($res|ConvertTo-Json -Depth 5)
}
Test 'a staged change without a changelog entry is blocked with the fix to apply' {
    $r=Repo;Put $r 'app.txt' 'v2';& git -C $r add -- app.txt
    $res=Test-AgentOpsPreCommit -RepositoryPath $r
    Assert ($res.Code -eq 1 -and $res.Status -eq 'BLOCKED') ($res|ConvertTo-Json -Depth 5)
    Assert (@($res.Issues|Where-Object {$_.Check -eq 'versioning' -and $_.Fix -match 'CHANGELOG\.md'}).Count -ge 1) ($res|ConvertTo-Json -Depth 5)
}
Test 'only staged changes count: an unstaged edit does not block' {
    $r=Repo;Put $r 'app.txt' 'v2'
    Put $r 'notes.txt' 'x';Put $r 'CHANGELOG.md' "# Changelog`n`n## [Unreleased]`n- Notas.`n"
    & git -C $r add -- notes.txt CHANGELOG.md
    $res=Test-AgentOpsPreCommit -RepositoryPath $r
    Assert ($res.Code -eq 0) ($res|ConvertTo-Json -Depth 5)
}
Test 'a credential in an added line is blocked, naming the file but never echoing the secret' {
    $r=Repo;Put $r 'config/settings.txt' "token=$fakeToken`n";Put $r 'CHANGELOG.md' "# Changelog`n`n## [Unreleased]`n- Ajustes.`n"
    & git -C $r add -- config/settings.txt CHANGELOG.md
    $res=Test-AgentOpsPreCommit -RepositoryPath $r
    $json=$res|ConvertTo-Json -Depth 5
    Assert ($res.Code -eq 1 -and @($res.Issues|Where-Object {$_.Check -eq 'secrets' -and $_.File -eq 'config/settings.txt'}).Count -eq 1) $json
    Assert ($json -notmatch [regex]::Escape($fakeToken)) 'The secret value appears in the result'
}
Test 'a credential that was already committed and is not being added again does not block' {
    $r=Repo;Put $r 'old.txt' "token=$fakeToken`n";& git -C $r add -- old.txt;& git -C $r commit -q --no-verify -m legacy
    Put $r 'old.txt' "token=$fakeToken`nmas texto`n";Put $r 'CHANGELOG.md' "# Changelog`n`n## [Unreleased]`n- Texto.`n"
    & git -C $r add -- old.txt CHANGELOG.md
    $res=Test-AgentOpsPreCommit -RepositoryPath $r
    Assert ($res.Code -eq 0) ($res|ConvertTo-Json -Depth 5)
}
Test 'the hook plan proposes two hook files in a repository without hooks' {
    $r=Repo
    $plan=Get-AgentOpsGitHookPlan -ProjectPath $r
    Assert ($plan.Status -eq 'READY' -and @($plan.Files).Count -eq 2) ($plan|ConvertTo-Json -Depth 5)
    Assert (@($plan.Files|Where-Object {$_.Key -eq '.git/hooks/pre-commit'}).Count -eq 1) ($plan|ConvertTo-Json -Depth 5)
}
Test 'an installed hook blocks a manual git commit without changelog and lets a correct one through' {
    $r=Repo;$s=State
    $inst=Install-AgentOpsGitHook -ProjectPath $r
    Assert ($inst.Status -eq 'INSTALLED') ($inst|ConvertTo-Json -Depth 5)
    Put $r 'app.txt' 'v2';& git -C $r add -- app.txt
    $bad=GitCommit $r $s 'sin changelog'
    Assert ($bad.Exit -ne 0) "Commit without changelog was accepted: $($bad.Output)"
    Assert ($bad.Output -match 'CHANGELOG') "No explanation shown: $($bad.Output)"
    Put $r 'CHANGELOG.md' "# Changelog`n`n## [Unreleased]`n- Cambio.`n";& git -C $r add -- CHANGELOG.md
    $good=GitCommit $r $s 'con changelog'
    Assert ($good.Exit -eq 0) "Correct commit was rejected: $($good.Output)"
}
Test 'installing twice is idempotent' {
    $r=Repo;Install-AgentOpsGitHook -ProjectPath $r|Out-Null
    $again=Install-AgentOpsGitHook -ProjectPath $r
    Assert ($again.Status -eq 'UP_TO_DATE') ($again|ConvertTo-Json -Depth 5)
}
Test 'a pre-commit hook from another tool is never overwritten' {
    $r=Repo;Put $r '.git/hooks/pre-commit' "#!/bin/sh`necho otro`n"
    $res=Install-AgentOpsGitHook -ProjectPath $r
    Assert ($res.Status -eq 'HOOK_REVIEW_REQUIRED') ($res|ConvertTo-Json -Depth 5)
    Assert ([IO.File]::ReadAllText((Join-Path $r '.git/hooks/pre-commit')) -match 'otro') 'Foreign hook was replaced'
}
Test 'a repository that uses its own hooks folder (core.hooksPath) needs review' {
    $r=Repo;& git -C $r config core.hooksPath .husky
    $plan=Get-AgentOpsGitHookPlan -ProjectPath $r
    Assert ($plan.Status -eq 'HOOK_REVIEW_REQUIRED') ($plan|ConvertTo-Json -Depth 5)
}
Test 'a folder without Git reports NOT_GIT and writes nothing' {
    $d=Join-Path $script:base ('sin-git-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($d)|Out-Null
    $plan=Get-AgentOpsGitHookPlan -ProjectPath $d
    Assert ($plan.Status -eq 'NOT_GIT' -and -not @($plan.Files).Count) ($plan|ConvertTo-Json -Depth 5)
}
Test 'without an Agent Ops installation the hook warns and lets the commit through' {
    $r=Repo;Install-AgentOpsGitHook -ProjectPath $r|Out-Null
    $empty=Join-Path $script:base ('vacio-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($empty)|Out-Null
    Put $r 'app.txt' 'v2';& git -C $r add -- app.txt
    $res=GitCommit $r $empty 'sin instalacion'
    Assert ($res.Exit -eq 0) "Commit blocked without installation: $($res.Output)"
    Assert ($res.Output -match 'Agent Ops') "No warning shown: $($res.Output)"
}
Test 'the entry script returns JSON and a non-zero exit code when blocked' {
    $r=Repo;Put $r 'app.txt' 'v2';& git -C $r add -- app.txt
    $engine=(Get-Process -Id $PID).Path
    $json=& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/pre-commit-check.ps1') -RepositoryPath $r -Json|Out-String
    Assert ($LASTEXITCODE -eq 1 -and ($json|ConvertFrom-Json).Status -eq 'BLOCKED') $json
}
Test 'the credential pattern is the same one the public release policy uses' {
    $scan=[IO.File]::ReadAllText((Join-Path $source 'scripts/SecretScan.psm1'))
    Assert ($scan -match "\`$script:pattern='([^']+)'") 'Pattern not found in SecretScan.psm1'
    $pattern=$Matches[1]
    $coordinator=[IO.File]::ReadAllText((Join-Path $source 'scripts/UpdateCoordinator.psm1'))
    Assert ($coordinator.Contains("-match '$pattern'")) 'UpdateCoordinator.psm1 uses a different credential pattern'
}
Write-Host "Pre-commit review:$script:passed passed, $script:failed failed. Fixtures: $script:base"
if($script:failed){exit 1}
