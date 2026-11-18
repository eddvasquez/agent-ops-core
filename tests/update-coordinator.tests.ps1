# All repositories, installations and profiles below are temporary fixtures.
[CmdletBinding()]
param([string]$Filter='')
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/UpdateCoordinator.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-update-tests-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$script:proof={param($repo,$sha,$seconds) @{Verified=$true;Sha=$sha;Summary=@('Fixture release');Workflow='windows-tests.yml'}}
$script:tasks={param($action,$config) if($action -eq 'Suspend'){@{Present=$false;Enabled=$false;Running=$false}}else{@{Healthy=$true}}}
function Assert($condition,$message){if(-not $condition){throw $message}}
function Test($name,[scriptblock]$body){if($Filter -and $name -notmatch $Filter){return};try{& $body;$script:passed++;Write-Host "PASS $name"}catch{$script:failed++;Write-Host "FAIL $name : $_";Write-Host $_.ScriptStackTrace}}
function Put($root,$key,$text){$path=Join-Path $root $key;[IO.Directory]::CreateDirectory((Split-Path -Parent $path))|Out-Null;[IO.File]::WriteAllText($path,$text)}
function Fixture {
    param([switch]$Templates)
    $root=Join-Path $script:base ('with spaces-'+[guid]::NewGuid().ToString('N'))
    $remote=Join-Path $root 'remote';$install=Join-Path $root 'bootstrap'
    [IO.Directory]::CreateDirectory($remote)|Out-Null
    Copy-Item -LiteralPath (Join-Path $source 'scripts') -Destination $remote -Recurse
    Copy-Item -LiteralPath (Join-Path $source 'release-contract.json') -Destination $remote
    if($Templates){Copy-Item -LiteralPath (Join-Path $source 'templates') -Destination $remote -Recurse}
    foreach($name in @('dev-systematic-debugging','dev-tdd','ops-git-worktrees','ops-project-init','ops-project-migrate','ops-session-handoff')){Put $remote "skills/$name/SKILL.md" 'core v1'}
    Put $remote 'README.md' 'Fixture v1'
    & git init -q -b main $remote
    & git -C $remote -c core.autocrlf=false add .
    & git -C $remote -c user.name=Tests -c user.email=tests@localhost commit -q -m 'fixture v1'
    if($LASTEXITCODE -ne 0){throw 'Fixture commit failed'}
    & git -C $remote branch stable
    [IO.Directory]::CreateDirectory($install)|Out-Null
    Copy-Item -LiteralPath (Join-Path $remote 'scripts') -Destination $install -Recurse
    $p=@{InstallRoot=$install;RepoUrl=$remote;StateDir=(Join-Path $root 'state');RuntimeDir=(Join-Path $root 'runtime');HubDir=(Join-Path $root 'hub');Targets=@((Join-Path $root 'target'));WatcherEnabled=$false}
    $r=Initialize-AgentOpsUpdate @p -Verifier $script:proof -TaskController $script:tasks
    Assert ($r.Code -eq 0) ($r|ConvertTo-Json -Depth 8)
    return @{Parameters=$p;Remote=$remote;ConfigPath=(Join-Path $p.StateDir 'watch-config.json');OldSha=(git -C $remote rev-parse HEAD);StatePath=(Join-Path $p.StateDir 'update-state.json')}
}
function Publish($f,$text='core v2'){
    Put $f.Remote 'skills/dev-tdd/SKILL.md' $text
    & git -C $f.Remote -c core.autocrlf=false add .
    & git -C $f.Remote -c user.name=Tests -c user.email=tests@localhost commit -q -m 'fixture v2'
    if($LASTEXITCODE -ne 0){throw 'Fixture update failed'}
    & git -C $f.Remote branch -f stable HEAD
    return (git -C $f.Remote rev-parse HEAD)
}
function Run($f,$action='Check',$session='A',$sha='') {
    Invoke-AgentOpsUpdate -ConfigPath $f.ConfigPath -Action $action -SessionId $session -BeginSession -CandidateSha $sha -Verifier $script:proof -TaskController $script:tasks
}
Test 'check offers a verified update and truthful estimate without touching active profiles' {
    $f=Fixture;$new=Publish $f;$r=Run $f
    Assert ($r.Code -eq 0 -and $r.Status -eq 'UPDATE_AVAILABLE' -and $r.NeedsUserChoice) ($r|ConvertTo-Json -Depth 8)
    Assert ($r.ActiveSha -eq $f.OldSha -and $r.CandidateSha -eq $new) 'Version identities wrong'
    Assert (-not $r.Estimate.Measured -and $r.Estimate.NetworkBudgetSeconds -eq 120) 'Invented first-run estimate'
    Assert ([IO.File]::ReadAllText((Join-Path $f.Parameters.Targets[0] 'dev-tdd/SKILL.md')) -eq 'core v1') 'Check applied the update'
}
Test 'background preparation consent activates only in a different work session' {
    $f=Fixture;$new=Publish $f;Run $f|Out-Null
    $r=Run $f 'Prepare' 'A' $new
    Assert ($r.Code -eq 0 -and $r.Status -eq 'READY_NEXT_SESSION' -and $r.ActiveSha -eq $f.OldSha) ($r|ConvertTo-Json -Depth 8)
    $r=Run $f 'Check' 'A'
    Assert ($r.Status -eq 'READY_NEXT_SESSION' -and -not $r.NeedsUserChoice) 'Repeated prompt or same-session activation'
    $r=Run $f 'Check' 'B'
    Assert ($r.Code -eq 0 -and $r.Status -eq 'UPDATED' -and $r.ActiveSha -eq $new) ($r|ConvertTo-Json -Depth 8)
    Assert ([IO.File]::ReadAllText((Join-Path $f.Parameters.Targets[0] 'dev-tdd/SKILL.md')) -eq 'core v2') 'New session did not synchronize'
}
Test 'update now prepares and activates exactly the approved SHA' {
    $f=Fixture;$new=Publish $f;Run $f|Out-Null;$r=Run $f 'Apply' 'A' $new
    Assert ($r.Code -eq 0 -and $r.ActiveSha -eq $new -and $r.LastGoodSha -eq $new) ($r|ConvertTo-Json -Depth 8)
    Assert ([IO.Directory]::Exists($r.ActivePath) -and [IO.Directory]::Exists((Join-Path $f.Parameters.RuntimeDir ('releases/'+$f.OldSha)))) 'Previous code environment lost'
}
Test 'defer suppresses repeated prompts only for that candidate and session' {
    $f=Fixture;$new=Publish $f;Run $f|Out-Null
    Assert ((Run $f 'Defer' 'A' $new).Status -eq 'DEFERRED') 'Defer failed'
    Assert (-not (Run $f 'Check' 'A').NeedsUserChoice) 'Repeated prompt'
    Assert ((Run $f 'Check' 'B').NeedsUserChoice) 'Deferral unexpectedly permanent'
    Assert (-not [IO.Directory]::Exists((Join-Path $f.Parameters.RuntimeDir ('releases/'+$new)))) 'Defer downloaded code'
}
Test 'failed download preserves last good release; offline starts use verified current release' {
    $f=Fixture;$new=Publish $f;Run $f|Out-Null
    $failure={param($arguments,$seconds) throw 'simulated network loss'}
    $r=Invoke-AgentOpsUpdate -ConfigPath $f.ConfigPath -Action Prepare -SessionId A -CandidateSha $new -GitRunner $failure -TaskController $script:tasks
    Assert ($r.Code -eq 1 -and $r.ActiveSha -eq $f.OldSha -and $r.LastGoodSha -eq $f.OldSha) 'Failed candidate replaced good state'
    $r=Invoke-AgentOpsUpdate -ConfigPath $f.ConfigPath -Action Check -SessionId B -BeginSession -GitRunner $failure -TaskController $script:tasks
    Assert ($r.Status -eq 'OFFLINE_CACHED' -and $r.ActiveSha -eq $f.OldSha) 'Offline fallback failed'
}
Test 'state schema, source identity and remote SHA validated before use' {
    $f=Fixture
    $r=Invoke-AgentOpsUpdate -ConfigPath $f.ConfigPath -RepoUrl 'https://example.test/other' -Verifier $script:proof
    Assert ($r.Code -eq 1) 'Wrong repository reused cache'
    $invalid={param($arguments,$seconds) @{ExitCode=0;Output="not-a-sha`trefs/heads/stable";Error=''}}
    Assert ((Invoke-AgentOpsUpdate -ConfigPath $f.ConfigPath -GitRunner $invalid -Verifier $script:proof).Code -eq 1) 'Invalid SHA accepted'
    [IO.File]::WriteAllText($f.StatePath,'[]')
    Assert ((Run $f).Code -eq 1) 'Wrong JSON schema accepted'
    Assert ([IO.File]::ReadAllText($f.StatePath) -eq '[]') 'Corrupt state was silently replaced'
}
Test 'tampered prepared code is rejected and good release remains active' {
    $f=Fixture;$new=Publish $f;Run $f|Out-Null;$ready=Run $f 'Prepare' 'A' $new
    Put (Join-Path $f.Parameters.RuntimeDir ('releases/'+$new)) 'scripts/sync-skills.ps1' 'tampered'
    $r=Run $f 'Apply' 'A' $new
    Assert ($r.Code -eq 1 -and $r.ActiveSha -eq $f.OldSha) 'Tampered release activated'
}
Test 'WhatIf never changes state, launches workers or installs a candidate' {
    $f=Fixture;$new=Publish $f;Run $f|Out-Null;$before=[IO.File]::ReadAllText($f.StatePath)
    $r=Invoke-AgentOpsUpdate -ConfigPath $f.ConfigPath -Action Apply -SessionId A -CandidateSha $new -WhatIf -Verifier $script:proof
    Assert ($r.Code -eq 0 -and [IO.File]::ReadAllText($f.StatePath) -eq $before) 'WhatIf changed state'
    Assert (-not [IO.Directory]::Exists((Join-Path $f.Parameters.RuntimeDir ('releases/'+$new)))) 'WhatIf prepared release'
}
Test 'real hidden background worker prepares once without activating in its parent session' {
    $f=Fixture;$new=Publish $f;Run $f|Out-Null
    $r=Invoke-AgentOpsUpdate -ConfigPath $f.ConfigPath -Action Prepare -SessionId A -CandidateSha $new -Background -TaskController $script:tasks
    Assert ($r.Code -eq 0 -and $r.Status -eq 'PREPARING' -and $r.WorkerId -gt 0) ($r|ConvertTo-Json -Depth 8)
    $again=Invoke-AgentOpsUpdate -ConfigPath $f.ConfigPath -Action Prepare -SessionId A -CandidateSha $new -Background -TaskController $script:tasks
    Assert ($again.Code -eq 3 -or $again.WorkerId -eq $r.WorkerId -or $again.Status -eq 'READY_NEXT_SESSION') 'Duplicate worker request was not coalesced'
    $deadline=[datetime]::UtcNow.AddSeconds(25)
    do{$status=Run $f 'Check' 'A';if($status.Code -eq 0 -and $status.Status -eq 'READY_NEXT_SESSION'){break};Start-Sleep -Milliseconds 200}while([datetime]::UtcNow -lt $deadline)
    Assert ($status.Code -eq 0 -and $status.CandidateStatus -eq 'READY') 'Worker did not finish preparing'
    $state=Get-Content -LiteralPath $f.StatePath -Raw|ConvertFrom-Json
    Assert ($state.Active.Sha -eq $f.OldSha -and $state.LastGood.Sha -eq $f.OldSha) 'Worker activated code'
    Assert ((Run $f 'Check' 'A').ActiveSha -eq $f.OldSha) 'Parent session unexpectedly upgraded'
}
Test 'failed health check rolls back code pointer, configuration and unchanged deployment files' {
    $f=Fixture;$new=Publish $f;Run $f|Out-Null
    $badHealth={param($action,$config,$previous) if($action -eq 'Suspend'){@{Present=$false;Enabled=$false;Running=$false}}else{@{Healthy=$false}}}
    $r=Invoke-AgentOpsUpdate -ConfigPath $f.ConfigPath -Action Apply -SessionId A -CandidateSha $new -Verifier $script:proof -TaskController $badHealth
    Assert ($r.Code -eq 1 -and $r.ActiveSha -eq $f.OldSha -and $r.LastGoodSha -eq $f.OldSha) ($r|ConvertTo-Json -Depth 8)
    Assert ([IO.File]::ReadAllText((Join-Path $f.Parameters.Targets[0] 'dev-tdd/SKILL.md')) -eq 'core v1') 'Failed update left a mixed deployment'
    $cfg=Get-Content -LiteralPath $f.ConfigPath -Raw|ConvertFrom-Json
    Assert ($cfg.FrameworkDir -eq $r.ActivePath) 'Failed update left candidate configuration active'
}
Test 'public skill customization conflicts block activation and preserve personal content' {
    $f=Fixture
    Put $f.Parameters.HubDir 'dev-tdd/SKILL.md' 'my customization'
    $active=(Get-Content -LiteralPath $f.ConfigPath -Raw|ConvertFrom-Json).FrameworkDir
    Import-Module (Join-Path $active 'scripts/SkillsSync.psm1') -Force
    Invoke-SkillSync -HubDir $f.Parameters.HubDir -Targets $f.Parameters.Targets -StateDir $f.Parameters.StateDir -FrameworkDir $active -Mode Apply|Out-Null
    $new=Publish $f;Run $f|Out-Null;$r=Run $f 'Apply' 'A' $new
    Assert ($r.Code -eq 2 -and $r.Status -eq 'SKILL_CONFLICT' -and $r.ActiveSha -eq $f.OldSha) ($r|ConvertTo-Json -Depth 8)
    Assert ([IO.File]::ReadAllText((Join-Path $f.Parameters.HubDir 'dev-tdd/SKILL.md')) -eq 'my customization') 'Customization lost'
}
Test 'unverified candidates are never offered; moving stable does not substitute approval' {
    $f=Fixture;$new=Publish $f
    $r=Invoke-AgentOpsUpdate -ConfigPath $f.ConfigPath -Verifier {param($r,$s,$t) @{Verified=$false;Sha=$s;Summary=@()}}
    Assert ($r.Code -eq 2 -and -not $r.NeedsUserChoice) 'Unverified update offered'
    Run $f|Out-Null;Publish $f 'core v3'|Out-Null
    $r=Run $f 'Apply' 'A' $new
    Assert ($r.Code -eq 1 -and $r.ActiveSha -eq $f.OldSha) 'An unapproved SHA was substituted'
}
Test 'scheduled check cannot activate a prepared update; private skills stay out of release and deployment' {
    $f=Fixture;Put $f.Parameters.HubDir 'private-client/SKILL.md' 'personal material'
    $new=Publish $f;Run $f|Out-Null;Run $f 'Prepare' 'A' $new|Out-Null
    $r=Invoke-AgentOpsUpdate -ConfigPath $f.ConfigPath -Action Check -Verifier $script:proof -TaskController $script:tasks
    Assert ($r.ActiveSha -eq $f.OldSha) 'Scheduled check activated an update'
    $r=Run $f 'Check' 'B'
    Assert ($r.Code -eq 0 -and $r.ActiveSha -eq $new) 'Next-session activation failed'
    Assert (-not [IO.Directory]::Exists((Join-Path $r.ActivePath 'skills/private-client'))) 'Personal skill entered release cache'
    Assert (-not [IO.Directory]::Exists((Join-Path $f.Parameters.Targets[0] 'private-client'))) 'Updater distributed personal skills outside its scope'
}
function CrashActivation($f,$sha){
    $configLiteral=$f.ConfigPath.Replace("'","''");$moduleLiteral=(Join-Path $f.Parameters.InstallRoot 'scripts/UpdateCoordinator.psm1').Replace("'","''")
    $body='Import-Module '''+$moduleLiteral+''' -Force; $controller={param($action,$config,$previous) if($action -eq "Suspend"){@{Present=$false;Enabled=$false;Running=$false}}else{[Environment]::Exit(99)}}; Invoke-AgentOpsUpdate -ConfigPath '''+$configLiteral+''' -Action Apply -SessionId A -CandidateSha '''+$sha+''' -TaskController $controller|Out-Null'
    $encoded=[Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($body))
    $child=Start-Process -FilePath (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList @('-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand',$encoded) -WindowStyle Hidden -PassThru
    try{if(-not $child.WaitForExit(20000)){$child.Kill();throw 'Crash fixture timed out'};Assert ($child.ExitCode -eq 99) ('Crash fixture did not reach probing: '+$child.ExitCode)}finally{$child.Dispose()}
}
Test 'abrupt exit after deployment is recovered before starting the next session' {
    $f=Fixture;$new=Publish $f;Run $f|Out-Null;Run $f 'Prepare' 'A' $new|Out-Null
    CrashActivation $f $new
    Assert ([IO.File]::Exists((Join-Path $f.Parameters.StateDir 'activation-pending.json'))) 'Crash journal missing'
    $r=Run $f 'Check' 'B'
    Assert ($r.Code -eq 0 -and $r.Status -eq 'RECOVERED' -and $r.ActiveSha -eq $f.OldSha) ($r|ConvertTo-Json -Depth 8)
    Assert ([IO.File]::ReadAllText((Join-Path $f.Parameters.Targets[0] 'dev-tdd/SKILL.md')) -eq 'core v1') 'Recovery left candidate files active'
}
Test 'recovery preserves edits made after an interrupted deployment and blocks activation' {
    $f=Fixture;$new=Publish $f;Run $f|Out-Null;Run $f 'Prepare' 'A' $new|Out-Null;CrashActivation $f $new
    Put $f.Parameters.Targets[0] 'dev-tdd/SKILL.md' 'edited after crash'
    $r=Run $f 'Check' 'B'
    Assert ($r.Code -eq 2 -and $r.Status -eq 'ACTIVATION_REVIEW_REQUIRED') ($r|ConvertTo-Json -Depth 8)
    Assert ([IO.File]::ReadAllText((Join-Path $f.Parameters.Targets[0] 'dev-tdd/SKILL.md')) -eq 'edited after crash') 'Post-crash edit overwritten'
    Assert ([IO.File]::Exists((Join-Path $f.Parameters.StateDir 'activation-pending.json'))) 'Review guard removed prematurely'
}
Test 'watcher entry starts the pinned runtime and reports its SHA during activation probing' {
    $f=Fixture;$new=Publish $f;Run $f|Out-Null;$global:AocProbeChild=$null
    $controller={param($action,$config,$previous)
        if($action -eq 'Suspend'){return @{Present=$false;Enabled=$false;Running=$false}}
        $arguments='-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "'+(Join-Path $config.InstallRoot 'scripts/watch-entry.ps1')+'" -ConfigPath "'+(Join-Path $config.StateDir 'watch-config.json')+'" -RunSeconds 3'
        $global:AocProbeChild=Start-Process -FilePath (Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe') -ArgumentList $arguments -WindowStyle Hidden -PassThru
        $heartbeat=Join-Path $config.StateDir 'watch-heartbeat.json';$deadline=[datetime]::UtcNow.AddSeconds(6)
        while(-not [IO.File]::Exists($heartbeat) -and [datetime]::UtcNow -lt $deadline){Start-Sleep -Milliseconds 100}
        return @{Healthy=[IO.File]::Exists($heartbeat)}
    }
    try{
        $r=Invoke-AgentOpsUpdate -ConfigPath $f.ConfigPath -Action Apply -SessionId A -CandidateSha $new -Verifier $script:proof -TaskController $controller
        Assert ($r.Code -eq 0 -and $r.ActiveSha -eq $new) ($r|ConvertTo-Json -Depth 8)
        $heartbeat=Get-Content -LiteralPath (Join-Path $f.Parameters.StateDir 'watch-heartbeat.json') -Raw|ConvertFrom-Json
        Assert ($heartbeat.Sha -eq $new -and $heartbeat.FrameworkDir -eq $r.ActivePath) 'Wrong watcher version loaded'
    }finally{if($global:AocProbeChild){if(-not $global:AocProbeChild.WaitForExit(6000)){$global:AocProbeChild.Kill();$global:AocProbeChild.WaitForExit()};$global:AocProbeChild.Dispose()};Remove-Variable AocProbeChild -Scope Global -ErrorAction SilentlyContinue}
}
Test 'measured total estimate adds preparation and activation instead of averaging the two phases' {
    $f=Fixture;$new=Publish $f
    $s=Get-Content -LiteralPath $f.StatePath -Raw|ConvertFrom-Json
    $s.Samples.PrepareSeconds=@(12,14,16);$s.Samples.ActivateSeconds=@(3,4,5)
    [IO.File]::WriteAllText($f.StatePath,($s|ConvertTo-Json -Depth 40))
    $r=Run $f
    Assert ($r.Estimate.Measured -and $r.Estimate.MinimumSeconds -eq 13 -and $r.Estimate.MaximumSeconds -eq 27) 'Estimate underestimated combined phases'
    Run $f 'Prepare' 'A' $new|Out-Null;$r=Run $f 'Check' 'A'
    Assert ($r.Estimate.Measured -and $r.Estimate.MinimumSeconds -eq 3 -and $r.Estimate.MaximumSeconds -eq 6) 'Ready candidate estimate still includes download time'
}
Test 'CI service outage after Git check preserves usable installed version and previous approval' {
    $f=Fixture;$new=Publish $f
    $r=Invoke-AgentOpsUpdate -ConfigPath $f.ConfigPath -BeginSession -SessionId A -Verifier {param($r,$s,$t) throw 'simulated CI service unavailable'}
    Assert ($r.Status -eq 'OFFLINE_CACHED' -and $r.CanStartWork -and $r.ActiveSha -eq $f.OldSha) ($r|ConvertTo-Json -Depth 8)
}
Test 'worker identity survives ISO timestamps parsed as DateTime' {
    & (Get-Module UpdateCoordinator) {
        $p=Get-Process -Id $PID
        try{$record=@{Id=$PID;StartedUtc=$p.StartTime.ToUniversalTime()};if(-not (Up-WorkerAlive $record)){throw 'DateTime worker identity rejected'}}finally{$p.Dispose()}
    }
}
Test 'manual sync dispatches the immutable active engine instead of a changed bootstrap engine' {
    $f=Fixture
    $enginePath=Join-Path $f.Parameters.InstallRoot 'scripts/SkillsSync.psm1'
    $stub=@'
function Invoke-SkillSync {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param($HubDir,$Targets,$StateDir,$FrameworkDir,$Mode,$Key,$VersionHash,$SkillNames)
    return [pscustomobject]@{Code=99;Copied=0;Removed=0;Conflicts=@();Deletions=@()}
}
Export-ModuleMember -Function Invoke-SkillSync
'@
    [IO.File]::AppendAllText($enginePath,"`n"+$stub)
    $json=& (Join-Path $f.Parameters.InstallRoot 'scripts/sync-skills.ps1') -HubDir $f.Parameters.HubDir -Targets $f.Parameters.Targets -StateDir $f.Parameters.StateDir -Mode Verify -Json|Out-String
    Assert ($LASTEXITCODE -eq 0 -and ($json|ConvertFrom-Json).Code -eq 0) 'Manual CLI ran the mutable bootstrap engine'
    Import-Module (Join-Path $source 'scripts/UpdateCoordinator.psm1') -Force
}
Test 'ISO-shaped session identifiers remain strings across JSON round trips' {
    $f=Fixture;$new=Publish $f;$session='2026-11-18T10:00:00Z'
    Run $f 'Check' $session|Out-Null
    Run $f 'Prepare' $session $new|Out-Null
    $r=Run $f 'Check' $session
    Assert ($r.Code -eq 0 -and $r.Status -eq 'READY_NEXT_SESSION' -and $r.ActiveSha -eq $f.OldSha) 'Session identity changed during JSON deserialization'
}
Test 'atomic state writes tolerate a short-lived concurrent reader' {
    $path=Join-Path $script:base 'reader-state.json';$module=Get-Module UpdateCoordinator|Where-Object {$_.Path -eq (Join-Path $source 'scripts/UpdateCoordinator.psm1')}|Select-Object -First 1
    & $module {param($p) Up-Write $p @{Value='before'}} $path
    $handle=[IO.File]::Open($path,'Open','Read','Read')
    $timer=New-Object Timers.Timer;$timer.Interval=100;$timer.AutoReset=$false
    $id='AocReader.'+[guid]::NewGuid().ToString('N')
    $subscription=Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier $id -MessageData $handle -Action {$event.MessageData.Dispose()}
    try{
        $timer.Start();& $module {param($p) Up-Write $p @{Value='after'}} $path
        Assert ((Get-Content -LiteralPath $path -Raw|ConvertFrom-Json).Value -eq 'after') 'Atomic state replacement failed after reader released'
    }finally{$handle.Dispose();$timer.Stop();$timer.Dispose();Unregister-Event -SourceIdentifier $id -ErrorAction SilentlyContinue;Remove-Job -Job $subscription -Force -ErrorAction SilentlyContinue}
}
Test 'a valid zip with altered bytes is rejected against the exact Git object IDs' {
    $f=Fixture;$new=Publish $f;Run $f|Out-Null;$runtimeRoot=$f.Parameters.RuntimeDir
    $corrupt={param($arguments,$seconds)
        $r=& (Get-Module UpdateCoordinator) {param($a,$t) Up-Git $a $t $null} $arguments $seconds
        if($arguments -contains 'archive' -and $r.ExitCode -eq 0){
            $zipPath=(@($arguments|Where-Object {$_ -like '--output=*'})[0]).Substring(9)
            if(-not [IO.Path]::GetFullPath($zipPath).StartsWith($runtimeRoot+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Corruption fixture escaped its runtime directory'}
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $zip=[IO.Compression.ZipFile]::Open($zipPath,[IO.Compression.ZipArchiveMode]::Update)
            try{$zip.GetEntry('README.md').Delete();$entry=$zip.CreateEntry('README.md');$writer=New-Object IO.StreamWriter($entry.Open());try{$writer.Write('altered archive bytes')}finally{$writer.Dispose()}}finally{$zip.Dispose()}
        }
        return $r
    }.GetNewClosure()
    $r=Invoke-AgentOpsUpdate -ConfigPath $f.ConfigPath -Action Prepare -SessionId A -CandidateSha $new -GitRunner $corrupt -TaskController $script:tasks
    Assert ($r.Code -eq 1 -and $r.ActiveSha -eq $f.OldSha -and $r.CandidateStatus -ne 'READY') 'Zip corruption was accepted as the tested commit'
}
Test 'checks preserve an in-progress approved candidate without asking again' {
    $f=Fixture;$new=Publish $f;Run $f|Out-Null
    $s=Get-Content -LiteralPath $f.StatePath -Raw|ConvertFrom-Json
    $s.Candidate.Status='PREPARING';$s.Candidate.Approved=$true;$s.Candidate.SessionId='A'
    $s.Candidate.Worker=@{Id=$PID;StartedUtc=(Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')}
    [IO.File]::WriteAllText($f.StatePath,($s|ConvertTo-Json -Depth 40))
    $r=Run $f 'Check' 'B'
    Assert ($r.Code -eq 0 -and $r.Status -eq 'PREPARING' -and -not $r.NeedsUserChoice -and $r.ActiveSha -eq $f.OldSha) 'Check asked again or changed an in-progress approval'
}
Test 'a delayed worker cannot restore consent revoked before it starts' {
    $f=Fixture;$new=Publish $f;Run $f|Out-Null
    $s=Get-Content -LiteralPath $f.StatePath -Raw|ConvertFrom-Json
    $s.Candidate.Status='PREPARING';$s.Candidate.Approved=$false;$s.Candidate.SessionId='A'
    [IO.File]::WriteAllText($f.StatePath,($s|ConvertTo-Json -Depth 40))
    $r=Invoke-AgentOpsUpdate -ConfigPath $f.ConfigPath -Action Prepare -Worker -SessionId A -CandidateSha $new -TaskController $script:tasks
    $after=Get-Content -LiteralPath $f.StatePath -Raw|ConvertFrom-Json
    Assert ($r.Code -eq 0 -and -not $after.Candidate.Approved -and $after.Candidate.Status -ne 'READY' -and $r.ActiveSha -eq $f.OldSha) 'Delayed worker restored revoked approval'
}
Test 'migration CLI runs from the verified active release with registered configuration' {
    $f=Fixture -Templates;$project=Join-Path (Split-Path $f.Parameters.StateDir) 'client-project'
    [IO.Directory]::CreateDirectory($project)|Out-Null
    $state=Get-Content $f.StatePath -Raw|ConvertFrom-Json
    $entry=Join-Path $state.Active.Path 'scripts/migrate-project.ps1'
    $json=& (Get-Process -Id $PID).Path -NoProfile -ExecutionPolicy Bypass -File $entry -ProjectPath $project -ConfigPath $f.ConfigPath -Mode Apply|Out-String
    Assert ($LASTEXITCODE -eq 0 -and ($json|ConvertFrom-Json).Status -eq 'MIGRATED') ('Managed CLI failed: '+$json)
}
Write-Host "Update results: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if($script:failed){exit 1}
