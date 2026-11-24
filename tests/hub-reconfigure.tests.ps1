# All installations, hubs and profiles below are temporary fixtures.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/UpdateCoordinator.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-hub-tests-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
function Assert($condition,$message){if(-not $condition){throw $message}}
function Test($name,[scriptblock]$body){try{& $body;$script:passed++;Write-Host "PASS $name"}catch{$script:failed++;Write-Host "FAIL $name : $_";Write-Host $_.ScriptStackTrace}}
function Put($root,$key,$text){$path=Join-Path $root $key;[IO.Directory]::CreateDirectory((Split-Path -Parent $path))|Out-Null;[IO.File]::WriteAllText($path,$text)}
function Read-Json($path){Get-Content -LiteralPath $path -Raw|ConvertFrom-Json}
function Fixture {
    $root=Join-Path $script:base ('with spaces-'+[guid]::NewGuid().ToString('N'))
    $install=Join-Path $root 'bootstrap'
    [IO.Directory]::CreateDirectory($install)|Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'scripts') -Destination $install -Recurse
    foreach($name in @('dev-systematic-debugging','dev-tdd','ops-git-worktrees','ops-project-init','ops-project-migrate','ops-session-handoff')){Put $install "skills/$name/SKILL.md" 'core'}
    $p=@{InstallRoot=$install;RepoUrl=$install;StateDir=(Join-Path $root 'state');RuntimeDir=(Join-Path $root 'runtime');HubDir=(Join-Path $root 'hub');Targets=@((Join-Path $root 'target'));WatcherEnabled=$false}
    foreach($d in @($p.HubDir)+$p.Targets){[IO.Directory]::CreateDirectory($d)|Out-Null}
    $r=Initialize-AgentOpsUpdate @p -LocalDevelopment
    Assert ($r.Code -eq 0) ($r|ConvertTo-Json -Depth 8)
    $newHub=Join-Path $root 'canonical hub';[IO.Directory]::CreateDirectory($newHub)|Out-Null
    return @{Root=$root;P=$p;NewHub=$newHub;ConfigPath=(Join-Path $p.StateDir 'watch-config.json');StatePath=(Join-Path $p.StateDir 'update-state.json')}
}
function Hashes($f){@((Get-FileHash $f.ConfigPath).Hash,(Get-FileHash $f.StatePath).Hash) -join '/'}

