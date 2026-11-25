# Integrations: after every update the framework adjusts its hooks, plugin and permissions in the harnesses the user
# has, with no scripts to run. What changes a tool's own configuration (the Codex permission profile) needs consent,
# asked once and remembered. An outdated bootstrap is reported so the agent can offer to update it.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/Integrations.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-integrations-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
# A fake user profile with the chosen harnesses, an installation state and a bootstrap (with or without the capability).
function Machine([string[]]$harnesses=@('claude','codex','gemini'),[bool]$modernBoot=$true,[string]$sha=('a'*40)){
    $m=Join-Path $script:base ('m-'+[guid]::NewGuid().ToString('N').Substring(0,6));$home2=Join-Path $m 'home';$state=Join-Path $m 'state';$boot=Join-Path $m 'boot'
    foreach($d in $home2,$state,(Join-Path $boot 'scripts')){[IO.Directory]::CreateDirectory($d)|Out-Null}
    foreach($h in $harnesses){$dir=$(switch($h){'claude'{'.claude'}'codex'{'.codex'}'gemini'{'.gemini/config'}});[IO.Directory]::CreateDirectory((Join-Path $home2 $dir))|Out-Null}
    if($harnesses -contains 'codex'){[IO.File]::WriteAllText((Join-Path $home2 '.codex/config.toml'),"model = `"gpt-5`"`n",$utf8)}
    [IO.File]::WriteAllText((Join-Path $boot 'scripts/UpdateCoordinator.psm1'),$(if($modernBoot){"# capability: local-channel-v1`n"}else{"# old bootstrap`n"}),$utf8)
    [IO.File]::WriteAllText((Join-Path $state 'update-state.json'),(@{SchemaVersion=1;Mode='MANAGED';Active=@{Sha=$sha;Path=$source};Config=@{InstallRoot=$boot;WatcherEnabled=$true}}|ConvertTo-Json -Depth 4),$utf8)
    [IO.File]::WriteAllText((Join-Path $state 'watch-config.json'),(@{HubDir=(Join-Path $m 'hub');Targets=@((Join-Path $m 't1'),(Join-Path $m 't2'));StateDir=$state}|ConvertTo-Json -Depth 4),$utf8)
    return @{Home=$home2;State=$state;Boot=$boot}
}
$okPlugin={param($d) $true}
function Sync($m,[string]$sha=''){Sync-AgentOpsIntegrations -StateDir $m.State -HomeDir $m.Home -AntigravityValidator $okPlugin}

Test 'only the harnesses the user has are adjusted, and nothing is created for the others' {
    $m=Machine -harnesses @('claude')
    $r=Sync $m
    Assert ($r.Code -eq 0 -and $r.Status -eq 'SYNCED' -and (@($r.Harnesses) -join ',') -eq 'claude') ($r|ConvertTo-Json -Depth 4)
    $c=[IO.File]::ReadAllText((Join-Path $m.Home '.claude/settings.json'))
    Assert ($c -match 'session-start' -and $c -match 'secret-guard' -and $c -match 'post-tool') 'Claude hooks missing'
    Assert (-not (Test-Path (Join-Path $m.Home '.codex')) -and -not (Test-Path (Join-Path $m.Home '.gemini'))) 'Created folders for absent harnesses'
}
Test 'a second adjustment changes nothing' {
    $m=Machine;Sync $m|Out-Null
    $r=Sync $m
    Assert ($r.Code -eq 0 -and $r.Status -eq 'UP_TO_DATE' -and -not @($r.Files).Count) ($r|ConvertTo-Json -Depth 4)
}
Test 'the Codex configuration is only changed with consent; asked once, and a no is never asked again' {
    $m=Machine;$toml=Join-Path $m.Home '.codex/config.toml';$before=[IO.File]::ReadAllText($toml)
    $r=Sync $m
    Assert ([IO.File]::ReadAllText($toml) -eq $before -and @($r.NeedsConsent) -contains 'codex-profile') ('Changed without consent or did not ask: '+($r|ConvertTo-Json -Depth 4))
    Set-AgentOpsConsent -StateDir $m.State -Name 'codex-profile' -Answer 'no'
    $r=Sync $m
    Assert ([IO.File]::ReadAllText($toml) -eq $before -and -not @($r.NeedsConsent).Count) 'A no must not change it nor ask again'
    Set-AgentOpsConsent -StateDir $m.State -Name 'codex-profile' -Answer 'yes'
    Sync $m|Out-Null
    Assert ([IO.File]::ReadAllText($toml) -match 'default_permissions = "agent-ops"') 'A yes must apply the profile'
}
Test 'Antigravity gets the framework plugin and no loose entries' {
    $m=Machine -harnesses @('gemini')
    Sync $m|Out-Null
    $cfg=Join-Path $m.Home '.gemini/config'
    Assert ([IO.File]::Exists((Join-Path $cfg 'plugins/agent-ops-core/plugin.json'))) 'Plugin not installed'
    $h=Join-Path $cfg 'hooks.json'
    Assert (-not [IO.File]::Exists($h) -or -not (([IO.File]::ReadAllText($h)|ConvertFrom-Json).PSObject.Properties.Name|Where-Object {$_ -like 'agent-ops-*'})) 'Loose entries left'
}
Test 'an outdated bootstrap is reported; a current one is not' {
    $old=Machine -modernBoot $false
    Assert ((Sync $old).Bootstrap -eq 'OUTDATED') 'Old bootstrap not reported'
    Assert ((Sync (Machine)).Bootstrap -eq 'OK') 'Current bootstrap reported as outdated'
}
Test 'at session start the adjustment runs only when the active version changed' {
    $m=Machine
    $first=Invoke-AgentOpsIntegrationsIfNeeded -StateDir $m.State -HomeDir $m.Home -AntigravityValidator $okPlugin
    Assert ($first.Status -eq 'SYNCED') ($first|ConvertTo-Json -Depth 4)
    $again=Invoke-AgentOpsIntegrationsIfNeeded -StateDir $m.State -HomeDir $m.Home -AntigravityValidator $okPlugin
    Assert ($again.Status -eq 'SKIPPED') 'Ran again with the same version'
    $s=[IO.File]::ReadAllText((Join-Path $m.State 'update-state.json')) -replace ('a'*40),('b'*40);[IO.File]::WriteAllText((Join-Path $m.State 'update-state.json'),$s,$utf8)
    $next=Invoke-AgentOpsIntegrationsIfNeeded -StateDir $m.State -HomeDir $m.Home -AntigravityValidator $okPlugin
    Assert ($next.Status -in @('SYNCED','UP_TO_DATE')) 'Did not run after an update'
    $none=Join-Path $script:base 'nostate';[IO.Directory]::CreateDirectory($none)|Out-Null
    Assert ((Invoke-AgentOpsIntegrationsIfNeeded -StateDir $none -HomeDir $m.Home).Status -eq 'NOT_INSTALLED') 'No installation must do nothing'
}
Test 'updating the bootstrap uses the real hub and targets of this installation and skips the scheduled task' {
    $m=Machine -modernBoot $false;$script:got=$null
    $runner={param($installer,$hub,$targets) $script:got=@{Installer=$installer;Hub=$hub;Targets=$targets};0}
    $r=Update-AgentOpsBootstrap -StateDir $m.State -Runner $runner
    $w=[IO.File]::ReadAllText((Join-Path $m.State 'watch-config.json'))|ConvertFrom-Json
    Assert ($r.Code -eq 0 -and $script:got.Hub -eq $w.HubDir -and (@($script:got.Targets) -join ';') -eq (@($w.Targets) -join ';') -and $script:got.Installer -like '*install.ps1') ($script:got|ConvertTo-Json -Depth 4)
}
Test 'a state folder other than the real one never touches the real user folder unless one is given' {
    $m=Machine
    $r=Sync-AgentOpsIntegrations -StateDir $m.State -AntigravityValidator $okPlugin
    Assert ($r.Code -eq 0 -and $r.Status -eq 'ISOLATED' -and -not @($r.Files).Count) ($r|ConvertTo-Json -Depth 4)
    $i=Invoke-AgentOpsIntegrationsIfNeeded -StateDir $m.State -AntigravityValidator $okPlugin
    Assert ($i.Status -eq 'ISOLATED') ($i|ConvertTo-Json -Depth 4)
    Assert (-not [IO.File]::Exists((Join-Path $m.State 'integrations.json'))) 'Recorded an adjustment that did not happen'
}
Write-Host "Integrations: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
