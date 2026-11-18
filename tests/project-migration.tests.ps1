[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/ProjectMigration.psm1') -Force
$base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-migrations-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($base)|Out-Null
$passed=0;$failed=0
function Assert($v,$m){if(-not $v){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_";Write-Host $_.ScriptStackTrace}}
function Fixture {
    $root=Join-Path $base ([guid]::NewGuid().ToString('N'));$frame=Join-Path $root 'frame';$project=Join-Path $root 'project'
    [IO.Directory]::CreateDirectory($frame)|Out-Null;[IO.Directory]::CreateDirectory($project)|Out-Null
    Copy-Item (Join-Path $source 'templates') $frame -Recurse
    foreach($name in @('dev-systematic-debugging','dev-tdd','ops-git-worktrees','ops-project-init','ops-project-migrate','ops-session-handoff')){
        $dir=Join-Path $frame ('skills/'+$name);[IO.Directory]::CreateDirectory($dir)|Out-Null
        Copy-Item (Join-Path $source ('skills/'+$name+'/SKILL.md')) $dir
    }
    $config=@{HubDir=(Join-Path $root 'custom-hub');Targets=@((Join-Path $root 'replica'));StateDir=(Join-Path $root 'private-state');FrameworkDir=$frame}
    [IO.Directory]::CreateDirectory($config.StateDir)|Out-Null
    $path=Join-Path $config.StateDir 'watch-config.json';$config|ConvertTo-Json|Set-Content $path -Encoding UTF8
    $resolver={param($p) [pscustomobject]@{Path=$frame;Sha=('a'*40);Mode='MANAGED'}}.GetNewClosure()
    return @{ProjectPath=$project;ConfigPath=$path;ReleaseResolver=$resolver}
}
Test 'missing configuration never creates a fallback hub' {
    $f=Fixture;$f.ConfigPath=Join-Path $base 'absent/config.json';$r=Invoke-ProjectMigration @f
    Assert ($r.Code -eq 2 -and $r.Status -eq 'INSTALLATION_REQUIRED') 'Missing configuration accepted'
}
Test 'plan and WhatIf leave project and state unchanged; apply is repeatable' {
    $f=Fixture;$r=Invoke-ProjectMigration @f
    Assert ($r.Code -eq 0 -and $r.Actions.Count -eq 6 -and -not (Test-Path (Join-Path $f.ProjectPath 'AGENTS.md'))) 'Plan wrote files'
    Invoke-ProjectMigration @f -Mode Apply -WhatIf|Out-Null
    Assert (-not (Test-Path (Join-Path (Split-Path $f.ConfigPath) 'migrations'))) 'WhatIf wrote private state'
    $r=Invoke-ProjectMigration @f -Mode Apply
    Assert ($r.Code -eq 0 -and (Test-Path (Join-Path $f.ProjectPath '.context/progress.md'))) ($r|ConvertTo-Json -Depth 5)
    $again=Invoke-ProjectMigration @f -Mode Apply
    Assert ($again.Code -eq 0 -and $again.Actions.Count -eq 0) 'Repeat rewrote project'
}
Test 'existing rules require a reviewed candidate and an unchanged original hash' {
    $f=Fixture;$agents=Join-Path $f.ProjectPath 'AGENTS.md';[IO.File]::WriteAllText($agents,'My particular rules')
    $p=Invoke-ProjectMigration @f
    Assert ($p.Code -eq 2 -and $p.Status -eq 'AGENTS_REVIEW_REQUIRED') 'Rules replaced without review'
    $candidate=Join-Path (Split-Path $f.ConfigPath) 'candidate.md';[IO.File]::WriteAllText($candidate,"My particular rules`nops-session-handoff MODO ENTRADA start-session.ps1")
    [IO.File]::WriteAllText($agents,'Later user edit')
    $r=Invoke-ProjectMigration @f -Mode Apply -AgentsCandidatePath $candidate -ExpectedAgentsHash $p.AgentsHash
    Assert ($r.Code -eq 2 -and [IO.File]::ReadAllText($agents) -eq 'Later user edit') 'Stale candidate overwrote later edit'
    $p=Invoke-ProjectMigration @f
    $r=Invoke-ProjectMigration @f -Mode Apply -AgentsCandidatePath $candidate -ExpectedAgentsHash $p.AgentsHash
    Assert ($r.Code -eq 0 -and [IO.File]::ReadAllText($agents).Contains('My particular rules')) ($r|ConvertTo-Json -Depth 5)
}
Test 'project skills import preserves sources and existing context byte for byte' {
    $f=Fixture;$skill=Join-Path $f.ProjectPath 'skills/personal';[IO.Directory]::CreateDirectory($skill)|Out-Null
    [IO.File]::WriteAllText((Join-Path $skill 'SKILL.md'),'personal fixture');[IO.File]::WriteAllBytes((Join-Path $skill 'attachment.bin'),[byte[]](0,255,1))
    $context=Join-Path $f.ProjectPath '.context';[IO.Directory]::CreateDirectory($context)|Out-Null
    [IO.File]::WriteAllBytes((Join-Path $context 'progress.md'),[byte[]](65,13,10,66))
    $r=Invoke-ProjectMigration @f -Mode Apply
    Assert ($r.Code -eq 0) ($r|ConvertTo-Json -Depth 6)
    Assert (([BitConverter]::ToString([IO.File]::ReadAllBytes((Join-Path $context 'progress.md')))) -eq '41-0D-0A-42') 'Memory changed'
    Assert ((Get-ChildItem $skill -File).Count -eq 2) 'Source changed'
    $cfg=Get-Content $f.ConfigPath -Raw|ConvertFrom-Json
    Assert ((Test-Path (Join-Path $cfg.HubDir 'personal/attachment.bin'))) 'Custom hub was ignored'
}
Test 'invalid configuration and project overlap fail without writes' {
    $f=Fixture;[IO.File]::WriteAllText($f.ConfigPath,'{}')
    Assert ((Invoke-ProjectMigration @f -Mode Apply).Code -eq 1) 'Invalid configuration accepted'
    $f=Fixture;$c=Get-Content $f.ConfigPath -Raw|ConvertFrom-Json;$f.ProjectPath=$c.HubDir
    [IO.Directory]::CreateDirectory($f.ProjectPath)|Out-Null
    Assert ((Invoke-ProjectMigration @f -Mode Apply).Code -eq 1) 'Overlapping project accepted'
}
Test 'conflicting imports are rescued without changing metadata or sources' {
    $f=Fixture;$c=Get-Content $f.ConfigPath -Raw|ConvertFrom-Json
    foreach($root in @($c.HubDir,(Join-Path $f.ProjectPath 'skills'))){$d=Join-Path $root 'demo';[IO.Directory]::CreateDirectory($d)|Out-Null;[IO.File]::WriteAllText((Join-Path $d 'SKILL.md'),$root)}
    $r=Invoke-ProjectMigration @f -Mode Apply
    Assert ($r.Code -eq 2 -and $r.RescueManifest -and -not (Test-Path (Join-Path $f.ProjectPath 'AGENTS.md'))) 'Conflict not rescued safely'
    $manifest=Get-Content $r.RescueManifest -Raw|ConvertFrom-Json
    Assert ($manifest.Complete -and @($manifest.Files|Where-Object {$_.Key -eq 'demo/SKILL.md'}).Count -eq 2) 'Conflict versions missing'
}
Test 'legacy public definitions cannot override the verified catalogue' {
    $f=Fixture;$d=Join-Path $f.ProjectPath 'skills/ops-session-handoff';[IO.Directory]::CreateDirectory($d)|Out-Null
    [IO.File]::WriteAllText((Join-Path $d 'SKILL.md'),'old public definition')
    $r=Invoke-ProjectMigration @f -Mode Apply
    Assert ($r.Code -eq 2 -and @($r.Conflicts|Where-Object {$_.Reason -eq 'ImportedCoreDivergence'}).Count -eq 1) 'Old core was accepted'
}
Test 'metadata failure rolls back unchanged files and keeps completed skill rescue' {
    $f=Fixture;$r=Invoke-ProjectMigration @f -Mode Apply -FaultHook {throw 'simulated interruption'}
    Assert ($r.Code -eq 1 -and $r.Status -eq 'ROLLED_BACK' -and -not (Test-Path (Join-Path $f.ProjectPath 'AGENTS.md'))) ($r|ConvertTo-Json -Depth 4)
    Assert (Test-Path $r.RescueManifest) 'Completed rescue was deleted'
}
Test 'later edits block recovery and remain intact' {
    $f=Fixture;$hook={param($a) [IO.File]::WriteAllText((Join-Path $a.Root $a.Key),'later user edit');throw 'interruption'}
    $r=Invoke-ProjectMigration @f -Mode Apply -FaultHook $hook
    Assert ($r.Code -eq 2 -and $r.Status -eq 'RECOVERY_REVIEW_REQUIRED') 'Concurrent edit was overwritten'
    $first=$r.Actions[0];Assert ([IO.File]::ReadAllText((Join-Path $first.Root $first.Key)) -eq 'later user edit') 'Later edit lost'
    Assert ((Invoke-ProjectMigration @f).Status -eq 'RECOVERY_REQUIRED') 'Pending recovery was hidden'
}
Test 'abrupt process exit is recovered before another migration' {
    $f=Fixture;$c=Get-Content $f.ConfigPath -Raw|ConvertFrom-Json
    $module=(Join-Path $source 'scripts/ProjectMigration.psm1').Replace("'","''");$frame=$c.FrameworkDir.Replace("'","''")
    $body="Import-Module '$module' -Force; Invoke-ProjectMigration -ProjectPath '"+$f.ProjectPath.Replace("'","''")+"' -ConfigPath '"+$f.ConfigPath.Replace("'","''")+"' -Mode Apply -ReleaseResolver { @{Path='$frame';Mode='MANAGED';Sha=('a'*40)} } -FaultHook { [Environment]::Exit(99) }"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
    & (Get-Process -Id $PID).Path -NoProfile -EncodedCommand $encoded|Out-Null
    Assert ($LASTEXITCODE -eq 99) 'Abrupt exit did not reach metadata write'
    $r=Invoke-ProjectMigration @f -Mode Apply
    Assert ($r.Code -eq 0 -and $r.Status -eq 'RECOVERED' -and -not (Test-Path (Join-Path $f.ProjectPath 'AGENTS.md'))) 'Interrupted metadata was not recovered'
    Assert ((Invoke-ProjectMigration @f -Mode Apply).Status -eq 'MIGRATED') 'Recovery prevented a clean retry'
}
Test 'optional commit excludes unrelated work and rejects a dirty index' {
    $f=Fixture;& git init -q -b main $f.ProjectPath
    & git -C $f.ProjectPath config user.name Tests;& git -C $f.ProjectPath config user.email tests@localhost
    [IO.File]::WriteAllText((Join-Path $f.ProjectPath 'unrelated.txt'),'keep local')
    $r=Invoke-ProjectMigration @f -Mode Apply -Commit
    Assert ($r.Code -eq 0 -and $r.Commit) ($r|ConvertTo-Json -Depth 4)
    Assert (-not @(& git -C $f.ProjectPath ls-tree -r --name-only HEAD|Where-Object {$_ -eq 'unrelated.txt'}).Count) 'Unrelated file committed'
    $f=Fixture;& git init -q -b main $f.ProjectPath
    [IO.File]::WriteAllText((Join-Path $f.ProjectPath 'staged.txt'),'staged');& git -C $f.ProjectPath add -- staged.txt
    $r=Invoke-ProjectMigration @f -Mode Apply -Commit
    Assert ($r.Code -eq 1 -and -not (Test-Path (Join-Path $f.ProjectPath 'AGENTS.md'))) 'Dirty index accepted'
}
Test 'a prior edit in an affected tracked file prevents commit before migration writes' {
    $f=Fixture;& git init -q -b main $f.ProjectPath
    & git -C $f.ProjectPath config user.name Tests;& git -C $f.ProjectPath config user.email tests@localhost
    $dir=Join-Path $f.ProjectPath '.context';[IO.Directory]::CreateDirectory($dir)|Out-Null
    $file=Join-Path $dir 'systemPatterns.md';[IO.File]::WriteAllText($file,'original project rules')
    & git -C $f.ProjectPath add -- .context/systemPatterns.md;& git -C $f.ProjectPath commit -q -m fixture
    [IO.File]::WriteAllText($file,'pending user edit')
    $r=Invoke-ProjectMigration @f -Mode Apply -Commit
    Assert ($r.Code -eq 1 -and [IO.File]::ReadAllText($file) -eq 'pending user edit' -and -not (Test-Path (Join-Path $f.ProjectPath 'AGENTS.md'))) 'Prior edit included in migration commit'
}
Test 'an import cannot overlap a registered replica' {
    $f=Fixture;$c=Get-Content $f.ConfigPath -Raw|ConvertFrom-Json
    [IO.Directory]::CreateDirectory($c.Targets[0])|Out-Null
    $r=Invoke-ProjectMigration @f -Mode Apply -ImportSources @($c.Targets[0])
    Assert ($r.Code -eq 1 -and -not (Test-Path (Join-Path $f.ProjectPath 'AGENTS.md'))) 'Import/replica overlap accepted'
}
Write-Host "Migration results: $passed passed, $failed failed. Fixtures: $base"
if($failed){exit 1}
