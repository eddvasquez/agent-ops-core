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
    Assert ($r.Code -eq 0 -and $r.Actions.Count -eq 9 -and -not (Test-Path (Join-Path $f.ProjectPath 'AGENTS.md'))) 'Plan wrote files'
    Assert (@($r.Actions|Where-Object {$_.Key -eq '.context/agent-ops.json'}).Count -eq 1) 'Plan does not record the framework version'
    Assert (@($r.Actions|Where-Object {$_.Key -eq '.context/reglas_proyecto.md'}).Count -eq 1) 'Plan does not create the project rules registry'
    Assert (@($r.Actions|Where-Object {$_.Key -eq 'CHANGELOG.md'}).Count -eq 1) 'Plan does not create CHANGELOG.md'
    Invoke-ProjectMigration @f -Mode Apply -WhatIf|Out-Null
    Assert (-not (Test-Path (Join-Path (Split-Path $f.ConfigPath) 'migrations'))) 'WhatIf wrote private state'
    $r=Invoke-ProjectMigration @f -Mode Apply
    Assert ($r.Code -eq 0 -and (Test-Path (Join-Path $f.ProjectPath '.context/progress.md'))) ($r|ConvertTo-Json -Depth 5)
    $again=Invoke-ProjectMigration @f -Mode Apply
    Assert ($again.Code -eq 0 -and $again.Actions.Count -eq 0) 'Repeat rewrote project'
}
Test 'an existing CHANGELOG.md is preserved byte for byte' {
    $f=Fixture;$log=Join-Path $f.ProjectPath 'CHANGELOG.md';[IO.File]::WriteAllBytes($log,[byte[]](35,13,10,88))
    $r=Invoke-ProjectMigration @f -Mode Apply
    Assert ($r.Code -eq 0 -and @($r.Actions|Where-Object {$_.Key -eq 'CHANGELOG.md'}).Count -eq 0) ($r|ConvertTo-Json -Depth 5)
    Assert (([BitConverter]::ToString([IO.File]::ReadAllBytes($log))) -eq '23-0D-0A-58') 'Existing changelog changed'
}
Test 'an existing project rules registry is preserved byte for byte' {
    $f=Fixture;$context=Join-Path $f.ProjectPath '.context';[IO.Directory]::CreateDirectory($context)|Out-Null
    $rules=Join-Path $context 'reglas_proyecto.md';[IO.File]::WriteAllBytes($rules,[byte[]](82,13,10,49))
    $r=Invoke-ProjectMigration @f -Mode Apply
    Assert ($r.Code -eq 0 -and @($r.Actions|Where-Object {$_.Key -eq '.context/reglas_proyecto.md'}).Count -eq 0) ($r|ConvertTo-Json -Depth 5)
    Assert (([BitConverter]::ToString([IO.File]::ReadAllBytes($rules))) -eq '52-0D-0A-31') 'Existing rules changed'
}
Test 'existing rules require a reviewed candidate and an unchanged original hash' {
    $f=Fixture;$agents=Join-Path $f.ProjectPath 'AGENTS.md';[IO.File]::WriteAllText($agents,'My particular rules')
    $p=Invoke-ProjectMigration @f
    Assert ($p.Code -eq 2 -and $p.Status -eq 'AGENTS_REVIEW_REQUIRED') 'Rules replaced without review'
    Assert ($p.AgentsProposal -and $p.AgentsProposal.Contains('My particular rules') -and $p.AgentsProposal.Contains('agent-ops:begin')) 'No proposal that keeps the project rules'
    $candidate=Join-Path (Split-Path $f.ConfigPath) 'candidate.md';[IO.File]::WriteAllText($candidate,$p.AgentsProposal)
    [IO.File]::WriteAllText($agents,'Later user edit')
    $r=Invoke-ProjectMigration @f -Mode Apply -AgentsCandidatePath $candidate -ExpectedAgentsHash $p.AgentsHash
    Assert ($r.Code -eq 2 -and [IO.File]::ReadAllText($agents) -eq 'Later user edit') 'Stale candidate overwrote later edit'
    [IO.File]::WriteAllText($agents,'My particular rules')
    $p=Invoke-ProjectMigration @f
    $r=Invoke-ProjectMigration @f -Mode Apply -AgentsCandidatePath $candidate -ExpectedAgentsHash $p.AgentsHash
    Assert ($r.Code -eq 0 -and [IO.File]::ReadAllText($agents).Contains('My particular rules')) ($r|ConvertTo-Json -Depth 5)
}
function Block([string]$body,[string]$version='0.9.0'){
    $b=($body -replace "`r",'').TrimEnd()
    $h=[Security.Cryptography.SHA256]::Create();try{$hash=([BitConverter]::ToString($h.ComputeHash([Text.Encoding]::UTF8.GetBytes($b)))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}
    return "<!-- agent-ops:begin version=$version hash=$hash -->`n$b`n<!-- agent-ops:end -->"
}
function Snapshot($root){
    $map=@{};foreach($file in Get-ChildItem -LiteralPath $root -Recurse -File -Force|Where-Object {$_.FullName -notmatch '\\\.git\\'}){$map[$file.FullName.Substring($root.Length)]=(Get-FileHash -LiteralPath $file.FullName).Hash};return $map
}
function Same($a,$b){(@($a.Keys)+@($b.Keys)|Sort-Object -Unique|Where-Object {$a[$_] -ne $b[$_]}).Count -eq 0}
Test 'a new AGENTS.md is a managed block and the framework version is recorded' {
    $f=Fixture;$r=Invoke-ProjectMigration @f -Mode Apply
    $text=[IO.File]::ReadAllText((Join-Path $f.ProjectPath 'AGENTS.md'))
    Assert ($r.Code -eq 0 -and $text -match '<!-- agent-ops:begin version=\S* hash=[a-f0-9]{64} -->' -and $text.Contains('<!-- agent-ops:end -->')) $text
    $reg=Get-Content (Join-Path $f.ProjectPath '.context/agent-ops.json') -Raw|ConvertFrom-Json
    Assert ($reg.FrameworkSha -eq ('a'*40) -and $reg.TemplateHash -match '^[a-f0-9]{64}$') ($reg|ConvertTo-Json)
}
Test 'an unedited managed block is updated automatically and the text outside it is kept byte for byte' {
    $f=Fixture;$agents=Join-Path $f.ProjectPath 'AGENTS.md'
    $before="# Reglas de Kavan`r`n- No afirmar rentabilidad garantizada.`r`n`r`n"
    $after="`r`n`r`n## Notas propias`r`n- Tutear siempre.`r`n"
    [IO.File]::WriteAllText($agents,$before+(Block 'Protocolos antiguos del marco')+$after)
    $r=Invoke-ProjectMigration @f -Mode Apply
    $text=[IO.File]::ReadAllText($agents)
    Assert ($r.Code -eq 0 -and $text.StartsWith($before) -and $text.EndsWith($after)) ($r|ConvertTo-Json -Depth 4)
    Assert ($text.Contains('Protocolo 8') -and -not $text.Contains('Protocolos antiguos del marco')) 'Block not updated'
}
Test 'an edited managed block requires review and writes nothing' {
    $f=Fixture;$agents=Join-Path $f.ProjectPath 'AGENTS.md'
    $edited=(Block 'Protocolos antiguos').Replace('Protocolos antiguos','Protocolos antiguos con una regla mia')
    [IO.File]::WriteAllText($agents,$edited);$hash=(Get-FileHash $agents).Hash
    $r=Invoke-ProjectMigration @f -Mode Apply
    Assert ($r.Code -eq 2 -and $r.Status -eq 'AGENTS_REVIEW_REQUIRED' -and (Get-FileHash $agents).Hash -eq $hash) ($r|ConvertTo-Json -Depth 4)
    Assert ($r.AgentsProposal.Contains('Protocolos antiguos con una regla mia')) 'Proposal dropped the edit'
}
Test 'a legacy AGENTS.md made only of framework template text is converted automatically' {
    $f=Fixture;$agents=Join-Path $f.ProjectPath 'AGENTS.md'
    $legacy=(& git -C $source show '57172b5:templates/AGENTS.md') -join "`n"
    [IO.File]::WriteAllText($agents,$legacy+"`n`n<!-- AgentOps migration: "+('b'*64)+" -->`n")
    $r=Invoke-ProjectMigration @f -Mode Apply
    $text=[IO.File]::ReadAllText($agents)
    Assert ($r.Code -eq 0 -and $text.Contains('agent-ops:begin') -and -not $text.Contains('AgentOps migration:')) ($r|ConvertTo-Json -Depth 4)
}
Test 'a candidate that drops a project rule is refused unless the removal was approved' {
    $f=Fixture;$agents=Join-Path $f.ProjectPath 'AGENTS.md'
    [IO.File]::WriteAllText($agents,"Regla propia: nunca mencionar la piscina.`nOtra regla propia.")
    $p=Invoke-ProjectMigration @f
    $block=$p.AgentsProposal.Substring(0,$p.AgentsProposal.IndexOf('<!-- agent-ops:end -->')+'<!-- agent-ops:end -->'.Length)
    $candidate=Join-Path (Split-Path $f.ConfigPath) 'drop.md';[IO.File]::WriteAllText($candidate,$block+"`n`nOtra regla propia.`n")
    $r=Invoke-ProjectMigration @f -Mode Apply -AgentsCandidatePath $candidate -ExpectedAgentsHash $p.AgentsHash
    Assert ($r.Code -eq 2 -and $r.Status -eq 'AGENTS_RULES_MISSING' -and ($r.MissingLines -join '|') -match 'piscina') ($r|ConvertTo-Json -Depth 4)
    Assert ([IO.File]::ReadAllText($agents).Contains('piscina')) 'File changed after refusal'
    $approved=Join-Path (Split-Path $f.ConfigPath) 'approved.txt';[IO.File]::WriteAllText($approved,'Regla propia: nunca mencionar la piscina.')
    $r=Invoke-ProjectMigration @f -Mode Apply -AgentsCandidatePath $candidate -ExpectedAgentsHash $p.AgentsHash -ApprovedRemovalsPath $approved
    Assert ($r.Code -eq 0 -and -not [IO.File]::ReadAllText($agents).Contains('piscina')) ($r|ConvertTo-Json -Depth 4)
}
Test 'a candidate without the current managed block is refused' {
    $f=Fixture;$agents=Join-Path $f.ProjectPath 'AGENTS.md';[IO.File]::WriteAllText($agents,'Regla propia.')
    $p=Invoke-ProjectMigration @f
    $candidate=Join-Path (Split-Path $f.ConfigPath) 'noblock.md';[IO.File]::WriteAllText($candidate,"Regla propia.`nops-session-handoff MODO ENTRADA start-session.ps1")
    $r=Invoke-ProjectMigration @f -Mode Apply -AgentsCandidatePath $candidate -ExpectedAgentsHash $p.AgentsHash
    Assert ($r.Code -ne 0 -and [IO.File]::ReadAllText($agents) -eq 'Regla propia.') ($r|ConvertTo-Json -Depth 4)
}
Test 'Plan says whether the project is up to date, and Defer silences the offer for this template only' {
    $f=Fixture
    $p=Invoke-ProjectMigration @f
    Assert ($p.UpToDate -eq $false -and $p.Deferred -eq $false) ($p|ConvertTo-Json -Depth 3)
    $d=Invoke-ProjectMigration @f -Mode Defer
    Assert ($d.Code -eq 0 -and $d.Status -eq 'DEFERRED') ($d|ConvertTo-Json -Depth 3)
    Assert (-not (Test-Path (Join-Path $f.ProjectPath 'AGENTS.md')) -and -not (Test-Path (Join-Path $f.ProjectPath '.context'))) 'Defer wrote into the project'
    Assert ((Invoke-ProjectMigration @f).Deferred -eq $true) 'Deferral not remembered'
    $r=Invoke-ProjectMigration @f -Mode Apply
    $p=Invoke-ProjectMigration @f
    Assert ($r.Code -eq 0 -and $p.UpToDate -eq $true -and $p.Actions.Count -eq 0) ($p|ConvertTo-Json -Depth 3)
}
Test 'git projects get a restore point at the pre-migration HEAD' {
    $f=Fixture;& git init -q -b main $f.ProjectPath
    & git -C $f.ProjectPath config user.name Tests;& git -C $f.ProjectPath config user.email tests@localhost
    [IO.File]::WriteAllText((Join-Path $f.ProjectPath 'code.txt'),'v1');& git -C $f.ProjectPath add -- code.txt;& git -C $f.ProjectPath commit -q -m base
    $head=(& git -C $f.ProjectPath rev-parse HEAD).Trim()
    $r=Invoke-ProjectMigration @f -Mode Apply
    Assert ($r.Code -eq 0 -and $r.RestoreRef -match '^refs/agent-ops/pre-migration/') ($r|ConvertTo-Json -Depth 4)
    Assert ((& git -C $f.ProjectPath rev-parse $r.RestoreRef).Trim() -eq $head) 'Restore point does not match HEAD'
}
Test 'rollback returns every file of the project to its exact previous state' {
    $f=Fixture;$ctx=Join-Path $f.ProjectPath '.context';[IO.Directory]::CreateDirectory($ctx)|Out-Null
    [IO.File]::WriteAllText((Join-Path $ctx 'systemPatterns.md'),'patrones propios')
    [IO.File]::WriteAllText((Join-Path $f.ProjectPath 'landing.html'),'<h1>Kavan</h1>')
    $before=Snapshot $f.ProjectPath
    $r=Invoke-ProjectMigration @f -Mode Apply
    Assert ($r.Code -eq 0 -and $r.JournalId) ($r|ConvertTo-Json -Depth 4)
    $back=Invoke-ProjectMigration @f -Mode Rollback -Journal $r.JournalId
    Assert ($back.Code -eq 0 -and $back.Status -eq 'ROLLED_BACK') ($back|ConvertTo-Json -Depth 4)
    Assert (Same $before (Snapshot $f.ProjectPath)) 'Project not restored byte for byte'
}
Test 'rollback refuses when a migrated file was edited afterwards and changes nothing' {
    $f=Fixture;$r=Invoke-ProjectMigration @f -Mode Apply
    $rules=Join-Path $f.ProjectPath '.context/reglas_proyecto.md';[IO.File]::AppendAllText($rules,"`n### R-001 [tono] [ámbito: todas] [estado: activa]`n- Regla: nueva")
    $snap=Snapshot $f.ProjectPath
    $back=Invoke-ProjectMigration @f -Mode Rollback -Journal $r.JournalId
    Assert ($back.Code -eq 2 -and $back.Status -eq 'ROLLBACK_REVIEW_REQUIRED') ($back|ConvertTo-Json -Depth 4)
    Assert (Same $snap (Snapshot $f.ProjectPath)) 'Rollback changed files despite a later edit'
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
Test 'other harness instruction files are inventoried as candidate rules and never modified' {
    $f=Fixture
    [IO.File]::WriteAllText((Join-Path $f.ProjectPath 'CLAUDE.md'),"# Notes`n`nNunca usar comillas tipográficas`n")
    [IO.File]::WriteAllText((Join-Path $f.ProjectPath '.cursorrules'),"Responder siempre en español")
    $gh=Join-Path $f.ProjectPath '.github';[IO.Directory]::CreateDirectory($gh)|Out-Null
    [IO.File]::WriteAllText((Join-Path $gh 'copilot-instructions.md'),"Usar PowerShell 5.1")
    $before=Snapshot $f.ProjectPath
    $r=Invoke-ProjectMigration @f
    Assert (Same $before (Snapshot $f.ProjectPath)) 'Plan modified harness files'
    $files=@($r.HarnessInstructions|ForEach-Object {$_.File})
    Assert ($files -contains 'CLAUDE.md' -and $files -contains '.cursorrules' -and $files -contains '.github/copilot-instructions.md') ('Missing inventory: '+($files -join ','))
    $claude=@($r.HarnessInstructions|Where-Object {$_.File -eq 'CLAUDE.md'})[0]
    Assert (@($claude.Lines) -contains 'Nunca usar comillas tipográficas') 'Own line not extracted'
    Assert (@($r.Actions|Where-Object {$_.Key -match 'CLAUDE|cursor|copilot'}).Count -eq 0) 'Harness file scheduled for writing'
    $r=Invoke-ProjectMigration @f -Mode Apply
    Assert ($r.Code -eq 0 -and [IO.File]::ReadAllText((Join-Path $f.ProjectPath '.cursorrules')) -eq 'Responder siempre en español') 'Apply touched harness file'
}
Test 'a project without harness instruction files reports an empty inventory' {
    $f=Fixture;$r=Invoke-ProjectMigration @f
    Assert (@($r.HarnessInstructions).Count -eq 0) 'Phantom harness inventory'
}
Write-Host "Migration results: $passed passed, $failed failed. Fixtures: $base"
if($failed){exit 1}
