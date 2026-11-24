[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$cli=Join-Path $repo 'scripts/sync-skills.ps1'
$watch=Join-Path $repo 'scripts/watch-skills.ps1'
$task=Join-Path $repo 'scripts/manage-skills-watcher.ps1'
$base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-integration-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($base) | Out-Null
$failures=0; $passed=0
function Assert($condition,$message){if(-not $condition){throw $message}}
function Test($name,[scriptblock]$body){try{& $body; $script:passed++; Write-Host "PASS $name"}catch{$script:failures++; Write-Host "FAIL $name : $_"; Write-Host $_.ScriptStackTrace}}
function Config {
    $root=Join-Path $base ([guid]::NewGuid().ToString('N'))
    return @{HubDir=(Join-Path $root 'hub'); Targets=@((Join-Path $root 'target')); StateDir=(Join-Path $root 'state'); FrameworkDir=''}
}
function Seed($p){[IO.Directory]::CreateDirectory((Join-Path $p.HubDir 'demo'))|Out-Null; [IO.File]::WriteAllText((Join-Path $p.HubDir 'demo/SKILL.md'),'base')}
Test 'downloaded installer via IEX reaches URL validation without a null cmdlet' {
    # Invalid source stops before Git, task registration or profile writes.
    $sourcePath=(Join-Path $repo 'install.ps1').Replace("'","''")
    $body="Invoke-Expression ([IO.File]::ReadAllText('$sourcePath').Replace('https://github.com/eddvasquez/agent-ops-core.git','invalid-fixture'))"
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
    $output=& (Get-Process -Id $PID).Path -NoProfile -EncodedCommand $encoded 2>&1|Out-String
    Assert ($LASTEXITCODE -eq 1 -and $output -match 'Managed installs require HTTPS' -and $output -notmatch 'NULL') ('IEX entry failed before URL validation: '+$output)
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes(('$WhatIfPreference=$true;'+$body)))
    $output=& (Get-Process -Id $PID).Path -NoProfile -EncodedCommand $encoded 2>&1|Out-String
    Assert ($LASTEXITCODE -eq 0 -and $output -match 'What if:' -and $output -notmatch 'Managed installs require HTTPS') 'IEX ignored inherited WhatIf preference'
}
Test 'standalone CLIs resolve default framework paths before doing any work' {
    $p=Config;$engine=(Get-Process -Id $PID).Path
    $json=& $engine -NoProfile -ExecutionPolicy Bypass -File $cli -HubDir $p.HubDir -Targets $p.Targets[0] -StateDir $p.StateDir -Mode Plan -WhatIf -Json|Out-String
    Assert ($LASTEXITCODE -eq 0 -and ($json|ConvertFrom-Json).Code -eq 0) 'Standalone sync default path failed'
    & $engine -NoProfile -ExecutionPolicy Bypass -File $task -HubDir $p.HubDir -Targets $p.Targets[0] -StateDir $p.StateDir -Action Status -WhatIf|Out-Null
    Assert ($LASTEXITCODE -eq 0 -and -not [IO.Directory]::Exists($p.StateDir)) 'Standalone task manager default path failed or wrote state'
}
Test 'CLI failure exits 1; WhatIf is read-only; repeated application copies nothing' {
    $p=Config; Seed $p
    $json=& $cli @p -Mode Apply -WhatIf -Json | Out-String
    Assert ($LASTEXITCODE -eq 0 -and -not [IO.Directory]::Exists($p.StateDir)) 'CLI WhatIf wrote state'
    $json=& $cli @p -Mode Apply -Json | Out-String
    Assert ($LASTEXITCODE -eq 0) $json
    $json=& $cli @p -Mode Apply -Json | Out-String
    Assert (($json|ConvertFrom-Json).Copied -eq 0) 'CLI not idempotent'
    [IO.File]::WriteAllText((Join-Path $base 'blocked'),'file')
    $p.Targets=@((Join-Path $base 'blocked'))
    $json=& $cli @p -Mode Apply -Json | Out-String
    Assert ($LASTEXITCODE -eq 1) 'CLI native status missing'
}
Test 'watcher reconciles on startup and responds to actual replica event' {
    $p=Config; Seed $p; $config=Join-Path (Split-Path $p.HubDir -Parent) 'config.json'
    [IO.File]::WriteAllText($config,($p|ConvertTo-Json))
    $timer=New-Object Timers.Timer; $timer.Interval=200; $timer.AutoReset=$true
    $timerId='AocTest.'+[guid]::NewGuid().ToString('N')
    $message=@{Timer=$timer;State=(Join-Path $p.StateDir 'state.json');Target=(Join-Path $p.Targets[0] 'demo/SKILL.md')}
    $subscription=Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier $timerId -MessageData $message -Action {
        if([IO.File]::Exists($event.MessageData.State)){$event.MessageData.Timer.Stop();[IO.File]::WriteAllText($event.MessageData.Target,'replica edit')}
    }
    try {
        $timer.Start(); & $watch -ConfigPath $config -RunSeconds 7
        Assert ([IO.File]::ReadAllText((Join-Path $p.HubDir 'demo/SKILL.md')) -eq 'replica edit') 'Watcher missed replica edit'
        Assert (Test-Path -LiteralPath (Join-Path $p.StateDir 'watcher.jsonl')) 'Watcher log missing'
    } finally { $timer.Stop(); $timer.Dispose(); Unregister-Event -SourceIdentifier $timerId -ErrorAction SilentlyContinue; Remove-Job -Job $subscription -Force -ErrorAction SilentlyContinue }
}
Test 'watcher logs transient read failure and retries without a new file event' {
    $p=Config; Seed $p; $config=Join-Path (Split-Path $p.HubDir -Parent) 'config.json'; [IO.File]::WriteAllText($config,($p|ConvertTo-Json))
    $handle=[IO.File]::Open((Join-Path $p.HubDir 'demo/SKILL.md'),'Open','ReadWrite','None')
    $timer=New-Object Timers.Timer; $timer.Interval=200; $timer.AutoReset=$true
    $timerId='AocTest.'+[guid]::NewGuid().ToString('N')
    $message=@{Timer=$timer;Handle=$handle;Log=(Join-Path $p.StateDir 'watcher.jsonl')}
    $subscription=Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier $timerId -MessageData $message -Action {
        if([IO.File]::Exists($event.MessageData.Log)){$event.MessageData.Timer.Stop();$event.MessageData.Handle.Dispose()}
    }
    try {
        $timer.Start(); & $watch -ConfigPath $config -RunSeconds 7
        Assert (Test-Path -LiteralPath (Join-Path $p.Targets[0] 'demo/SKILL.md')) 'Watcher failed to retry'
        $lines=@(Get-Content -LiteralPath (Join-Path $p.StateDir 'watcher.jsonl') | ForEach-Object {$_|ConvertFrom-Json})
        Assert (@($lines|Where-Object Code -eq 1).Count -gt 0) 'Failure not logged'
        Assert (@($lines|Where-Object Code -eq 0).Count -gt 0) 'Recovery not logged'
    } finally { $handle.Dispose(); $timer.Stop(); $timer.Dispose(); Unregister-Event -SourceIdentifier $timerId -ErrorAction SilentlyContinue; Remove-Job -Job $subscription -Force -ErrorAction SilentlyContinue }
}
Test 'task configuration WhatIf does not create config or touch scheduled tasks' {
    $p=Config; Seed $p
    & $task @p -Action Enable -WhatIf
    Assert (-not [IO.Directory]::Exists($p.StateDir)) 'Task WhatIf wrote configuration'
}
Test 'task lifecycle uses hidden logon action and refuses an unrelated task (mocked Windows scheduler)' {
    $p=Config;Seed $p
    $global:AocFakeTask=$null;$global:AocTaskCalls=New-Object 'Collections.Generic.List[string]'
    function global:Get-ScheduledTask {[CmdletBinding()]param($TaskName) return $global:AocFakeTask}
    function global:New-ScheduledTaskAction {param($Execute,$Argument) return [pscustomobject]@{Execute=$Execute;Arguments=$Argument}}
    function global:New-ScheduledTaskTrigger {param([switch]$AtLogOn,$User) return @{AtLogOn=[bool]$AtLogOn;User=$User}}
    function global:New-ScheduledTaskPrincipal {param($UserId,$LogonType,$RunLevel) return @{UserId=$UserId;LogonType=$LogonType;RunLevel=$RunLevel}}
    function global:New-ScheduledTaskSettingsSet {param([switch]$AllowStartIfOnBatteries,[switch]$DontStopIfGoingOnBatteries,[switch]$StartWhenAvailable,$MultipleInstances,$ExecutionTimeLimit,$RestartCount,$RestartInterval) return $PSBoundParameters}
    function global:Register-ScheduledTask {param($TaskName,$Action,$Trigger,$Principal,$Settings,[switch]$Force) $global:AocFakeTask=[pscustomobject]@{Actions=@($Action);Trigger=$Trigger;Settings=$Settings};$global:AocTaskCalls.Add('register')}
    function global:Start-ScheduledTask {param($TaskName) $global:AocTaskCalls.Add('start')}
    function global:Stop-ScheduledTask {param($TaskName) $global:AocTaskCalls.Add('stop')}
    function global:Disable-ScheduledTask {param($TaskName) $global:AocTaskCalls.Add('disable')}
    function global:Unregister-ScheduledTask {[CmdletBinding(SupportsShouldProcess=$true)]param($TaskName) $global:AocTaskCalls.Add('remove')}
    $functions=@('Get-ScheduledTask','New-ScheduledTaskAction','New-ScheduledTaskTrigger','New-ScheduledTaskPrincipal','New-ScheduledTaskSettingsSet','Register-ScheduledTask','Start-ScheduledTask','Stop-ScheduledTask','Disable-ScheduledTask','Unregister-ScheduledTask')
    try {
        & $task @p -Action Enable
        Assert ($global:AocFakeTask.Actions[0].Arguments.Contains('-WindowStyle Hidden')) 'Visible watcher configured'
        Assert $global:AocFakeTask.Trigger.AtLogOn 'Not a logon task'
        Assert ([timespan]$global:AocFakeTask.Settings.ExecutionTimeLimit -eq [timespan]::Zero) 'Watcher expires after default task limit'
        Import-Module (Join-Path $repo 'scripts/UpdateCoordinator.psm1') -Force
        Initialize-AgentOpsUpdate -InstallRoot $repo -RepoUrl 'https://github.com/eddvasquez/agent-ops-core' -StateDir $p.StateDir -HubDir $p.HubDir -Targets $p.Targets -WatcherEnabled $false -LocalDevelopment|Out-Null
        # No explicit FrameworkDir: the task manager must resolve the registered
        # runtime without losing its own helper commands during module reload.
        & $task -StateDir $p.StateDir -Action Enable
        $registered=Get-Content -LiteralPath (Join-Path $p.StateDir 'watch-config.json') -Raw|ConvertFrom-Json
        Assert ($registered.HubDir -eq $p.HubDir -and $registered.FrameworkDir -eq $repo) 'Registered paths were replaced by defaults'
        & $task @p -Action Disable
        & $task @p -Action Remove
        Assert ($global:AocTaskCalls -contains 'disable' -and $global:AocTaskCalls -contains 'remove') 'Lifecycle incomplete'
        $global:AocFakeTask=[pscustomobject]@{Actions=@([pscustomobject]@{Arguments='foreign task'})}
        $refused=$false;try{& $task @p -Action Remove}catch{$refused=$true}
        Assert $refused 'Foreign task touched'
    }finally{foreach($name in $functions){Remove-Item -LiteralPath ('Function:\'+$name) -ErrorAction SilentlyContinue};Remove-Variable AocFakeTask,AocTaskCalls -Scope Global -ErrorAction SilentlyContinue}
}
Test 'explicit local development install never auto-pulls; existing non-Git folder preserved' {
    $remote=Join-Path $base 'remote';[IO.Directory]::CreateDirectory($remote)|Out-Null
    foreach($name in @('install.ps1','update.ps1','scripts','release-contract.json')){Copy-Item -LiteralPath (Join-Path $repo $name) -Destination $remote -Recurse}
    foreach($name in @('dev-systematic-debugging','dev-tdd','ops-git-worktrees','ops-project-init','ops-project-migrate','ops-session-handoff')){
        $dir=Join-Path $remote "skills/$name";[IO.Directory]::CreateDirectory($dir)|Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'SKILL.md'),'upstream v1')
    }
    & git init -q -b main $remote
    & git -C $remote -c core.autocrlf=false add .
    & git -C $remote -c user.name=Tests -c user.email=tests@localhost commit -q -m fixture
    Assert ($LASTEXITCODE -eq 0) 'Fixture Git commit failed'
    $p=Config;$installed=Join-Path (Split-Path $p.HubDir -Parent) 'installed'
    & (Join-Path $repo 'install.ps1') -RepoUrl $remote -TargetDir $installed -HubDir $p.HubDir -Targets $p.Targets -StateDir $p.StateDir -SkipTask -LocalDevelopment
    Assert ($LASTEXITCODE -eq 0) 'Installation failed'
    Assert ([IO.File]::Exists((Join-Path $p.Targets[0] 'dev-tdd/SKILL.md'))) 'Installer did not distribute core'
    $settingsPath=Join-Path $p.StateDir 'update-state.json'
    $settings=Get-Content -LiteralPath $settingsPath -Raw|ConvertFrom-Json
    $settings.Config.WatcherEnabled=$true
    [IO.File]::WriteAllText($settingsPath,($settings|ConvertTo-Json -Depth 40))
    & (Join-Path $repo 'install.ps1') -RepoUrl $remote -TargetDir $installed -HubDir $p.HubDir -Targets $p.Targets -StateDir $p.StateDir -SkipTask -LocalDevelopment
    Assert ($LASTEXITCODE -eq 0 -and (Get-Content -LiteralPath $settingsPath -Raw|ConvertFrom-Json).Config.WatcherEnabled) 'Skipping task registration changed the saved watcher preference'
    [IO.File]::WriteAllText((Join-Path $remote 'skills/dev-tdd/SKILL.md'),'upstream v2')
    & git -C $remote -c core.autocrlf=false add .
    & git -C $remote -c user.name=Tests -c user.email=tests@localhost commit -q -m update
    & (Join-Path $installed 'update.ps1') -ConfigPath (Join-Path $p.StateDir 'watch-config.json') -Force
    Assert ($LASTEXITCODE -eq 0) 'Update failed'
    Assert ([IO.File]::ReadAllText((Join-Path $p.Targets[0] 'dev-tdd/SKILL.md')) -eq 'upstream v1') 'Development install was updated without a decision'
    $occupied=Join-Path $base 'occupied';[IO.Directory]::CreateDirectory($occupied)|Out-Null
    [IO.File]::WriteAllText((Join-Path $occupied 'keep.txt'),'keep')
    & (Join-Path $repo 'install.ps1') -RepoUrl $remote -TargetDir $occupied -HubDir $p.HubDir -Targets $p.Targets -StateDir $p.StateDir -SkipTask -LocalDevelopment
    Assert ($LASTEXITCODE -eq 1 -and [IO.File]::ReadAllText((Join-Path $occupied 'keep.txt')) -eq 'keep') 'Installer removed existing folder'
}
Write-Host "Integration results: $passed passed, $failures failed. Fixtures: $base"
if(-not $failures){Remove-TestFixtures $base}
if($failures){exit 1}
