[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/UpdateCoordinator.psm1') -Force
$root=Join-Path ([IO.Path]::GetTempPath()) ('aoc-policy-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($root)|Out-Null
Copy-Item -LiteralPath (Join-Path $source 'scripts') -Destination $root -Recurse
Copy-Item -LiteralPath (Join-Path $source 'release-contract.json') -Destination $root
foreach($name in @('dev-systematic-debugging','dev-tdd','ops-git-worktrees','ops-project-init','ops-project-migrate','ops-session-handoff')){
    $dir=Join-Path $root "skills/$name";[IO.Directory]::CreateDirectory($dir)|Out-Null;[IO.File]::WriteAllText((Join-Path $dir 'SKILL.md'),'public fixture')
}
& git init -q -b main $root
& git -C $root -c core.autocrlf=false add .
& git -C $root -c user.name=Tests -c user.email=tests@localhost commit -q -m public
$good=git -C $root rev-parse HEAD
$r=Get-AgentOpsReleasePolicy -RepositoryPath $root -Commit $good
if($r.Code -ne 0 -or $r.SkillDefinitions -ne 6){throw ('Valid public package rejected: '+($r.Issues -join '; '))}
Write-Host 'PASS release policy accepts exactly the six public definitions'
$engine=(Get-Process -Id $PID).Path
$entry=Join-Path $root 'scripts/check-release.ps1'
$json=& $engine -NoProfile -ExecutionPolicy Bypass -File $entry -Commit $good|Out-String
if($LASTEXITCODE -ne 0 -or ($json|ConvertFrom-Json).SkillDefinitions -ne 6){throw 'Standalone release CLI failed to resolve its own repository'}
Write-Host 'PASS standalone release CLI resolves its repository without caller scope'
$private=Join-Path $root 'skills/private-fixture';[IO.Directory]::CreateDirectory($private)|Out-Null
[IO.File]::WriteAllText((Join-Path $private 'SKILL.md'),'private fixture')
& git -C $root add .
& git -C $root -c user.name=Tests -c user.email=tests@localhost commit -q -m private
if((Get-AgentOpsReleasePolicy -RepositoryPath $root -Commit HEAD).Code -eq 0){throw 'Private skill accepted'}
Write-Host 'PASS release policy rejects an extra private skill'
# Create a separate clean commit from the approved tree; no reset/delete needed.
& git -C $root checkout -q -b secrets-test $good
[IO.File]::WriteAllText((Join-Path $root 'scripts/github-token.env'),'dummy fixture value')
& git -C $root add -- scripts/github-token.env
& git -C $root -c user.name=Tests -c user.email=tests@localhost commit -q -m secret
if((Get-AgentOpsReleasePolicy -RepositoryPath $root -Commit HEAD).Code -eq 0){throw 'Credential file accepted'}
Write-Host 'PASS release policy rejects credential/configuration files'
& git -C $root checkout -q -b link-test $good
$blob=('outside-fixture'|git -C $root hash-object -w --stdin)
& git -C $root update-index --add --cacheinfo "120000,$blob,scripts/link"
& git -C $root -c user.name=Tests -c user.email=tests@localhost commit -q -m link
if((Get-AgentOpsReleasePolicy -RepositoryPath $root -Commit HEAD).Code -eq 0){throw 'Symbolic link accepted'}
Write-Host 'PASS release policy rejects links without following them'
& git -C $root checkout -q -b versioning-test $good
[IO.File]::WriteAllText((Join-Path $root 'CHANGELOG.md'),"# Changelog`n`n## [Unreleased]`n")
[IO.File]::WriteAllText((Join-Path $root 'VERSION'),'1.0.0')
[IO.Directory]::CreateDirectory((Join-Path $root 'changelogs/archive'))|Out-Null
[IO.File]::WriteAllText((Join-Path $root 'changelogs/dev-tdd.md'),"# Changelog`n`n## [Unreleased]`n")
[IO.File]::WriteAllText((Join-Path $root 'changelogs/archive/dev-tdd.md'),"# Archive`n")
& git -C $root add -- CHANGELOG.md VERSION changelogs
& git -C $root -c user.name=Tests -c user.email=tests@localhost commit -q -m versioning
$v=Get-AgentOpsReleasePolicy -RepositoryPath $root -Commit HEAD
if($v.Code -ne 0){throw ('Versioning files rejected: '+($v.Issues -join '; '))}
Write-Host 'PASS release policy accepts CHANGELOG.md, VERSION and changelogs/'
& git -C $root checkout -q -b private-changelog-test $good
[IO.Directory]::CreateDirectory((Join-Path $root 'changelogs'))|Out-Null
[IO.File]::WriteAllText((Join-Path $root 'changelogs/private-token.json'),'{}')
& git -C $root add -- changelogs
& git -C $root -c user.name=Tests -c user.email=tests@localhost commit -q -m badlog
if((Get-AgentOpsReleasePolicy -RepositoryPath $root -Commit HEAD).Code -eq 0){throw 'Non-markdown changelog file accepted'}
Write-Host 'PASS release policy rejects non-markdown files under changelogs/'
# Installed bootstraps never update and verify every new release with their own frozen allowlist.
# This copy is the allowlist of the oldest supported bootstrap (c34512f). Every file the repository
# publishes must pass it, or existing installations reject the update ("Unexpected/private file").
$legacyCore=@('dev-systematic-debugging','dev-tdd','ops-git-worktrees','ops-project-init','ops-project-migrate','ops-session-handoff')
function Test-LegacyAllowed([string]$path){
    if($path -match '(^|/)[^/]*\.env($|\.)|(^|/)(credentials|secrets)(\.|/)|(^|/)[^/]*(token|credential|secret)[^/]*\.(json|toml|ya?ml|key|pem|pfx|p12)$|\.py[co]$|(^|/)__pycache__/'){return $false}
    if($path -match '^skills/([^/]+)/'){
        if($Matches[1] -in $legacyCore){return $true}
        return ($path -match '^skills/scripts/(rescue_local_edits|sync_hub_to_gemini|watch_skills_hub)\.ps1$')
    }
    if($path -match '^skills/'){return $path -match '^skills/(pull_replica_to_hub|setup_ai_skills_machine|setup_antigravity_machine|sync_antigravity_junctions)\.bat$'}
    return ($path -match '^(scripts|templates|tests|docs|\.github)/' -or $path -in @('.gitignore','README.md','LICENSE','install.ps1','install.sh','update.ps1','update.sh','release-contract.json'))
}
$published=@(& git -C $source -c core.quotepath=false ls-files)
$rejected=@($published|Where-Object {-not (Test-LegacyAllowed $_)})
if($rejected.Count){throw ('Installed bootstraps would reject this release: '+($rejected -join ', '))}
Write-Host "PASS every published file ($($published.Count)) passes the frozen bootstrap allowlist"
Write-Host "Release policy: 8 passed. Fixture: $root"
Remove-TestFixtures $root
