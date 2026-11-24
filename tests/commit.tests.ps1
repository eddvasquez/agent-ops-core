# Safe commit/tag tool for agents. All repositories below are temporary fixtures.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/AgentOpsCommit.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-commit-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
function Repo([switch]$Unborn){
    $r=Join-Path $script:base ('Kavan - Villas de Toskana '+[guid]::NewGuid().ToString('N').Substring(0,6))
    [IO.Directory]::CreateDirectory($r)|Out-Null
    & git init -q -b main $r
    & git -C $r config user.name 'Tests'
    & git -C $r config user.email 'tests@localhost'
    & git -C $r config core.autocrlf false
    if(-not $Unborn){
        [IO.File]::WriteAllText((Join-Path $r 'base.txt'),'base',$utf8)
        & git -C $r add -- base.txt
        & git -C $r commit -q -m base
    }
    return $r
}
function Put($r,$k,$t){$p=Join-Path $r $k;[IO.Directory]::CreateDirectory((Split-Path -Parent $p))|Out-Null;[IO.File]::WriteAllText($p,$t,$utf8)}
function Head($r){(& git -C $r rev-parse HEAD).Trim()}
$tricky="fix(landing): quitar ""inversión segura"" y `$100 del hero`nSegunda línea con 'comillas simples', `$env:PATH, % y ``backticks``.`n`nPárrafo final: ñ, á, é, ü."

