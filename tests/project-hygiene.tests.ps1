# Project hygiene sensor: reports leftovers in a project and never changes anything.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/ProjectHygiene.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-hygiene-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
function Put($r,$k,$t){$p=Join-Path $r $k;[IO.Directory]::CreateDirectory((Split-Path -Parent $p))|Out-Null;[IO.File]::WriteAllText($p,$t,$utf8);return $p}
function NewDir([string]$n){$d=Join-Path $script:base ($n+'-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($d)|Out-Null;return $d}
function Hub{$h=NewDir 'hub';Put $h 'dev-tdd/SKILL.md' "---`nname: dev-tdd`nversion: 1.2.0`n---`nTDD"|Out-Null;Put $h 'interlude/SKILL.md' 'interlude v3'|Out-Null;return $h}
function GitProject{
    $p=NewDir 'proyecto';& git init -q -b main $p
    & git -C $p config user.name Tests;& git -C $p config user.email tests@localhost;& git -C $p config core.autocrlf false
    Put $p 'AGENTS.md' 'reglas'|Out-Null;Put $p '.context/activeContext.md' 'estado'|Out-Null;Put $p 'app.txt' 'v1'|Out-Null
    & git -C $p add -A;& git -C $p commit -q --no-verify -m base
    return $p
}
function Snapshot($root){@(Get-ChildItem -LiteralPath $root -Recurse -Force -File|Where-Object {$_.FullName -notmatch '\\\.git\\'}|ForEach-Object {"$($_.FullName)|$($_.Length)|$($_.LastWriteTimeUtc.Ticks)"})|Sort-Object}

Test 'a tidy project reports nothing' {
    $r=Get-AgentOpsProjectHygiene -ProjectPath (GitProject) -HubDir (Hub)
    Assert ($r.Code -eq 0 -and $r.Status -eq 'CLEAN' -and -not @($r.Findings).Count) ($r|ConvertTo-Json -Depth 5)
}
Test 'copies of hub skills inside the project are reported, telling identical from different ones' {
    $h=Hub;$p=GitProject
    Copy-Item (Join-Path $h 'dev-tdd') (Join-Path $p 'skills/dev-tdd') -Recurse
    Put $p 'skills/interlude/SKILL.md' 'interlude v1 (antigua)'|Out-Null
    Put $p 'skills/propia/SKILL.md' 'solo de este proyecto'|Out-Null
    $r=Get-AgentOpsProjectHygiene -ProjectPath $p -HubDir $h
    $f=@($r.Findings|Where-Object {$_.Kind -eq 'skills-copy'})
    Assert ($r.Status -eq 'FINDINGS' -and $f.Count -eq 1) ($r|ConvertTo-Json -Depth 5)
    Assert ($f[0].Identical -contains 'dev-tdd' -and $f[0].Different -contains 'interlude' -and $f[0].Identical -notcontains 'propia' -and $f[0].Different -notcontains 'propia') ($f|ConvertTo-Json -Depth 5)
    Assert ($f[0].Message -match '2' -and $f[0].Fix) ($f|ConvertTo-Json -Depth 5)
}
Test 'old provisional files are reported; recent ones are not' {
    $p=GitProject
    $old=Put $p 'scratch/prueba-vieja.txt' 'x';(Get-Item $old).LastWriteTime=(Get-Date).AddDays(-10)
    Put $p 'scratch/hoy.txt' 'y'|Out-Null
    $r=Get-AgentOpsProjectHygiene -ProjectPath $p -HubDir (Hub)
    $f=@($r.Findings|Where-Object {$_.Kind -eq 'old-scratch'})
    Assert ($f.Count -eq 1 -and $f[0].Paths -contains 'scratch/prueba-vieja.txt' -and $f[0].Paths -notcontains 'scratch/hoy.txt') ($r|ConvertTo-Json -Depth 5)
    Assert ($f[0].Message -match '^Hay 1 archivo provisional con') "Singular expected: $($f[0].Message)"
}
Test 'governance files not saved in history are reported' {
    $p=GitProject;Put $p 'AGENTS.md' 'reglas nuevas'|Out-Null
    $one=@((Get-AgentOpsProjectHygiene -ProjectPath $p -HubDir (Hub)).Findings|Where-Object {$_.Kind -eq 'unsaved-governance'})
    Assert ($one[0].Message -match '^Hay 1 archivo de gobernanza sin guardar') "Singular expected: $($one[0].Message)"
    Put $p 'CHANGELOG.md' '# Changelog'|Out-Null
    $r=Get-AgentOpsProjectHygiene -ProjectPath $p -HubDir (Hub)
    $f=@($r.Findings|Where-Object {$_.Kind -eq 'unsaved-governance'})
    Assert ($f.Count -eq 1 -and $f[0].Paths -contains 'AGENTS.md' -and $f[0].Paths -contains 'CHANGELOG.md') ($r|ConvertTo-Json -Depth 5)
}
Test 'governance that the project deliberately ignores is not reported' {
    $p=GitProject;Put $p '.gitignore' "/.context/`n"|Out-Null;& git -C $p add .gitignore;& git -C $p rm -q -r --cached .context;& git -C $p commit -q --no-verify -m ignore
    Put $p '.context/activeContext.md' 'estado nuevo'|Out-Null
    $r=Get-AgentOpsProjectHygiene -ProjectPath $p -HubDir (Hub)
    Assert (-not @($r.Findings|Where-Object {$_.Kind -eq 'unsaved-governance'}).Count) ($r|ConvertTo-Json -Depth 5)
}
Test 'a project without Git only skips the governance check' {
    $p=NewDir 'sin-git';Put $p 'AGENTS.md' 'x'|Out-Null
    $old=Put $p 'tmp/viejo.log' 'x';(Get-Item $old).LastWriteTime=(Get-Date).AddDays(-30)
    $r=Get-AgentOpsProjectHygiene -ProjectPath $p -HubDir (Hub)
    Assert ($r.Code -eq 0 -and @($r.Findings|Where-Object {$_.Kind -eq 'old-scratch'}).Count -eq 1 -and -not @($r.Findings|Where-Object {$_.Kind -eq 'unsaved-governance'}).Count) ($r|ConvertTo-Json -Depth 5)
}
Test 'the framework repository is not told to remove its own skills' {
    $h=Hub;$p=GitProject;Put $p 'release-contract.json' '{}'|Out-Null;Put $p 'scripts/harness-capabilities.json' '{}'|Out-Null
    Copy-Item (Join-Path $h 'dev-tdd') (Join-Path $p 'skills/dev-tdd') -Recurse
    & git -C $p add -A;& git -C $p commit -q --no-verify -m fw
    $r=Get-AgentOpsProjectHygiene -ProjectPath $p -HubDir $h
    Assert (-not @($r.Findings|Where-Object {$_.Kind -eq 'skills-copy'}).Count) ($r|ConvertTo-Json -Depth 5)
}
Test 'the sensor never changes anything in the project' {
    $h=Hub;$p=GitProject;Copy-Item (Join-Path $h 'dev-tdd') (Join-Path $p 'skills/dev-tdd') -Recurse
    $old=Put $p 'scratch/x.txt' 'x';(Get-Item $old).LastWriteTime=(Get-Date).AddDays(-10);Put $p 'AGENTS.md' 'cambio'|Out-Null
    $before=Snapshot $p;$status=(& git -C $p status --porcelain)
    $r=Get-AgentOpsProjectHygiene -ProjectPath $p -HubDir $h
    Assert (@($r.Findings).Count -eq 3) ($r|ConvertTo-Json -Depth 5)
    Assert (((Snapshot $p) -join "`n") -eq ($before -join "`n") -and ((& git -C $p status --porcelain) -join "`n") -eq ($status -join "`n")) 'The sensor changed the project'
}
Test 'findings come with plain-language lines for the session report' {
    $h=Hub;$p=GitProject;Copy-Item (Join-Path $h 'dev-tdd') (Join-Path $p 'skills/dev-tdd') -Recurse
    $r=Get-AgentOpsProjectHygiene -ProjectPath $p -HubDir $h
    Assert (@($r.Lines).Count -eq 1 -and $r.Lines[0] -match 'skill' -and $r.Lines[0] -notmatch 'Kind|skills-copy') ($r|ConvertTo-Json -Depth 5)
}
Test 'the entry script returns JSON with code 0 even when there are findings' {
    $h=Hub;$p=GitProject;Put $p 'AGENTS.md' 'cambio'|Out-Null
    $engine=(Get-Process -Id $PID).Path
    $json=& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/project-hygiene.ps1') -ProjectPath $p -HubDir $h|Out-String
    Assert ($LASTEXITCODE -eq 0 -and ($json|ConvertFrom-Json).Status -eq 'FINDINGS') $json
}
Test 'backup and unreferenced files are reported while node_modules and sql migrations are ignored' {
    $h=Hub;$p=GitProject
    Put $p '.gitignore' "web/dump.sql`n"|Out-Null;& git -C $p add .gitignore;& git -C $p commit -q --no-verify -m ig
    Put $p 'config.bak' 'x'|Out-Null
    Put $p 'web/dump.sql' 'SELECT 1;'|Out-Null
    Put $p 'migrations/001_init.sql' 'CREATE TABLE t(id int);'|Out-Null
    Put $p 'node_modules/pkg/test.bak' 'x'|Out-Null
    $r=Get-AgentOpsProjectHygiene -ProjectPath $p -HubDir $h
    $f=@($r.Findings|Where-Object {$_.Kind -eq 'backup-or-unreferenced'})
    Assert ($r.Status -eq 'FINDINGS' -and $f.Count -eq 1) ($r|ConvertTo-Json -Depth 5)
    Assert (@($f[0].Paths) -contains 'config.bak' -and @($f[0].Paths) -contains 'web/dump.sql') ($f|ConvertTo-Json -Depth 5)
    Assert (@($f[0].Paths) -notcontains 'migrations/001_init.sql' -and @($f[0].Paths) -notcontains 'node_modules/pkg/test.bak') ($f|ConvertTo-Json -Depth 5)
}
Test 'excessive Codex turn-diff references are reported in read-only mode' {
    $h=Hub;$p=GitProject
    $sha=(& git -C $p rev-parse HEAD).Trim()
    foreach($i in 1..26){
        Put $p ".git/refs/codex/turn-diffs/checkpoints/c-$i" "$sha`n"|Out-Null
    }
    $r=Get-AgentOpsProjectHygiene -ProjectPath $p -HubDir $h
    $f=@($r.Findings|Where-Object {$_.Kind -eq 'codex-turn-diffs'})
    Assert ($r.Status -eq 'FINDINGS' -and $f.Count -eq 1 -and $f[0].Message -match '26') ($r|ConvertTo-Json -Depth 5)
}
Write-Host "Project hygiene: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
