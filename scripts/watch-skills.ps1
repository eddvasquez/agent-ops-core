[CmdletBinding()]
param([string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'),
      [ValidateRange(0,86400)][int]$RunSeconds=0,[string]$ReleaseSha='')
$ErrorActionPreference='Stop'
$watchLibrary=Import-Module (Join-Path $PSScriptRoot 'SkillsSync.psm1') -Force -PassThru
$raw=Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
$invoke=@{HubDir=[string]$raw.HubDir;Targets=[string[]]$raw.Targets;StateDir=[string]$raw.StateDir;FrameworkDir=[string]$raw.FrameworkDir}
$validated=Get-SkillSyncConfiguration @invoke
$identity=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
$mutex=New-Object Threading.Mutex($false,(& $watchLibrary {param($d) Get-SyncWatcherMutexName $d} $validated.StateDir)); $owned=$false
$watchers=@(); $ids=@(); $prefix='AOC.'+[guid]::NewGuid().ToString('N')+'.'
function Write-WatchLog($r,$scope) {
    # Validate again before logging in case an ancestor was replaced by a link.
    $safe=Get-SkillSyncConfiguration @invoke
    [IO.Directory]::CreateDirectory($safe.StateDir)|Out-Null
    $line=@{Utc=[datetime]::UtcNow.ToString('o');Code=$r.Code;Copied=$r.Copied;Removed=$r.Removed;Conflicts=$r.Conflicts;Deletions=$r.Deletions;Issues=$r.Issues;Scope=@($scope);RescueManifest=$r.RescueManifest}|ConvertTo-Json -Depth 15 -Compress
    $log=Join-Path $safe.StateDir 'watcher.jsonl'
    if([IO.File]::Exists($log) -and ([IO.File]::GetAttributes($log) -band [IO.FileAttributes]::ReparsePoint)){throw 'Watcher log is a link.'}
    [IO.File]::AppendAllText($log,$line+[Environment]::NewLine,(New-Object Text.UTF8Encoding $false))
}
try {
    try {$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
    if(-not $owned){Write-Host 'A skills watcher is already running for this user.'; exit 3}
    if($ReleaseSha){
        if($ReleaseSha -notmatch '^[a-f0-9]{40}$'){throw 'Invalid watcher release SHA.'}
        $verified=Get-AgentOpsActiveRelease -ConfigPath $ConfigPath -ForWatcher
        if($verified.Sha -ne $ReleaseSha -or $verified.Path -ne $invoke.FrameworkDir){throw 'Watcher runtime/configuration mismatch.'}
        $heartbeat=@{Sha=$ReleaseSha;FrameworkDir=$invoke.FrameworkDir;ProcessId=$PID;Utc=[datetime]::UtcNow.ToString('o')}
        & $watchLibrary {param($d,$h) Write-SyncJson (Get-SyncChild $d 'watch-heartbeat.json') $h} $invoke.StateDir $heartbeat
    }
    foreach($root in $validated.Roots) {
        if($root.Role -ne 'framework'){[IO.Directory]::CreateDirectory($root.Path)|Out-Null}
        if(-not [IO.Directory]::Exists($root.Path)){throw "Watcher source missing: $($root.Path)"}
        $w=New-Object IO.FileSystemWatcher $root.Path
        $w.IncludeSubdirectories=$true; $w.NotifyFilter=[IO.NotifyFilters]'FileName,DirectoryName,LastWrite,Size'
        foreach($eventName in @('Changed','Created','Deleted','Renamed','Error')) {
            $id=$prefix+$root.Id+'.'+$eventName
            Register-ObjectEvent -InputObject $w -EventName $eventName -SourceIdentifier $id|Out-Null
            $ids+=$id
        }
        $w.EnableRaisingEvents=$true; $watchers+=$w
    }
    $clock=[Diagnostics.Stopwatch]::StartNew(); $pending=@{}; $first=$null; $last=0
    $nextFull=0; $retryAt=$null; $retryScope=@(); $retryIndex=0; $lastCode=0
    while($RunSeconds -eq 0 -or $clock.Elapsed.TotalSeconds -lt $RunSeconds) {
        if([IO.File]::Exists((Join-Path $invoke.StateDir 'activation-pending.json'))){Wait-Event -Timeout 1|Out-Null;continue}
        foreach($e in @(Get-Event|Where-Object {$_.SourceIdentifier.StartsWith($prefix)})) {
            if($e.SourceIdentifier.EndsWith('.Error')) {$nextFull=0}
            else {
                $names=@($e.SourceEventArgs.Name)
                if($e.SourceIdentifier.EndsWith('.Renamed')){$names+=@($e.SourceEventArgs.OldName)}
                foreach($name in $names) {
                    if($name -and $name -notmatch '(^|[/\\])\.aoc-[a-f0-9]{32}\.tmp$') {
                        $skill=($name -split '[/\\]')[0]
                        $pending[$skill]=$true
                        if($null -eq $first){$first=$clock.Elapsed.TotalSeconds}
                        $last=$clock.Elapsed.TotalSeconds
                    }
                }
            }
            Remove-Event -EventIdentifier $e.EventIdentifier
        }
        $now=$clock.Elapsed.TotalSeconds; $scope=$null
        if($now -ge $nextFull){$scope=@();$nextFull=$now+300;$pending=@{};$first=$null}
        elseif($null -ne $retryAt -and $now -ge $retryAt){$scope=@($retryScope);$retryAt=$null}
        elseif($pending.Count -and (($now-$last) -ge 1.5 -or ($now-$first) -ge 5)){$scope=@($pending.Keys);$pending=@{};$first=$null}
        if($null -ne $scope) {
            if($ReleaseSha){
                $verified=Get-AgentOpsActiveRelease -ConfigPath $ConfigPath
                if($verified.Sha -ne $ReleaseSha -or $verified.Path -ne $invoke.FrameworkDir){throw 'Active runtime changed; restart the watcher before synchronization.'}
            }
            $r=Invoke-SkillSync @invoke -Mode Apply -SkillNames $scope
            $lastCode=$r.Code; Write-WatchLog $r $scope
            if($r.Code -in @(1,3)) {
                if($retryIndex -lt 3){$retryAt=$clock.Elapsed.TotalSeconds+@(1,2,4)[$retryIndex];$retryScope=@($scope);$retryIndex++}
                else{$retryAt=$null;$retryIndex=0}
            } else {$retryIndex=0;$retryAt=$null}
        }
        # Timeout is bounded; events only request work, the engine proves content equality.
        Wait-Event -Timeout 1 | Out-Null
    }
    exit $lastCode
} finally {
    foreach($id in $ids){Unregister-Event -SourceIdentifier $id -ErrorAction SilentlyContinue; Get-Event -SourceIdentifier $id -ErrorAction SilentlyContinue|Remove-Event}
    foreach($w in $watchers){$w.Dispose()}
    if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()
}