Test 'a message with quotes, accents, dollars, backticks and lines arrives byte for byte' {
    $r=Repo;Put $r 'a.md' 'x'
    $res=Invoke-AgentOpsCommit -RepositoryPath $r -Paths @('a.md') -Message $tricky
    Assert ($res.Code -eq 0 -and $res.Status -eq 'COMMITTED') ($res|ConvertTo-Json -Depth 5)
    $body=(& git -C $r -c i18n.logOutputEncoding=UTF-8 log -1 --format=%B) -join "`n"
    $raw=[Text.Encoding]::UTF8.GetString([Text.Encoding]::Default.GetBytes($body))
    $got=if($body.TrimEnd() -eq $tricky.TrimEnd()){$body}else{$raw}
    Assert ($got.TrimEnd() -eq $tricky.TrimEnd()) "Message changed:`n$body"
    Assert ($res.Sha -eq (Head $r)) 'Reported SHA is not HEAD'
}
Test 'the tag is created on the new commit, never on the previous one' {
    $r=Repo;$old=Head $r;Put $r 'b.md' 'x'
    $res=Invoke-AgentOpsCommit -RepositoryPath $r -Paths @('b.md') -Message $tricky -Tag 'v9.9.9' -TagMessage 'Release "9.9.9"'
    Assert ($res.Code -eq 0 -and $res.Status -eq 'TAGGED') ($res|ConvertTo-Json -Depth 5)
    $tagged=(& git -C $r rev-parse 'v9.9.9^{commit}').Trim()
    Assert ($tagged -eq (Head $r) -and $tagged -ne $old) 'Tag does not point to the new commit'
}
Test 'when the commit fails no tag is created and the code is not zero' {
    $r=Repo
    $res=Invoke-AgentOpsCommit -RepositoryPath $r -Paths @('base.txt') -Message 'nothing changed' -Tag 'v1.0.0'
    Assert ($res.Code -ne 0 -and $res.Step) ($res|ConvertTo-Json -Depth 5)
    Assert (-not (& git -C $r tag --list 'v1.0.0')) 'Tag created after a failed commit'
}
Test 'a pre-commit hook rejection stops before tagging' {
    $r=Repo;Put $r 'c.md' 'x'
    Put $r '.git/hooks/pre-commit' "#!/bin/sh`nexit 1`n"
    $res=Invoke-AgentOpsCommit -RepositoryPath $r -Paths @('c.md') -Message 'm' -Tag 'v2.0.0'
    Assert ($res.Code -ne 0 -and $res.Step -eq 'commit') ($res|ConvertTo-Json -Depth 5)
    Assert (-not (& git -C $r tag --list 'v2.0.0')) 'Tag created after hook rejection'
}
Test 'foreign files already staged are refused without committing' {
    $r=Repo;$old=Head $r;Put $r 'mine.md' 'x';Put $r 'other.md' 'y'
    & git -C $r add -- other.md
    $res=Invoke-AgentOpsCommit -RepositoryPath $r -Paths @('mine.md') -Message 'm'
    Assert ($res.Code -ne 0 -and $res.Step -eq 'index') ($res|ConvertTo-Json -Depth 5)
    Assert ((Head $r) -eq $old) 'Committed despite foreign staged files'
}
Test 'only the requested paths are committed' {
    $r=Repo;Put $r 'keep.md' 'x';Put $r 'leave.md' 'y'
    $res=Invoke-AgentOpsCommit -RepositoryPath $r -Paths @('keep.md') -Message 'm'
    Assert ($res.Code -eq 0) ($res|ConvertTo-Json -Depth 5)
    $files=@(& git -C $r diff-tree --no-commit-id --name-only -r HEAD)
    Assert ($files.Count -eq 1 -and $files[0] -eq 'keep.md') ($files -join ',')
    Assert ((& git -C $r status --porcelain) -match 'leave.md') 'Unrequested file was touched'
}
Test 'a versioning failure undoes the commit and keeps the changes staged' {
    $r=Repo
    Put $r 'docs/CHANGELOG.md' "# Changelog`n`n## [Unreleased]`n`n## [1.0.0] - 2026-11-19`n- base`n"
    Put $r 'docs/VERSION' '1.0.0'
    & git -C $r add -- docs;& git -C $r commit -q -m docs
    $old=Head $r;Put $r 'src.ps1' 'x'
    $res=Invoke-AgentOpsCommit -RepositoryPath $r -Paths @('src.ps1') -Message 'undocumented change'
    Assert ($res.Code -ne 0 -and $res.Step -eq 'versioning') ($res|ConvertTo-Json -Depth 5)
    Assert ((Head $r) -eq $old) 'Commit kept despite versioning failure'
    Assert ((& git -C $r diff --cached --name-only) -contains 'src.ps1') 'Changes were lost'
}
Test 'the first commit of an empty repository works' {
    $r=Repo -Unborn;Put $r 'first.md' 'x'
    $res=Invoke-AgentOpsCommit -RepositoryPath $r -Paths @('first.md') -Message 'first'
    Assert ($res.Code -eq 0 -and $res.Sha -eq (Head $r)) ($res|ConvertTo-Json -Depth 5)
}
Test 'an existing tag is never moved' {
    $r=Repo;& git -C $r tag -a 'v1.0.0' -m 'old';$before=(& git -C $r rev-parse 'v1.0.0^{commit}').Trim()
    Put $r 'd.md' 'x'
    $res=Invoke-AgentOpsCommit -RepositoryPath $r -Paths @('d.md') -Message 'm' -Tag 'v1.0.0'
    Assert ($res.Code -ne 0 -and $res.Step -eq 'tag') ($res|ConvertTo-Json -Depth 5)
    Assert ((& git -C $r rev-parse 'v1.0.0^{commit}').Trim() -eq $before) 'Existing tag moved'
}
Test 'deleted and renamed paths are committed' {
    $r=Repo;& git -C $r mv base.txt moved.txt
    & git -C $r reset -q
    $res=Invoke-AgentOpsCommit -RepositoryPath $r -Paths @('base.txt','moved.txt') -Message 'rename'
    Assert ($res.Code -eq 0) ($res|ConvertTo-Json -Depth 5)
    Assert (-not (& git -C $r ls-files base.txt) -and (& git -C $r ls-files moved.txt)) 'Rename not committed'
}
Test 'CLI reads the message from a file and returns JSON with the exit code' {
    $r=Repo;Put $r 'e.md' 'x';$msg=Join-Path $script:base ('msg-'+[guid]::NewGuid().ToString('N')+'.txt')
    [IO.File]::WriteAllText($msg,$tricky,$utf8)
    $engine=(Get-Process -Id $PID).Path
    $json=& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/commit.ps1') -RepositoryPath $r -Paths 'e.md' -MessageFile $msg|Out-String
    Assert ($LASTEXITCODE -eq 0 -and ($json|ConvertFrom-Json).Status -eq 'COMMITTED') $json
}
Test 'CLI through powershell -File accepts several comma-separated paths' {
    $r=Repo;Put $r 'f1.md' 'x';Put $r 'dir with space/f2.md' 'y'
    $engine=(Get-Process -Id $PID).Path
    $json=& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/commit.ps1') -RepositoryPath $r -Paths 'f1.md,dir with space/f2.md' -Message 'two paths'|Out-String
    Assert ($LASTEXITCODE -eq 0 -and @(($json|ConvertFrom-Json).Files).Count -eq 2) $json
}
Write-Host "Commit tool: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