Test 'switches HubDir in both configuration files and keeps the installation valid' {
    $f=Fixture
    Put $f.NewHub 'personal/SKILL.md' 'canonical'
    $r=Set-AgentOpsHubDir -ConfigPath $f.ConfigPath -HubDir $f.NewHub
    Assert ($r.Code -eq 0 -and $r.Status -eq 'RECONFIGURED') ($r|ConvertTo-Json -Depth 6)
    Assert ((Read-Json $f.ConfigPath).HubDir -eq $f.NewHub) 'watch-config.json not updated'
    Assert ((Read-Json $f.StatePath).Config.HubDir -eq $f.NewHub) 'update-state.json not updated'
    Assert ((Get-AgentOpsActiveRelease -ConfigPath $f.ConfigPath).Mode -eq 'LOCAL_DEV') 'State guard rejects the new configuration'
    Assert ($r.Backup -and (Test-Path (Join-Path $r.Backup 'watch-config.json')) -and (Test-Path (Join-Path $r.Backup 'update-state.json'))) 'Backups missing'
    Assert ((Read-Json (Join-Path $r.Backup 'update-state.json')).Config.HubDir -eq $f.P.HubDir) 'Backup does not hold the previous hub'
    Assert (Test-Path -LiteralPath $f.P.HubDir) 'Previous hub was removed'
}
Test 'the same hub is reported unchanged without writing' {
    $f=Fixture;$before=Hashes $f
    $r=Set-AgentOpsHubDir -ConfigPath $f.ConfigPath -HubDir $f.P.HubDir
    Assert ($r.Code -eq 0 -and $r.Status -eq 'UNCHANGED' -and -not $r.Backup) ($r|ConvertTo-Json -Depth 6)
    Assert ((Hashes $f) -eq $before) 'Unchanged hub rewrote configuration'
}
Test 'a missing hub directory is refused without writing' {
    $f=Fixture;$before=Hashes $f
    $r=Set-AgentOpsHubDir -ConfigPath $f.ConfigPath -HubDir (Join-Path $f.Root 'absent')
    Assert ($r.Code -eq 1 -and ($r.Issues -join ' ') -match 'does not exist') ($r|ConvertTo-Json -Depth 6)
    Assert ((Hashes $f) -eq $before) 'Missing hub changed configuration'
}
Test 'a hub overlapping a replica is refused without writing' {
    $f=Fixture;$before=Hashes $f
    $inside=Join-Path $f.P.Targets[0] 'nested';[IO.Directory]::CreateDirectory($inside)|Out-Null
    $r=Set-AgentOpsHubDir -ConfigPath $f.ConfigPath -HubDir $inside
    Assert ($r.Code -eq 1) ($r|ConvertTo-Json -Depth 6)
    Assert ((Hashes $f) -eq $before) 'Overlapping hub changed configuration'
}
Test 'divergent skills between the new hub and replicas require review and write nothing' {
    $f=Fixture;$before=Hashes $f
    Put $f.NewHub 'shared/SKILL.md' 'hub edit'
    Put $f.P.Targets[0] 'shared/SKILL.md' 'replica edit'
    $r=Set-AgentOpsHubDir -ConfigPath $f.ConfigPath -HubDir $f.NewHub
    Assert ($r.Code -eq 2 -and $r.Status -eq 'REVIEW_REQUIRED' -and @($r.Conflicts).Count -ge 1) ($r|ConvertTo-Json -Depth 6)
    Assert ((Hashes $f) -eq $before) 'Conflicting switch changed configuration'
    Assert ([IO.File]::ReadAllText((Join-Path $f.P.Targets[0] 'shared/SKILL.md')) -eq 'replica edit') 'Replica was modified'
}
Test 'WhatIf evaluates without writing' {
    $f=Fixture;$before=Hashes $f
    $r=Set-AgentOpsHubDir -ConfigPath $f.ConfigPath -HubDir $f.NewHub -WhatIf
    Assert ($r.Status -eq 'WHAT_IF') ($r|ConvertTo-Json -Depth 6)
    Assert ((Hashes $f) -eq $before) 'WhatIf changed configuration'
}
Test 'a half-applied switch (watch-config already changed) is completed' {
    $f=Fixture
    $cfg=Read-Json $f.ConfigPath;$cfg.HubDir=$f.NewHub;[IO.File]::WriteAllText($f.ConfigPath,($cfg|ConvertTo-Json -Depth 5))
    $guard=$null;try{Get-AgentOpsActiveRelease -ConfigPath $f.ConfigPath|Out-Null}catch{$guard=$_.Exception.Message}
    Assert ($guard -match 'configuration changed') 'Fixture did not reproduce the guard'
    $r=Set-AgentOpsHubDir -ConfigPath $f.ConfigPath -HubDir $f.NewHub
    Assert ($r.Code -eq 0 -and $r.Status -eq 'RECONFIGURED') ($r|ConvertTo-Json -Depth 6)
    Assert ((Get-AgentOpsActiveRelease -ConfigPath $f.ConfigPath).Mode -eq 'LOCAL_DEV') 'Half-applied switch still blocked'
}
Test 'a half-applied switch towards a different hub is refused' {
    $f=Fixture;$other=Join-Path $f.Root 'other';[IO.Directory]::CreateDirectory($other)|Out-Null
    $cfg=Read-Json $f.ConfigPath;$cfg.HubDir=$other;[IO.File]::WriteAllText($f.ConfigPath,($cfg|ConvertTo-Json -Depth 5))
    $r=Set-AgentOpsHubDir -ConfigPath $f.ConfigPath -HubDir $f.NewHub
    Assert ($r.Code -eq 1 -and (Read-Json $f.StatePath).Config.HubDir -eq $f.P.HubDir) ($r|ConvertTo-Json -Depth 6)
}
Test 'a pending activation blocks the switch' {
    $f=Fixture;$before=Hashes $f
    Put $f.P.StateDir 'activation-pending.json' '{}'
    $r=Set-AgentOpsHubDir -ConfigPath $f.ConfigPath -HubDir $f.NewHub
    Assert ($r.Code -eq 2 -and $r.Status -eq 'ACTIVATION_REVIEW_REQUIRED') ($r|ConvertTo-Json -Depth 6)
    Assert ((Hashes $f) -eq $before) 'Pending activation allowed a switch'
}
Test 'CLI returns JSON and the exit code without touching scheduled tasks' {
    $f=Fixture;$engine=(Get-Process -Id $PID).Path
    $json=& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/set-hub.ps1') -HubDir $f.NewHub -ConfigPath $f.ConfigPath -NoRestart|Out-String
    Assert ($LASTEXITCODE -eq 0 -and ($json|ConvertFrom-Json).Status -eq 'RECONFIGURED') $json
}
Write-Host "Hub reconfiguration: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
