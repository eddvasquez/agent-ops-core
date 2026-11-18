# Standalone tests: no modules or network installation required.
[CmdletBinding()]
param([switch]$IncludeLinkTest)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../scripts/SkillsSync.psm1') -Force
$script:TestRoot = Join-Path ([IO.Path]::GetTempPath()) ('aoc-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($script:TestRoot) | Out-Null
$script:Passed = 0
$script:Failed = 0
function Assert($condition, $message) { if (-not $condition) { throw $message } }
function Fixture {
    $base = Join-Path $script:TestRoot ([guid]::NewGuid().ToString('N'))
    $p = @{ HubDir = (Join-Path $base 'hub'); Targets = @((Join-Path $base 'target[1]'), (Join-Path $base 'target two')); StateDir = (Join-Path $base 'state') }
    foreach ($dir in (@($p.HubDir) + $p.Targets)) { [IO.Directory]::CreateDirectory($dir) | Out-Null }
    return $p
}
function Put($root, $key, $text) {
    $path = Join-Path $root $key
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    [IO.File]::WriteAllText($path, $text)
    return $path
}
function Read($root, $key) { [IO.File]::ReadAllText((Join-Path $root $key)) }
function Test($name, [scriptblock]$body) {
    try { & $body; $script:Passed++; Write-Host "PASS $name" }
    catch { $script:Failed++; Write-Host "FAIL $name : $_" -ForegroundColor Red; Write-Host $_.ScriptStackTrace }
}
Test 'complete rescue; functional payload and binary bytes distributed; caches retained in rescue' {
    $p = Fixture
    Put $p.Targets[0] 'demo/SKILL.md' 'instructions' | Out-Null
    Put $p.Targets[0] 'demo/scripts/tool.ps1' 'Write-Output 1' | Out-Null
    Put $p.Targets[0] 'demo/scripts/tool.py' 'print(1)' | Out-Null
    Put $p.Targets[0] 'demo/README.md' 'reference' | Out-Null
    $hidden = Put $p.Targets[0] 'demo/.settings' 'hidden'
    [IO.File]::SetAttributes($hidden, [IO.FileAttributes]::Hidden)
    $binary = Put $p.Targets[0] 'demo/assets/template.xlsx' 'placeholder'
    [IO.File]::WriteAllBytes($binary, [byte[]](0,1,2,255,0,128))
    Put $p.Targets[0] 'demo/scripts/__pycache__/tool.pyc' 'cache' | Out-Null
    $r = Invoke-SkillSync @p -Mode Apply
    Assert ($r.Code -eq 0) ($r | ConvertTo-Json -Depth 6)
    foreach ($key in @('demo/SKILL.md','demo/scripts/tool.ps1','demo/scripts/tool.py','demo/README.md','demo/.settings','demo/assets/template.xlsx')) {
        Assert (Test-Path -LiteralPath (Join-Path $p.Targets[1] $key)) "Missing payload $key"
    }
    Assert ((Get-FileHash -LiteralPath $binary).Hash -eq (Get-FileHash -LiteralPath (Join-Path $p.Targets[1] 'demo/assets/template.xlsx')).Hash) 'Binary changed'
    Assert (-not (Test-Path -LiteralPath (Join-Path $p.Targets[1] 'demo/scripts/__pycache__/tool.pyc'))) 'Cache distributed'
    $manifest = Get-Content -LiteralPath $r.RescueManifest -Raw | ConvertFrom-Json
    Assert $manifest.Complete 'Rescue incomplete'
    Assert (@($manifest.Files).Count -eq 7) 'Rescue omitted files'
    foreach ($f in $manifest.Files) { Assert (Test-Path -LiteralPath (Join-Path $p.StateDir ('blobs/' + $f.Hash))) 'Missing rescued blob' }
}
Test 'hash comparison ignores timestamps; identical content makes zero copies' {
    $p = Fixture; $f = Put $p.HubDir 'demo/SKILL.md' 'AAAA'
    Assert ((Invoke-SkillSync @p -Mode Apply).Code -eq 0) 'Initial sync failed'
    $time = [IO.File]::GetLastWriteTimeUtc($f)
    [IO.File]::WriteAllText($f, 'BBBB'); [IO.File]::SetLastWriteTimeUtc($f, $time)
    $r = Invoke-SkillSync @p -Mode Apply
    Assert ($r.Code -eq 0 -and (Read $p.Targets[0] 'demo/SKILL.md') -eq 'BBBB') 'Same metadata hid edit'
    [IO.File]::SetLastWriteTimeUtc($f, $time.AddDays(1))
    Assert ((Invoke-SkillSync @p -Mode Apply).Copied -eq 0) 'Unnecessary copy'
}
Test 'replica edit rescued; actual previous content can be restored' {
    $p = Fixture; Put $p.HubDir 'demo/SKILL.md' 'base' | Out-Null
    Invoke-SkillSync @p -Mode Apply | Out-Null
    $old = (Get-FileHash -LiteralPath (Join-Path $p.HubDir 'demo/SKILL.md')).Hash.ToLowerInvariant()
    Put $p.Targets[0] 'demo/SKILL.md' 'replica edit' | Out-Null
    Assert ((Invoke-SkillSync @p -Mode Apply).Code -eq 0) 'Rescue failed'
    Assert ((Read $p.HubDir 'demo/SKILL.md') -eq 'replica edit') 'Replica lost'
    $r = Invoke-SkillSync @p -Mode Restore -Key 'demo/SKILL.md' -VersionHash $old
    Assert ($r.Code -eq 0 -and (Read $p.HubDir 'demo/SKILL.md') -eq 'base') 'Restore failed'
}
Test 'conflicts independent of source order; explicit resolution' {
    $p = Fixture; Put $p.HubDir 'demo/SKILL.md' 'base' | Out-Null
    Invoke-SkillSync @p -Mode Apply | Out-Null
    Put $p.Targets[0] 'demo/SKILL.md' 'edit A' | Out-Null
    Put $p.Targets[1] 'demo/SKILL.md' 'edit B' | Out-Null
    $r = Invoke-SkillSync @p -Mode Apply
    Assert ($r.Code -eq 2 -and $r.Conflicts.Count -eq 1) 'Conflict not detected'
    Assert ((Read $p.HubDir 'demo/SKILL.md') -eq 'base') 'Conflict overwrote hub'
    [array]::Reverse($p.Targets)
    Assert ((Invoke-SkillSync @p -Mode Apply).Code -eq 2) 'Order changed decision'
    $hash = (Get-FileHash -LiteralPath (Join-Path $p.Targets[0] 'demo/SKILL.md')).Hash.ToLowerInvariant()
    $r = Invoke-SkillSync @p -Mode Resolve -Key 'demo/SKILL.md' -VersionHash $hash
    Assert ($r.Code -eq 0 -and (Read $p.HubDir 'demo/SKILL.md') -eq 'edit B') 'Resolve failed'
}
Test 'initial divergence preserved; unrelated root content never removed' {
    $p = Fixture; Put $p.HubDir 'demo/SKILL.md' 'hub' | Out-Null
    Put $p.Targets[0] 'demo/SKILL.md' 'replica' | Out-Null
    Put $p.Targets[0] 'notes.txt' 'unrelated' | Out-Null
    Put $p.Targets[0] 'not-a-skill/data.txt' 'unrelated folder' | Out-Null
    Assert ((Invoke-SkillSync @p -Mode Apply).Code -eq 2) 'Initial conflict lost'
    Assert ((Read $p.Targets[0] 'notes.txt') -eq 'unrelated') 'Root file removed'
    Assert (-not (Test-Path -LiteralPath (Join-Path $p.HubDir 'not-a-skill'))) 'Imported non-skill'
}
Test 'borrado stays pending; safe explicit prune; modified survivor blocks prune' {
    $p = Fixture; Put $p.HubDir 'demo/SKILL.md' 'base' | Out-Null
    Invoke-SkillSync @p -Mode Apply | Out-Null
    [IO.File]::Delete((Join-Path $p.Targets[0] 'demo/SKILL.md'))
    $r = Invoke-SkillSync @p -Mode Apply
    Assert ($r.Code -eq 2 -and $r.Deletions.Count -eq 1) 'Deletion not pending'
    Assert ((Read $p.HubDir 'demo/SKILL.md') -eq 'base') 'Deletion propagated'
    Put $p.Targets[1] 'demo/SKILL.md' 'other edit' | Out-Null
    Assert ((Invoke-SkillSync @p -Mode Prune -Key 'demo/SKILL.md').Code -eq 2) 'Prune destroyed edit'
    Put $p.Targets[1] 'demo/SKILL.md' 'base' | Out-Null
    Assert ((Invoke-SkillSync @p -Mode Prune -Key 'demo/SKILL.md').Code -eq 0) 'Prune failed'
    Assert (-not (Test-Path -LiteralPath (Join-Path $p.HubDir 'demo/SKILL.md'))) 'Prune did not remove managed file'
    Assert ((Invoke-SkillSync @p -Mode Apply).Copied -eq 0) 'Pruned file resurrected'
}
Test 'WhatIf and Plan never create state or destinations' {
    $p = Fixture; Put $p.HubDir 'demo/SKILL.md' 'base' | Out-Null
    $r = Invoke-SkillSync @p -Mode Apply -WhatIf
    Assert ($r.Copied -eq 0) 'WhatIf wrote copies'
    Assert (-not (Test-Path -LiteralPath $p.StateDir)) 'WhatIf created state'
    Assert (-not (Test-Path -LiteralPath (Join-Path $p.Targets[0] 'demo'))) 'WhatIf wrote target'
    $r = Invoke-SkillSync @p -Mode Plan
    Assert ($r.Actions.Count -eq 2) 'Plan missing copies'
    Assert (-not (Test-Path -LiteralPath $p.StateDir)) 'Plan created state'
}
Test 'reject dangerous or overlapping roots and corrupt state' {
    $p = Fixture; $p.Targets = @((Join-Path $p.HubDir 'nested'))
    Assert ((Invoke-SkillSync @p -Mode Apply).Code -eq 1) 'Nested destination allowed'
    $p = Fixture; Put $p.StateDir 'state.json' '{broken' | Out-Null
    Assert ((Invoke-SkillSync @p -Mode Apply).Code -eq 1) 'Corrupt state allowed'
}
Test 'blocked read cannot declare complete rescue; retry after release' {
    $p = Fixture; $f = Put $p.HubDir 'demo/SKILL.md' 'base'
    $lock = [IO.File]::Open($f, 'Open', 'ReadWrite', 'None')
    try { $r = Invoke-SkillSync @p -Mode Apply; Assert ($r.Code -eq 1) 'Locked source reported success' }
    finally { $lock.Dispose() }
    Assert ((Invoke-SkillSync @p -Mode Apply).Code -eq 0) 'Retry did not recover'
}
Test 'framework catalogue prevents publishing or importing specialized skills; upstream conflict preserved' {
    $p = Fixture; $framework = Join-Path (Split-Path $p.HubDir -Parent) 'framework'
    $names = @('dev-systematic-debugging','dev-tdd','ops-git-worktrees','ops-project-init','ops-project-migrate','ops-session-handoff')
    foreach ($name in $names) { Put $framework ("skills/$name/SKILL.md") 'core v1' | Out-Null }
    Put $framework 'skills/private-ads/SKILL.md' 'private' | Out-Null
    Assert ((Invoke-SkillSync @p -FrameworkDir $framework -Mode Apply).Code -eq 0) 'Core seed failed'
    Assert (-not (Test-Path -LiteralPath (Join-Path $p.HubDir 'private-ads'))) 'Private source imported'
    Put $p.HubDir 'dev-tdd/SKILL.md' 'my edit' | Out-Null
    Invoke-SkillSync @p -FrameworkDir $framework -Mode Apply | Out-Null
    Put $framework 'skills/dev-tdd/SKILL.md' 'core v2' | Out-Null
    $r = Invoke-SkillSync @p -FrameworkDir $framework -Mode Apply
    Assert ($r.Code -eq 2) 'Upstream overwrote customization'
    Assert ((Read $framework 'skills/dev-tdd/SKILL.md') -eq 'core v2') 'Framework mutated'
}
Test 'incremental rescue inventories the entire affected skill, not unrelated skills' {
    $p=Fixture; Put $p.HubDir 'demo/SKILL.md' 'base' | Out-Null; Put $p.HubDir 'other/SKILL.md' 'other' | Out-Null
    Invoke-SkillSync @p -Mode Apply | Out-Null
    Put $p.Targets[0] 'demo/assets/attachment.pdf' 'attachment' | Out-Null
    Put $p.HubDir 'other/SKILL.md' 'deferred' | Out-Null
    $r=Invoke-SkillSync @p -Mode Apply -SkillNames @('demo')
    Assert ($r.Code -eq 0) ($r | ConvertTo-Json -Depth 5)
    Assert ((Read $p.Targets[1] 'other/SKILL.md') -eq 'other') 'Unrelated skill changed'
    $manifest=Get-Content -LiteralPath $r.RescueManifest -Raw | ConvertFrom-Json
    Assert (@($manifest.Files | Where-Object Key -like 'other/*').Count -eq 0) 'Unexpected scope'
    Assert ((Read $p.Targets[1] 'demo/assets/attachment.pdf') -eq 'attachment') 'Attachment not rescued'
    Assert ((Invoke-SkillSync @p -Mode Apply).Code -eq 0) 'Full reconciliation failed'
}
Test 'interrupted replacement leaves baseline unchanged and recovers on next run' {
    $p=Fixture;Put $p.HubDir 'demo/SKILL.md' 'base'|Out-Null;Invoke-SkillSync @p -Mode Apply|Out-Null
    Put $p.HubDir 'demo/SKILL.md' 'new content'|Out-Null
    $handle=[IO.File]::Open((Join-Path $p.Targets[1] 'demo/SKILL.md'),'Open','Read','Read')
    try{
        $r=Invoke-SkillSync @p -Mode Apply
        Assert ($r.Code -eq 1) 'Locked replacement declared success'
        $j=Get-Content -LiteralPath $r.Journal -Raw|ConvertFrom-Json
        Assert ($j.Status -eq 'Interrupted') 'Interruption not journalled'
        Assert ((Read $p.Targets[1] 'demo/SKILL.md') -eq 'base') 'Locked target lost'
    }finally{$handle.Dispose()}
    Assert ((Invoke-SkillSync @p -Mode Apply).Code -eq 0) 'Journal recovery failed'
    Assert ((Read $p.Targets[1] 'demo/SKILL.md') -eq 'new content') 'Recovery omitted target'
}
if($IncludeLinkTest){Test 'links are reported as incomplete and never traversed' {
    $p=Fixture;Put $p.HubDir 'demo/SKILL.md' 'base'|Out-Null
    $outside=Join-Path (Split-Path $p.HubDir -Parent) 'outside';[IO.Directory]::CreateDirectory($outside)|Out-Null
    Put $outside 'private.txt' 'outside skill'|Out-Null
    New-Item -ItemType Junction -Path (Join-Path $p.HubDir 'demo/external') -Target $outside|Out-Null
    $r=Invoke-SkillSync @p -Mode Apply
    Assert ($r.Code -eq 1) 'Link accepted silently'
    $m=Get-Content -LiteralPath $r.RescueManifest -Raw|ConvertFrom-Json
    Assert (-not $m.Complete) 'Unresolved link declared complete'
    Assert (-not (Test-Path -LiteralPath (Join-Path $p.Targets[0] 'demo/external/private.txt'))) 'Link traversed'
}}
Test 'complete rescue includes empty directories and restores entire skill including caches' {
    $p=Fixture;Put $p.HubDir 'demo/SKILL.md' 'base'|Out-Null
    Put $p.HubDir 'demo/__pycache__/cached.pyc' 'cache'|Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $p.HubDir 'demo/empty/resources'))|Out-Null
    $r=Invoke-SkillSync @p -Mode Apply
    Assert ($r.Code -eq 0) 'Sync failed'
    Assert ([IO.Directory]::Exists((Join-Path $p.Targets[0] 'demo/empty/resources'))) 'Empty resource directory lost'
    $destination=Join-Path (Split-Path $p.HubDir -Parent) 'restored'
    $restore=Restore-SkillRescue -ManifestPath $r.RescueManifest -SourceRoot $p.HubDir -Destination $destination -WhatIf
    Assert (-not [IO.Directory]::Exists($destination)) 'Restore WhatIf wrote files'
    $restore=Restore-SkillRescue -ManifestPath $r.RescueManifest -SourceRoot $p.HubDir -Destination $destination
    Assert ($restore.Code -eq 0) 'Full restore failed'
    Assert ((Read $destination 'demo/__pycache__/cached.pyc') -eq 'cache') 'Raw cache not restored'
    Assert ([IO.Directory]::Exists((Join-Path $destination 'demo/empty/resources'))) 'Empty directory not restored'
    Assert ((Restore-SkillRescue -ManifestPath $r.RescueManifest -SourceRoot $p.HubDir -Destination $destination).Code -eq 1) 'Restore overwrote existing folder'
}
Test 'backup corruption fails closed before any overwrite' {
    $p=Fixture;Put $p.HubDir 'demo/SKILL.md' 'base'|Out-Null;Invoke-SkillSync @p -Mode Apply|Out-Null
    $hash=(Get-FileHash -LiteralPath (Join-Path $p.HubDir 'demo/SKILL.md')).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText((Join-Path $p.StateDir ('blobs/'+$hash)),'corrupt')
    Put $p.HubDir 'demo/SKILL.md' 'edit'|Out-Null
    $r=Invoke-SkillSync @p -Mode Apply
    Assert ($r.Code -eq 1 -and (Read $p.Targets[0] 'demo/SKILL.md') -eq 'base') 'Corrupt backup allowed overwrite'
}
Test 'another process holding the user mutex returns busy without writing' {
    $p=Fixture;Put $p.HubDir 'demo/SKILL.md' 'base'|Out-Null
    $ready=Join-Path (Split-Path $p.HubDir -Parent) 'mutex-ready'
    $body='$m=New-Object Threading.Mutex($false,("Local\AgentOpsSkillsSync-"+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value)); try{$m.WaitOne()|Out-Null;[IO.File]::WriteAllText('''+$ready.Replace("'","''")+''',"ready");Start-Sleep -Seconds 3}finally{$m.ReleaseMutex();$m.Dispose()}'
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
    $child=Start-Process -FilePath (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList @('-NoProfile','-NonInteractive','-EncodedCommand',$encoded) -WindowStyle Hidden -PassThru
    try {
        $deadline=[datetime]::UtcNow.AddSeconds(8)
        while(-not [IO.File]::Exists($ready) -and [datetime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
        Assert ([IO.File]::Exists($ready)) 'Mutex child failed to initialize'
        $r=Invoke-SkillSync @p -Mode Apply
        Assert ($r.Code -eq 3 -and -not [IO.Directory]::Exists($p.StateDir)) 'Concurrent execution was not blocked'
    }finally{if(-not $child.WaitForExit(5000)){$child.Kill();$child.WaitForExit()};$child.Dispose()}
}
Test 'missing framework directory and malformed baseline fail closed' {
    $p=Fixture; $framework=Join-Path (Split-Path $p.HubDir -Parent) 'absent-framework'
    Assert ((Invoke-SkillSync @p -FrameworkDir $framework -Mode Apply).Code -eq 1) 'Missing framework reported success'
    Put $p.HubDir 'demo/SKILL.md' 'base'|Out-Null;Invoke-SkillSync @p -Mode Apply|Out-Null
    $path=Join-Path $p.StateDir 'state.json';$s=Get-Content -LiteralPath $path -Raw|ConvertFrom-Json
    $s.Entries.'demo/SKILL.md'.Baselines.hub='invalid hash'
    [IO.File]::WriteAllText($path,($s|ConvertTo-Json -Depth 30))
    Assert ((Invoke-SkillSync @p -Mode Apply).Code -eq 1) 'Malformed baseline accepted'
}
Write-Host "Results: $script:Passed passed, $script:Failed failed. Fixtures: $script:TestRoot"
if ($script:Failed) { exit 1 }
