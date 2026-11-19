[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/Versioning.psm1') -Force
$script:passed=0
function New-Fixture {
    $root=Join-Path ([IO.Path]::GetTempPath()) ('aoc-versioning-'+[guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($root)|Out-Null
    & git init -q -b main $root
    return $root
}
function Set-File($root,$path,$text){
    $full=Join-Path $root $path;[IO.Directory]::CreateDirectory((Split-Path -Parent $full))|Out-Null
    [IO.File]::WriteAllText($full,$text)
}
function Save-Commit($root,$message){
    & git -C $root -c core.autocrlf=false add -A
    & git -C $root -c user.name=Tests -c user.email=tests@localhost commit -q -m $message
}
function Skill($version){ "---`nname: demo`ndescription: demo`nversion: $version`n---`n# Demo`n" }
function Log($versions){
    $text="# Changelog`n`n## [Unreleased]`n"
    foreach($v in $versions){$text+="`n## [$v] - 2026-11-19`n### Added`n- Entry.`n"}
    return $text
}
function Assert-Code($result,$code,$label){
    if($result.Code -ne $code){throw ("$label expected code $code, got $($result.Code): "+($result.Issues -join '; '))}
    $script:passed++;Write-Host "PASS $label"
}
function Assert-Issue($result,$pattern,$label){
    if(-not (@($result.Issues)|Where-Object {$_ -match $pattern})){throw ("$label missing issue /$pattern/: "+($result.Issues -join '; '))}
    $script:passed++;Write-Host "PASS $label"
}

# 1. A versioned skill with a matching changelog is accepted.
$r1=New-Fixture
Set-File $r1 'skills/demo/SKILL.md' (Skill '1.0.0')
Set-File $r1 'changelogs/demo.md' (Log @('1.0.0'))
Save-Commit $r1 'baseline'
Assert-Code (Test-AgentOpsVersioning -RepositoryPath $r1) 0 'clean versioned skill is accepted'

# 2. A skill without a SemVer version is rejected.
Set-File $r1 'skills/demo/SKILL.md' (Skill 'one')
Assert-Issue (Test-AgentOpsVersioning -RepositoryPath $r1) 'demo.*SemVer' 'invalid skill version is rejected'

# 3. A skill whose declared version differs from its latest released entry is rejected.
Set-File $r1 'skills/demo/SKILL.md' (Skill '1.1.0')
Assert-Issue (Test-AgentOpsVersioning -RepositoryPath $r1) 'demo.*1\.1\.0.*1\.0\.0' 'version/changelog mismatch is rejected'

# 4. Changing a skill without touching its changelog is rejected (working tree vs HEAD).
Set-File $r1 'skills/demo/SKILL.md' (Skill '1.0.0')
Set-File $r1 'skills/demo/scripts/run.py' 'print(1)'
Assert-Issue (Test-AgentOpsVersioning -RepositoryPath $r1) 'demo.*changelogs/demo\.md' 'skill change without changelog entry is rejected'

# 5. The same change with a changelog update is accepted.
Set-File $r1 'changelogs/demo.md' ((Log @('1.0.0')) -replace '## \[Unreleased\]',"## [Unreleased]`n### Added`n- run.py.")
Assert-Code (Test-AgentOpsVersioning -RepositoryPath $r1) 0 'skill change with changelog entry is accepted'
Save-Commit $r1 'add script'

# 6. Commit ranges are checked too (CI mode).
Set-File $r1 'skills/demo/references/a.md' 'ref'
Save-Commit $r1 'undocumented'
Assert-Issue (Test-AgentOpsVersioning -RepositoryPath $r1 -Base 'HEAD~1' -Head 'HEAD') 'changelogs/demo\.md' 'commit range without changelog is rejected'

# 7. A skill without any changelog file is rejected.
$r2=New-Fixture
Set-File $r2 'skills/lonely/SKILL.md' (Skill '0.1.0')
Save-Commit $r2 'lonely'
Assert-Issue (Test-AgentOpsVersioning -RepositoryPath $r2) 'lonely.*changelog' 'skill without changelog is rejected'

# 8. A changelog without an Unreleased section is rejected.
Set-File $r2 'changelogs/lonely.md' "# Changelog`n`n## [0.1.0] - 2026-11-19`n- x`n"
Assert-Issue (Test-AgentOpsVersioning -RepositoryPath $r2) 'Unreleased' 'changelog without Unreleased is rejected'

# 9. Root project changelog: changes outside .context/ and changelogs/ need a root entry.
$r3=New-Fixture
Set-File $r3 'CHANGELOG.md' (Log @('1.0.0'))
Set-File $r3 'VERSION' '1.0.0'
Set-File $r3 'src/app.ps1' 'v1'
Save-Commit $r3 'root baseline'
Assert-Code (Test-AgentOpsVersioning -RepositoryPath $r3) 0 'clean root project is accepted'
Set-File $r3 '.context/activeContext.md' 'handoff'
Assert-Code (Test-AgentOpsVersioning -RepositoryPath $r3) 0 'handoff-only changes need no changelog'
Set-File $r3 'src/app.ps1' 'v2'
Assert-Issue (Test-AgentOpsVersioning -RepositoryPath $r3) 'CHANGELOG\.md' 'root change without changelog is rejected'

# 10. Root VERSION must match the latest released entry.
Set-File $r3 'src/app.ps1' 'v1'
Set-File $r3 'VERSION' '2.0.0'
Assert-Issue (Test-AgentOpsVersioning -RepositoryPath $r3) 'VERSION.*2\.0\.0.*1\.0\.0' 'root VERSION mismatch is rejected'
Set-File $r3 'VERSION' '1.0.0'

# 11. Tags must match the changelog and declared version at the tagged commit.
& git -C $r3 -c user.name=Tests -c user.email=tests@localhost tag -a v1.0.0 -m 'v1.0.0'
Assert-Code (Test-AgentOpsVersioning -RepositoryPath $r3) 0 'matching root tag is accepted'
& git -C $r3 -c user.name=Tests -c user.email=tests@localhost tag -a v3.0.0 -m 'v3.0.0'
Assert-Issue (Test-AgentOpsVersioning -RepositoryPath $r3) 'v3\.0\.0' 'root tag without changelog version is rejected'
& git -C $r3 tag -d v3.0.0|Out-Null
& git -C $r1 -c user.name=Tests -c user.email=tests@localhost tag -a demo@v1.0.0 -m 'demo 1.0.0'
Assert-Code (Test-AgentOpsVersioning -RepositoryPath $r1) 0 'matching skill tag is accepted'
& git -C $r1 -c user.name=Tests -c user.email=tests@localhost tag -a demo@v9.9.9 -m 'bad'
Assert-Issue (Test-AgentOpsVersioning -RepositoryPath $r1) 'demo@v9\.9\.9' 'skill tag without matching version is rejected'

# 12. Rotation: more than ten released sections in the active changelog is a warning, not an error.
$r4=New-Fixture
$many=@(1..12|ForEach-Object {"1.0.$_"});[array]::Reverse($many)
Set-File $r4 'skills/big/SKILL.md' (Skill '1.0.12')
Set-File $r4 'changelogs/big.md' (Log $many)
Save-Commit $r4 'big'
$r=Test-AgentOpsVersioning -RepositoryPath $r4
Assert-Code $r 0 'long changelog does not fail'
if(-not (@($r.Warnings)|Where-Object {$_ -match 'big.*archive'})){throw 'rotation warning missing'};$script:passed++;Write-Host 'PASS long changelog warns to archive'

# 12b. A UTF-8 BOM before the frontmatter is tolerated in the working tree and at tags.
$rb=New-Fixture
[IO.Directory]::CreateDirectory((Join-Path $rb 'skills/bom'))|Out-Null
[IO.File]::WriteAllText((Join-Path $rb 'skills/bom/SKILL.md'),((Skill '2.0.0') -replace 'name: demo','name: bom'),(New-Object Text.UTF8Encoding($true)))
Set-File $rb 'changelogs/bom.md' (Log @('2.0.0'))
Save-Commit $rb 'bom'
& git -C $rb -c user.name=Tests -c user.email=tests@localhost tag -a bom@v2.0.0 -m 'bom'
Assert-Code (Test-AgentOpsVersioning -RepositoryPath $rb) 0 'BOM-prefixed frontmatter is accepted'

# 12c. A version line that splits a folded/literal description breaks the YAML and is rejected.
$rf=New-Fixture
Set-File $rf 'skills/fold/SKILL.md' "---`nname: fold`ndescription: >-`nversion: 1.0.0`n  Long folded text.`n---`n# Fold`n"
Set-File $rf 'changelogs/fold.md' (Log @('1.0.0'))
Save-Commit $rf 'fold'
Assert-Issue (Test-AgentOpsVersioning -RepositoryPath $rf) 'fold.*description' 'version inside a block-scalar description is rejected'
Set-File $rf 'skills/fold/SKILL.md' "---`nname: fold`nversion: 1.0.0`ndescription: >-`n  Long folded text.`n---`n# Fold`n"
Save-Commit $rf 'fix fold'
Assert-Code (Test-AgentOpsVersioning -RepositoryPath $rf) 0 'version beside a folded description is accepted'

# 12d. docs/ layout (used by the framework itself): docs/CHANGELOG.md, docs/VERSION, docs/changelogs/<skill>.md.
$rd=New-Fixture
Set-File $rd 'docs/CHANGELOG.md' (Log @('2.0.0'))
Set-File $rd 'docs/VERSION' '2.0.0'
Set-File $rd 'skills/dl/SKILL.md' ((Skill '1.0.0') -replace 'name: demo','name: dl')
Set-File $rd 'docs/changelogs/dl.md' (Log @('1.0.0'))
Set-File $rd 'src/a.ps1' 'v1'
Save-Commit $rd 'docs layout'
& git -C $rd -c user.name=Tests -c user.email=tests@localhost tag -a v2.0.0 -m 'v2.0.0'
& git -C $rd -c user.name=Tests -c user.email=tests@localhost tag -a dl@v1.0.0 -m 'dl'
$r=Test-AgentOpsVersioning -RepositoryPath $rd
Assert-Code $r 0 'docs/ layout is accepted with tags'
if(@($r.Artifacts|Where-Object {$_.Kind -eq 'project' -and $_.Version -eq '2.0.0' -and $_.Changelog -eq 'docs/CHANGELOG.md'}).Count -ne 1){throw 'docs/ project changelog not detected'};$script:passed++;Write-Host 'PASS docs/ project changelog and VERSION are detected'
Set-File $rd 'src/a.ps1' 'v2'
Assert-Issue (Test-AgentOpsVersioning -RepositoryPath $rd) 'docs/CHANGELOG\.md' 'docs/ layout still requires a changelog entry'
Set-File $rd 'src/a.ps1' 'v1'
Set-File $rd 'skills/dl/notes.md' 'x'
Assert-Issue (Test-AgentOpsVersioning -RepositoryPath $rd) 'dl.*docs/changelogs/dl\.md' 'docs/ layout requires the skill changelog entry'
Set-File $rd 'docs/VERSION' '3.0.0'
Assert-Issue (Test-AgentOpsVersioning -RepositoryPath $rd) 'VERSION.*3\.0\.0.*2\.0\.0' 'docs/VERSION mismatch is rejected'

# 13. Repositories without versioned artifacts are not penalised.
$r5=New-Fixture
Set-File $r5 'notes.txt' 'x'
Save-Commit $r5 'plain'
Assert-Code (Test-AgentOpsVersioning -RepositoryPath $r5) 0 'repository without artifacts is accepted'
& git -C $r5 -c user.name=Tests -c user.email=tests@localhost tag -a v1.0.0 -m 'unversioned tag'
Assert-Code (Test-AgentOpsVersioning -RepositoryPath $r5) 0 'tags in a repository without a project changelog are not judged'

# 14. CLI returns JSON and the exit code.
$engine=(Get-Process -Id $PID).Path
$json=& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/check-versioning.ps1') -RepositoryPath $r2|Out-String
if($LASTEXITCODE -ne 1 -or ($json|ConvertFrom-Json).Code -ne 1){throw 'CLI did not report the failing fixture'}
$script:passed++;Write-Host 'PASS CLI reports JSON and exit code'

Write-Host "Versioning: $script:passed passed."
