# Stable bootstrap protocol v1. Windows PowerShell 5.1 and PowerShell 7.
Set-StrictMode -Version 2
$script:library=Import-Module (Join-Path $PSScriptRoot 'SkillsSync.psm1') -Force -PassThru
$script:core=@('dev-systematic-debugging','dev-tdd','ops-git-worktrees','ops-project-init','ops-project-migrate','ops-session-handoff')
function Up-Root($path){& $script:library {param($p) Get-SyncRoot $p} $path}
function Up-Child($root,$key){& $script:library {param($r,$k) Get-SyncChild $r $k} $root $key}
function Up-Hash($path){& $script:library {param($p) Get-SyncHash $p} $path}
function Up-Write($path,$value){& $script:library {param($p,$v) Write-SyncJson $p $v} $path $value}
function Up-Read($path){
    # New PowerShell versions otherwise coerce ISO-looking identifiers to dates.
    $share=[IO.FileShare]([int][IO.FileShare]::ReadWrite -bor [int][IO.FileShare]::Delete)
    $stream=[IO.File]::Open($path,'Open','Read',$share)
    $reader=New-Object IO.StreamReader($stream,[Text.Encoding]::UTF8,$true)
    try{$json=$reader.ReadToEnd()}finally{$reader.Dispose()}
    if((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')){$value=ConvertFrom-Json $json -DateKind String}
    else{$value=ConvertFrom-Json $json}
    & $script:library {param($v) ConvertTo-SyncMap $v} $value
}
function Up-Mutex($name){New-Object Threading.Mutex($false,('Local\AgentOps'+$name+'-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))}
function Up-Lock($mutex,[int]$milliseconds=0){try{return $mutex.WaitOne($milliseconds)}catch [Threading.AbandonedMutexException]{return $true}}
function Up-Arguments([string[]]$values){
    $quoted=foreach($v in $values){
        if($v -and $v -notmatch '[\s"]'){$v}else{'"'+[regex]::Replace([regex]::Replace([string]$v,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'}
    }
    return ($quoted -join ' ')
}
function Up-Git([string[]]$arguments,[double]$seconds=5,$runner=$null){
    if($runner){return (& $runner $arguments $seconds)}
    if($seconds -le 0){throw [TimeoutException]::new('Git time budget exhausted.')}
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=(Get-Command git.exe -ErrorAction Stop).Source
    $info.Arguments=Up-Arguments $arguments
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true;$info.WindowStyle='Hidden'
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.StandardOutputEncoding=[Text.Encoding]::UTF8;$info.StandardErrorEncoding=[Text.Encoding]::UTF8
    $info.EnvironmentVariables['GIT_TERMINAL_PROMPT']='0';$info.EnvironmentVariables['GCM_INTERACTIVE']='Never'
    $process=New-Object Diagnostics.Process;$process.StartInfo=$info
    try{
        [void]$process.Start()
        $stdout=$process.StandardOutput.ReadToEndAsync();$stderr=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit([int][math]::Ceiling($seconds*1000))){
            if(-not $process.HasExited){
                if($process.GetType().GetMethod('Kill',[type[]]@([bool]))){$process.Kill($true)}
                else{
                    $stop=New-Object Diagnostics.ProcessStartInfo
                    $stop.FileName=Join-Path $env:WINDIR 'System32/taskkill.exe';$stop.Arguments="/PID $($process.Id) /T /F"
                    $stop.UseShellExecute=$false;$stop.CreateNoWindow=$true;$stop.WindowStyle='Hidden'
                    $stop.RedirectStandardOutput=$true;$stop.RedirectStandardError=$true
                    $killer=[Diagnostics.Process]::Start($stop);[void]$killer.WaitForExit(5000);$killer.Dispose()
                }
            }
            throw [TimeoutException]::new('Git operation timed out.')
        }
        return @{ExitCode=$process.ExitCode;Output=$stdout.GetAwaiter().GetResult();Error=$stderr.GetAwaiter().GetResult()}
    }finally{$process.Dispose()}
}
function Up-GitOk($arguments,$seconds,$runner){
    $r=Up-Git $arguments $seconds $runner
    # Deliberately do not include credential-helper output or URLs in errors.
    if($r.ExitCode -ne 0){throw 'Git operation failed (network, credentials, channel or local repository unavailable).'}
    return [string]$r.Output
}
function Up-Repo([string]$url){
    if([string]::IsNullOrWhiteSpace($url)){throw 'Repository URL required.'}
    if($url -match '^https://'){
        $uri=[uri]$url
        if($uri.UserInfo -or $uri.Query -or $uri.Fragment){throw 'Credentials/query strings must not be embedded in repository URLs.'}
        return $url.TrimEnd('/') -replace '\.git$',''
    }
    if([IO.Path]::IsPathRooted($url)){return (Up-Root $url)}
    throw 'Use an HTTPS repository URL or an explicit local development repository.'
}
function Up-CIProof($repo,$sha,[double]$seconds){
    $uri=[uri]$repo
    if($uri.Scheme -ne 'https' -or $uri.Host -ne 'github.com' -or $uri.AbsolutePath -notmatch '^/[^/]+/[^/]+$'){return @{Verified=$false;Sha=$sha;Summary=@()}}
    if($seconds -le 0){throw [TimeoutException]::new('Check time budget exhausted.')}
    Add-Type -AssemblyName System.Net.Http
    $client=New-Object Net.Http.HttpClient
    try{
        $client.Timeout=[timespan]::FromSeconds($seconds)
        [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent','AgentOps-Update/1')
        [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('Accept','application/vnd.github+json')
        [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('X-GitHub-Api-Version','2022-11-28')
        if($env:GITHUB_TOKEN){$client.DefaultRequestHeaders.Authorization=New-Object Net.Http.Headers.AuthenticationHeaderValue('Bearer',$env:GITHUB_TOKEN)}
        $url='https://api.github.com/repos'+$uri.AbsolutePath+'/actions/workflows/windows-tests.yml/runs?event=push&status=success&head_sha='+$sha+'&per_page=100'
        $response=$client.GetAsync($url).GetAwaiter().GetResult()
        try{
            if(-not $response.IsSuccessStatusCode){throw ('CI verification unavailable (HTTP '+[int]$response.StatusCode+').')}
            $body=$response.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json
            $runs=@($body.workflow_runs|Where-Object {$_.head_sha -eq $sha -and $_.head_branch -eq 'main' -and $_.event -eq 'push' -and $_.status -eq 'completed' -and $_.conclusion -eq 'success'})
            $summary=@();if($runs.Count){$summary=@(([string]$runs[0].display_title -replace '[\x00-\x1f]',' ').Substring(0,[math]::Min(300,([string]$runs[0].display_title).Length)))}
            return @{Verified=($runs.Count -gt 0);Sha=$sha;Summary=$summary;Workflow='windows-tests.yml'}
        }finally{$response.Dispose()}
    }finally{$client.Dispose()}
}
function Up-Paths($config){
    foreach($name in @('InstallRoot','StateDir','RuntimeDir','HubDir')){$config[$name]=Up-Root $config[$name]}
    $config.Targets=@($config.Targets|ForEach-Object {Up-Root $_})
    $all=@($config.InstallRoot,$config.StateDir,$config.RuntimeDir,$config.HubDir)+@($config.Targets)
    for($i=0;$i -lt $all.Count;$i++){for($j=$i+1;$j -lt $all.Count;$j++){
        if($all[$i] -eq $all[$j] -or $all[$i].StartsWith($all[$j]+'\',[StringComparison]::OrdinalIgnoreCase) -or $all[$j].StartsWith($all[$i]+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Bootstrap, runtime, state, hub and replicas must be distinct, non-overlapping roots.'}
    }}
}
function Up-State($configPath){
    $configPath=[IO.Path]::GetFullPath($configPath)
    $stateDir=Up-Root (Split-Path -Parent $configPath)
    Up-Child $stateDir ([IO.Path]::GetFileName($configPath))|Out-Null
    $path=Up-Child $stateDir 'update-state.json'
    $s=Up-Read $path
    if($s -isnot [hashtable] -or $s.SchemaVersion -ne 1 -or $s.Identity -isnot [hashtable] -or $s.Config -isnot [hashtable] -or $s.Candidate -isnot [hashtable] -or $s.Samples -isnot [hashtable]){throw 'Invalid update state schema; existing state is preserved.'}
    if($s.Identity.Channel -ne 'stable' -or (Up-Repo $s.Identity.RepoUrl) -ne $s.Identity.RepoUrl){throw 'Invalid update source identity.'}
    if($s.Mode -notin @('MANAGED','LOCAL_DEV') -or $s.Config.WatcherEnabled -isnot [bool]){throw 'Invalid installation mode/settings.'}
    Up-Paths $s.Config
    if($s.Config.StateDir -ne $stateDir){throw 'Update state is bound to a different directory.'}
    foreach($record in @($s.Active,$s.LastGood)){
        if($null -ne $record -and ($record -isnot [hashtable] -or $record.Sha -notmatch '^[a-f0-9]{40}$' -or $record.Path -ne (Up-Child $s.Config.RuntimeDir ('releases/'+$record.Sha)))){throw 'Invalid active release record.'}
    }
    if($s.Candidate.Count -and ($s.Candidate.Sha -notmatch '^[a-f0-9]{40}$' -or $s.Candidate.Status -notin @('DETECTED','PREPARING','READY','FAILED'))){throw 'Invalid candidate state.'}
    if($s.Candidate.Count -and ($s.Candidate.Approved -isnot [bool] -or $s.Candidate.VerifiedCI -isnot [bool] -or $s.Candidate.Worker -isnot [hashtable] -or $s.Candidate.SessionId -isnot [string])){throw 'Invalid candidate consent/proof.'}
    foreach($sample in @($s.Samples.PrepareSeconds)+@($s.Samples.ActivateSeconds)){if($sample -isnot [ValueType] -or [double]$sample -le 0 -or [double]::IsNaN([double]$sample) -or [double]::IsInfinity([double]$sample)){throw 'Invalid update timing measurements.'}}
    $sync=Up-Read $configPath
    if($sync.HubDir -ne $s.Config.HubDir -or $sync.StateDir -ne $stateDir -or @(Compare-Object @($sync.Targets|Sort-Object) @($s.Config.Targets|Sort-Object)).Count){throw 'Synchronization configuration changed; review before updating.'}
    if($s.Active -and -not [IO.File]::Exists((Join-Path $stateDir 'activation-pending.json')) -and $sync.FrameworkDir -ne $s.Active.Path){throw 'Active runtime and synchronization configuration disagree.'}
    return $s
}
function Up-Save($s){Up-Write (Up-Child $s.Config.StateDir 'update-state.json') $s}
function Up-Estimate($s){
    $prepared=$s.Candidate.Count -and $s.Candidate.Status -eq 'READY'
    $measured=$s.Samples.ActivateSeconds.Count -ge 3 -and ($prepared -or $s.Samples.PrepareSeconds.Count -ge 3)
    $low=$null;$high=$null
    if($measured){
        $mean=($s.Samples.ActivateSeconds|Measure-Object -Average).Average
        if(-not $prepared){$mean+=($s.Samples.PrepareSeconds|Measure-Object -Average).Average}
        $low=[math]::Max(1,[math]::Floor($mean*0.75));$high=[math]::Max($low+1,[math]::Ceiling($mean*1.5))
    }
    return @{Measured=[bool]$measured;MinimumSeconds=$low;MaximumSeconds=$high;NetworkBudgetSeconds=120;CheckBudgetSeconds=5;Prepared=[bool]$prepared;Note=if($measured){'Estimate based on previous successful operations on this machine; not a deadline.'}else{'No reliable measurements yet. Remote check: up to 5 seconds; preparation network budget: 120 seconds. Activation may take additional time.'}}
}
function Up-Result($s,[string]$status,[int]$code=0){
    $blocked=$s -and [IO.File]::Exists((Join-Path $s.Config.StateDir 'activation-pending.json'))
    return [ordered]@{Code=$code;Status=$status;SessionId=$null;CanStartWork=[bool]($s -and ($s.Active -or $s.Mode -eq 'LOCAL_DEV') -and -not $blocked);ActiveSha=if($s -and $s.Active){$s.Active.Sha}else{$null};ActivePath=if($s -and $s.Active -and -not $blocked){$s.Active.Path}elseif($s -and $s.Mode -eq 'LOCAL_DEV' -and -not $blocked){$s.Config.InstallRoot}else{$null};LastGoodSha=if($s -and $s.LastGood){$s.LastGood.Sha}else{$null};CandidateSha=if($s -and $s.Candidate.Count){$s.Candidate.Sha}else{$null};CandidateStatus=if($s -and $s.Candidate.Count){$s.Candidate.Status}else{$null};NeedsUserChoice=$false;Choices=@('Apply','Prepare','Defer');Summary=@(if($s -and $s.Candidate.Count){$s.Candidate.Summary});Estimate=if($s){Up-Estimate $s}else{$null};WorkerId=if($s -and $s.Candidate.Count -and $s.Candidate.Worker.Count){$s.Candidate.Worker.Id}else{$null};Issues=@()}
}
function Up-AllowedFile([string]$path){
    if($path -match '(^|/)[^/]*\.env($|\.)|(^|/)(credentials|secrets)(\.|/)|(^|/)[^/]*(token|credential|secret)[^/]*\.(json|toml|ya?ml|key|pem|pfx|p12)$|\.py[co]$|(^|/)__pycache__/'){return $false}
    if($path -match '^skills/([^/]+)/'){
        if($Matches[1] -in $script:core){return $true}
        return ($path -match '^skills/scripts/(rescue_local_edits|sync_hub_to_gemini|watch_skills_hub)\.ps1$')
    }
    if($path -match '^skills/'){return $path -match '^skills/(pull_replica_to_hub|setup_ai_skills_machine|setup_antigravity_machine|sync_antigravity_junctions)\.bat$'}
    return ($path -match '^(scripts|templates|tests|docs|\.github)/' -or $path -in @('.gitignore','README.md','LICENSE','install.ps1','install.sh','update.ps1','update.sh','release-contract.json'))
}
function Up-ValidateRelease($s,$record){
    if($record.Sha -notmatch '^[a-f0-9]{40}$'){throw 'Invalid release SHA.'}
    $root=Up-Child $s.Config.RuntimeDir ('releases/'+$record.Sha)
    if($record.Path -ne $root){throw 'Release path does not match its SHA.'}
    $manifest=Up-Read (Up-Child $root '.agent-ops-release.json')
    if($manifest.SchemaVersion -ne 1 -or $manifest.Sha -ne $record.Sha -or $manifest.RepoUrl -ne $s.Identity.RepoUrl -or $manifest.Channel -ne 'stable' -or -not $manifest.VerifiedCI){throw 'Release source/proof mismatch.'}
    $seen=@{}
    foreach($f in $manifest.Files){
        if(-not (Up-AllowedFile $f.Path) -or $seen.ContainsKey($f.Path) -or $f.Hash -notmatch '^[a-f0-9]{64}$'){throw 'Invalid release manifest file.'}
        $seen[$f.Path]=$true
        if((Up-Hash (Up-Child $root $f.Path)) -ne $f.Hash){throw ('Release content changed: '+$f.Path)}
    }
    $stack=New-Object 'Collections.Generic.Stack[string]';$stack.Push($root)
    while($stack.Count){
        foreach($path in [IO.Directory]::EnumerateFileSystemEntries($stack.Pop())){
            $relative=$path.Substring($root.Length+1).Replace('\','/');Up-Child $root $relative|Out-Null
            if([IO.Directory]::Exists($path)){$stack.Push($path)}
            elseif($relative -ne '.agent-ops-release.json' -and -not $seen.ContainsKey($relative)){throw 'Unexpected file in immutable release.'}
        }
    }
    $contract=Up-Read (Up-Child $root 'release-contract.json')
    if($contract.ProtocolVersion -ne 1 -or $contract.SyncStateSchema -ne 1 -or @(Compare-Object @($contract.CoreSkills|Sort-Object) @($script:core|Sort-Object)).Count){throw 'Release requires a different bootstrap protocol or skill catalogue.'}
    foreach($name in $script:core){if(-not $seen.ContainsKey("skills/$name/SKILL.md")){throw 'Incomplete public skill catalogue.'}}
    foreach($required in @('scripts/SkillsSync.psm1','scripts/UpdateCoordinator.psm1','scripts/start-session.ps1','scripts/update-worker.ps1','scripts/watch-entry.ps1','scripts/watch-skills.ps1','scripts/manage-skills-watcher.ps1')){if(-not $seen.ContainsKey($required)){throw ('Incomplete runtime: '+$required)}}
    return $root
}
function Up-GitBlobHash($path){
    $stream=[IO.File]::Open($path,'Open','Read','Read')
    $sha=[Security.Cryptography.SHA1]::Create()
    try{
        $header=[Text.Encoding]::ASCII.GetBytes(('blob '+$stream.Length+"`0"))
        [void]$sha.TransformBlock($header,0,$header.Length,$header,0)
        $buffer=New-Object byte[] 65536
        while(($count=$stream.Read($buffer,0,$buffer.Length)) -gt 0){[void]$sha.TransformBlock($buffer,0,$count,$buffer,0)}
        [void]$sha.TransformFinalBlock((New-Object byte[] 0),0,0)
        return ([BitConverter]::ToString($sha.Hash)).Replace('-','').ToLowerInvariant()
    }finally{$stream.Dispose();$sha.Dispose()}
}
function Up-Prepare($s,$runner){
    $clock=[Diagnostics.Stopwatch]::StartNew();$sha=$s.Candidate.Sha
    if(-not $s.Candidate.VerifiedCI){throw 'Candidate has not passed the trusted CI workflow.'}
    $record=@{Sha=$sha;Path=(Up-Child $s.Config.RuntimeDir ('releases/'+$sha))}
    if([IO.Directory]::Exists($record.Path)){Up-ValidateRelease $s $record|Out-Null;$s.Candidate.Path=$record.Path;$s.Candidate.Status='READY';Up-Save $s;return}
    $s.Candidate.Status='PREPARING';Up-Save $s
    $cache=Up-Child $s.Config.RuntimeDir 'repository.git'
    if(-not [IO.Directory]::Exists($cache)){
        Up-GitOk @('init','--bare',$cache) (120-$clock.Elapsed.TotalSeconds) $runner|Out-Null
        Up-GitOk @('--git-dir',$cache,'remote','add','origin',$s.Identity.RepoUrl) (120-$clock.Elapsed.TotalSeconds) $runner|Out-Null
    }
    $origin=(Up-GitOk @('--git-dir',$cache,'remote','get-url','origin') (120-$clock.Elapsed.TotalSeconds) $runner).Trim()
    if((Up-Repo $origin) -ne $s.Identity.RepoUrl){throw 'Cached repository identity mismatch.'}
    Up-GitOk @('--git-dir',$cache,'fetch','--no-tags','--depth=1','origin','refs/heads/stable') (120-$clock.Elapsed.TotalSeconds) $runner|Out-Null
    $fetched=(Up-GitOk @('--git-dir',$cache,'rev-parse','FETCH_HEAD') (120-$clock.Elapsed.TotalSeconds) $runner).Trim()
    if($fetched -ne $sha){throw 'Stable moved after approval; check again instead of substituting a different candidate.'}
    $tree=Up-GitOk @('--git-dir',$cache,'ls-tree','-r','-z',$sha) (120-$clock.Elapsed.TotalSeconds) $runner
    $expected=@{}
    foreach($line in @($tree -split "`0"|Where-Object {$_})){
        if($line -notmatch '^(100644|100755) blob ([a-f0-9]{40})\t(.+)$'){throw 'Release contains a link, submodule or unsupported object.'}
        $path=$Matches[3]
        if(-not (Up-AllowedFile $path) -or $expected.ContainsKey($path)){throw ('Unexpected/private file in public release: '+$path)}
        $expected[$path]=$Matches[2]
    }
    if($expected.Count -gt 512){throw 'Release exceeds file-count limit.'}
    [IO.Directory]::CreateDirectory((Up-Child $s.Config.RuntimeDir 'releases'))|Out-Null
    $stage=Up-Child $s.Config.RuntimeDir ('releases/.pending-'+[guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($stage)|Out-Null
    $zipPath=Up-Child $s.Config.RuntimeDir ('candidate-'+[guid]::NewGuid().ToString('N')+'.zip')
    Up-GitOk @('-c','core.autocrlf=false','-c','core.eol=lf','--git-dir',$cache,'archive','--format=zip',('--output='+$zipPath),$sha) (120-$clock.Elapsed.TotalSeconds) $runner|Out-Null
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip=[IO.Compression.ZipFile]::OpenRead($zipPath);$files=@();$seen=@{};$total=0
    try{
        foreach($entry in $zip.Entries){
            if($clock.Elapsed.TotalSeconds -gt 120){throw [TimeoutException]::new('Preparation budget exhausted; active release unchanged.')}
            $path=$entry.FullName
            $destination=Up-Child $stage $path
            if($path.EndsWith('/')){continue}
            if(-not $expected.ContainsKey($path) -or $seen.ContainsKey($path) -or $entry.Length -gt 10485760){throw 'Unexpected, duplicated or oversized archive member.'}
            $total+=$entry.Length;if($total -gt 52428800){throw 'Release exceeds total size limit.'}
            [IO.Directory]::CreateDirectory((Split-Path -Parent $destination))|Out-Null
            $inputStream=$entry.Open();$outputStream=[IO.File]::Open($destination,'CreateNew','Write','None')
            try{$inputStream.CopyTo($outputStream);$outputStream.Flush($true)}finally{$outputStream.Dispose();$inputStream.Dispose()}
            if((Up-GitBlobHash $destination) -ne $expected[$path]){throw ('Archive bytes differ from the approved Git object: '+$path)}
            if($path -match '\.ps(m)?1$'){
                $errors=$null;$tokens=$null
                [void][Management.Automation.Language.Parser]::ParseFile($destination,[ref]$tokens,[ref]$errors)
                if($errors){throw ('Invalid PowerShell syntax in release: '+$path)}
            }
            $seen[$path]=$true;$files+=@{Path=$path;Hash=(Up-Hash $destination);Length=$entry.Length}
        }
    }finally{$zip.Dispose()}
    if($seen.Count -ne $expected.Count){throw 'Incomplete archive.'}
    Up-Write (Up-Child $stage '.agent-ops-release.json') @{SchemaVersion=1;Sha=$sha;RepoUrl=$s.Identity.RepoUrl;Channel='stable';VerifiedCI=$true;Files=$files}
    # Rename is on the same volume. No existing version is overwritten.
    [IO.Directory]::Move($stage,$record.Path)
    Up-ValidateRelease $s $record|Out-Null
    [IO.File]::Delete($zipPath)
    $s.Candidate.Path=$record.Path;$s.Candidate.Status='READY';$s.Candidate.Worker=@{}
    $s.Samples.PrepareSeconds=@(@($s.Samples.PrepareSeconds)+@($clock.Elapsed.TotalSeconds)|Select-Object -Last 10)
    Up-Save $s
}

function Up-Task($action,$config,$previous=$null){
    if(-not $config.WatcherEnabled){return @{Present=$false;Enabled=$false;Running=$false;Healthy=$true}}
    $task=Get-ScheduledTask -TaskName 'AgentOpsSkillsWatcher' -ErrorAction SilentlyContinue
    $entry=Join-Path $config.InstallRoot 'scripts/watch-entry.ps1'
    $legacy=Join-Path $config.InstallRoot 'scripts/watch-skills.ps1'
    $configPath=Join-Path $config.StateDir 'watch-config.json'
    if($task -and -not @($task.Actions|Where-Object {($_.Arguments.Contains('"'+$entry+'"') -or $_.Arguments.Contains('"'+$legacy+'"')) -and $_.Arguments.Contains('"'+$configPath+'"')}).Count){throw 'Watcher task belongs to a different installation.'}
    if($action -eq 'Suspend'){
        $result=@{Present=[bool]$task;Enabled=($task -and $task.State -ne 'Disabled');Running=($task -and $task.State -eq 'Running')}
        if($task){Stop-ScheduledTask -TaskName 'AgentOpsSkillsWatcher';Disable-ScheduledTask -TaskName 'AgentOpsSkillsWatcher'|Out-Null}
        return $result
    }
    if($previous -and $previous.Present -and $previous.Enabled){
        $heartbeat=Up-Child $config.StateDir 'watch-heartbeat.json'
        if([IO.File]::Exists($heartbeat)){[IO.File]::Delete($heartbeat)}
        Enable-ScheduledTask -TaskName 'AgentOpsSkillsWatcher'|Out-Null;Start-ScheduledTask -TaskName 'AgentOpsSkillsWatcher'
        $expected=Up-State $configPath;$deadline=[datetime]::UtcNow.AddSeconds(10)
        while([datetime]::UtcNow -lt $deadline){
            if([IO.File]::Exists($heartbeat)){
                try{$beat=Up-Read $heartbeat;if($beat.Sha -eq $expected.Active.Sha -and $beat.FrameworkDir -eq $expected.Active.Path){return @{Healthy=$true}}}catch{}
            }
            Start-Sleep -Milliseconds 100
        }
        return @{Healthy=$false}
    }
    return @{Healthy=$true}
}
function Up-Snapshot($s,$key){
    $path=Up-Child $s.Config.StateDir $key
    $hash=if([IO.File]::Exists($path)){Up-Hash $path}else{'-'}
    if($hash -ne '-') {& $script:library {param($d,$p,$h) Save-SyncBlob $d $p $h} $s.Config.StateDir $path $hash|Out-Null}
    return @{Key=$key;Before=$hash;After=$null}
}
function Up-UndoFile($s,$action,$backups){
    $path=Up-Child $action.Root $action.Key
    $current=if([IO.File]::Exists($path)){Up-Hash $path}else{'-'}
    if($current -eq $action.Before){return $true}
    if(-not $action.After -or $current -ne $action.After){return $false}
    $inverse=@{Root=$action.Root;Key=$action.Key;Before=$current;Hash=$action.Before;BackupPath=(Join-Path (Split-Path -Parent $path) ('.aoc-'+[guid]::NewGuid().ToString('N')+'.tmp'))}
    & $script:library {param($a,$d,$b) Set-SyncFile $a $d 'update-rollback' $b} $inverse $s.Config.StateDir $backups
    return $true
}
function Up-Recover($s,$taskController){
    $guard=Up-Child $s.Config.StateDir 'activation-pending.json'
    if(-not [IO.File]::Exists($guard)){return @{Complete=$true;State=$s}}
    $pending=Up-Read $guard
    if($pending.Journal -notmatch '^updates/[a-f0-9]{32}/journal\.json$'){throw 'Invalid activation journal reference.'}
    $journalPath=Up-Child $s.Config.StateDir $pending.Journal;$j=Up-Read $journalPath
    if($j.SchemaVersion -ne 1 -or $j.Meta -isnot [hashtable]){throw 'Invalid activation journal.'}
    $backups=New-Object 'Collections.Generic.List[object]';$review=@()
    foreach($a in $j.Files){
        if($a.Root -notin (@($s.Config.HubDir)+@($s.Config.Targets)) -or ($a.Key -split '/')[0] -notin $script:core){throw 'Activation journal contains an unrelated path.'}
        Up-Child $a.Root $a.Key|Out-Null
        if($a.Before -notmatch '^(-|[a-f0-9]{64})$' -or $a.After -notmatch '^[a-f0-9]{64}$'){throw 'Invalid rollback hash.'}
    }
    foreach($key in @('Sync','Config','Update')){
        $expected=@{Sync='state.json';Config='watch-config.json';Update='update-state.json'}[$key]
        if($j.Meta[$key].Key -ne $expected -or $j.Meta[$key].Before -notmatch '^(-|[a-f0-9]{64})$'){throw 'Invalid rollback metadata path.'}
    }
    if($j.Status -ne 'Complete'){
        foreach($a in @($j.Files)){
            try{if(-not (Up-UndoFile $s $a $backups)){$review+=($a.Root+'/'+$a.Key)}}catch{$review+=$_.Exception.Message}
        }
        if(-not $review.Count){
            foreach($key in @('Sync','Config','Update')){
                $a=@{Root=$s.Config.StateDir;Key=$j.Meta[$key].Key;Before=$j.Meta[$key].Before;After=$j.Meta[$key].After}
                try{if(-not (Up-UndoFile $s $a $backups)){$review+=$a.Key}}catch{$review+=$_.Exception.Message}
            }
        }
    }
    $j.RollbackBackups=@($backups.ToArray());$j.Review=@($review)
    if($review.Count){$j.Status='ReviewRequired';Up-Write $journalPath $j;return @{Complete=$false;State=$s;Issues=$review}}
    if($j.Status -ne 'Complete'){
        $restored=Up-State (Join-Path $s.Config.StateDir 'watch-config.json')
        if($restored.Candidate.Count){$restored.Candidate.Status='FAILED';$restored.Candidate.Approved=$false}
        $restored.LastError='Interrupted/failed activation rolled back; candidate requires a new decision.';Up-Save $restored
        $s=$restored;$j.Status='RolledBack'
    }
    Up-Write $journalPath $j
    # Keep temporary rollback captures until their durable blob and journal exist.
    foreach($b in $backups){
        if([IO.File]::Exists($b.Path) -and (Up-Hash $b.Path) -eq $b.Hash -and (Up-Hash (Up-Child $s.Config.StateDir ('blobs/'+$b.Hash))) -eq $b.Hash){[IO.File]::Delete($b.Path)}
    }
    [IO.File]::Delete($guard)
    if($j.TaskBefore){if($taskController){& $taskController 'Resume' $s.Config $j.TaskBefore|Out-Null}else{Up-Task 'Resume' $s.Config $j.TaskBefore|Out-Null}}
    return @{Complete=$true;State=$s}
}
function Up-TextHash($text){$sha=[Security.Cryptography.SHA256]::Create();try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}}
function Up-Apply($s,$taskController){
    $clock=[Diagnostics.Stopwatch]::StartNew();$record=@{Sha=$s.Candidate.Sha;Path=$s.Candidate.Path}
    $path=Up-ValidateRelease $s $record
    $engine=Import-Module (Join-Path $path 'scripts/SkillsSync.psm1') -Force -PassThru
    $invoke=@{HubDir=$s.Config.HubDir;Targets=$s.Config.Targets;StateDir=$s.Config.StateDir;FrameworkDir=$path;SkillNames=$script:core}
    $syncLock=Up-Mutex 'SkillsSync';$owned=Up-Lock $syncLock
    if(-not $owned){$syncLock.Dispose();throw 'Another synchronization is running.'}
    $previous=$null;$guard=Up-Child $s.Config.StateDir 'activation-pending.json';$journal=$null;$watchLock=$null;$watchOwned=$false
    try{
        $plan=& $engine {param($p) Invoke-SkillSync @p -Mode Plan} $invoke
        if($plan.Code -ne 0){throw 'SKILL_CONFLICT: resolve public skill differences before activation.'}
        if([IO.File]::Exists($guard)){throw 'Pending activation must be recovered first.'}
        $journal=@{SchemaVersion=1;Status='Applying';OldActive=$s.Active;Candidate=$record;Files=@();Meta=@{};TaskBefore=$null;RollbackBackups=@();Review=@()}
        foreach($action in $plan.Actions){
            if($action.Before -ne '-') {& $script:library {param($d,$p,$h) Save-SyncBlob $d $p $h} $s.Config.StateDir (Up-Child $action.Root $action.Key) $action.Before|Out-Null}
            $journal.Files+=@{Root=$action.Root;Key=$action.Key;Before=$action.Before;After=$action.Hash}
        }
        $journal.Meta.Sync=Up-Snapshot $s 'state.json';$journal.Meta.Config=Up-Snapshot $s 'watch-config.json';$journal.Meta.Update=Up-Snapshot $s 'update-state.json'
        $relative='updates/'+[guid]::NewGuid().ToString('N')+'/journal.json';$journalPath=Up-Child $s.Config.StateDir $relative
        Up-Write $journalPath $journal;Up-Write $guard @{Journal=$relative}
        $previous=if($taskController){& $taskController 'Suspend' $s.Config}else{Up-Task 'Suspend' $s.Config}
        $journal.TaskBefore=$previous;Up-Write $journalPath $journal
        $watchLock=Up-Mutex 'SkillsWatcher';$watchOwned=Up-Lock $watchLock 5000
        if(-not $watchOwned){throw 'An unmanaged watcher is running; activation cannot replace its code.'}
        $r=& $engine {param($p) Invoke-SkillSync @p -Mode Apply} $invoke
        if($r.Code -ne 0){throw ('Skill deployment failed: '+($r.Issues -join '; '))}
        $journal.Meta.Sync.After=Up-Hash (Up-Child $s.Config.StateDir 'state.json');Up-Write $journalPath $journal
        & $engine {param($p) Save-SkillSyncConfiguration -HubDir $p.HubDir -Targets $p.Targets -StateDir $p.StateDir -FrameworkDir $p.FrameworkDir} $invoke|Out-Null
        $journal.Meta.Config.After=Up-Hash (Up-Child $s.Config.StateDir 'watch-config.json');Up-Write $journalPath $journal
        $verified=& $engine {param($p) Invoke-SkillSync @p -Mode Verify} $invoke
        if($verified.Code -ne 0){throw 'Post-activation verification failed.'}
        $s.Active=$record
        $journal.Status='Probing';$journal.Meta.Update.After=Up-TextHash ($s|ConvertTo-Json -Depth 40);Up-Write $journalPath $journal
        Up-Save $s
        # The task may acquire its singleton while probing, but its synchronization
        # loop stays paused by activation-pending.json until this transaction commits.
        $watchLock.ReleaseMutex();$watchOwned=$false
        $health=if($taskController){& $taskController 'Resume' $s.Config $previous}else{Up-Task 'Resume' $s.Config $previous}
        if(-not $health.Healthy){throw 'Watcher health check failed.'}
        $s.LastGood=$record;$s.Candidate=@{};$s.Deferred=@{}
        $s.Samples.ActivateSeconds=@(@($s.Samples.ActivateSeconds)+@($clock.Elapsed.TotalSeconds)|Select-Object -Last 10)
        $journal.Meta.Update.After=Up-TextHash ($s|ConvertTo-Json -Depth 40);Up-Write $journalPath $journal;Up-Save $s
        $journal.Status='Complete';Up-Write $journalPath $journal;[IO.File]::Delete($guard)
    }catch{
        $failure=$_.Exception.Message
        if($journal -and [IO.File]::Exists($guard)){
            # Stop the candidate task before restoring a previous configuration.
            try{if($taskController){& $taskController 'Suspend' $s.Config|Out-Null}else{Up-Task 'Suspend' $s.Config|Out-Null}}catch{}
            $recovery=Up-Recover $s $taskController
            if(-not $recovery.Complete){throw ('ACTIVATION_REVIEW_REQUIRED: '+($recovery.Issues -join '; '))}
            $restored=$recovery.State;$s.Clear();foreach($key in $restored.Keys){$s[$key]=$restored[$key]}
        }
        throw $failure
    }finally{if($watchOwned){$watchLock.ReleaseMutex()};if($watchLock){$watchLock.Dispose()};if($owned){$syncLock.ReleaseMutex()};$syncLock.Dispose()}
}

function Up-WorkerAlive($worker){
    if(-not $worker.Count -or -not $worker.Id){return $false}
    try{
        $expected=if($worker.StartedUtc -is [datetime]){$worker.StartedUtc}else{[datetime]::Parse([string]$worker.StartedUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)}
        $p=Get-Process -Id $worker.Id -ErrorAction Stop
        try{return $p.StartTime.ToUniversalTime().Ticks -eq $expected.ToUniversalTime().Ticks}finally{$p.Dispose()}
    }catch{return $false}
}
function Up-LaunchWorker($s,$configPath){
    $workerScript=Up-Child $s.Config.InstallRoot 'scripts/update-worker.ps1'
    if(-not [IO.File]::Exists($workerScript)){throw 'Bootstrap worker missing; rerun the installer.'}
    $logId=[guid]::NewGuid().ToString('N');$out=Up-Child $s.Config.StateDir ('updates/worker-'+$logId+'.json');$err=Up-Child $s.Config.StateDir ('updates/worker-'+$logId+'.err')
    [IO.Directory]::CreateDirectory((Split-Path -Parent $out))|Out-Null
    $s.Candidate.Status='PREPARING';Up-Save $s
    $exe=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
    $arguments=Up-Arguments @('-NoProfile','-NonInteractive','-WindowStyle','Hidden','-ExecutionPolicy','Bypass','-File',$workerScript,'-ConfigPath',$configPath,'-CandidateSha',$s.Candidate.Sha,'-SessionId',$s.Candidate.SessionId)
    $process=Start-Process -FilePath $exe -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $out -RedirectStandardError $err -PassThru
    try{$s.Candidate.Worker=@{Id=$process.Id;StartedUtc=$process.StartTime.ToUniversalTime().ToString('o');Output=$out;Error=$err}}finally{$process.Dispose()}
    Up-Save $s
    return $s.Candidate.Worker.Id
}

function Initialize-AgentOpsUpdate {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory=$true)][string]$InstallRoot,[Parameter(Mandatory=$true)][string]$RepoUrl,
          [Parameter(Mandatory=$true)][string]$StateDir,[string]$RuntimeDir='',
          [Parameter(Mandatory=$true)][string]$HubDir,[Parameter(Mandatory=$true)][string[]]$Targets,
          [bool]$WatcherEnabled=$true,[switch]$LocalDevelopment,[scriptblock]$Verifier,[scriptblock]$GitRunner,[scriptblock]$TaskController)
    $s=$null;$mutex=Up-Mutex 'Update';$owned=$false
    try{
        if(-not $RuntimeDir){$RuntimeDir=$StateDir+'-runtime'}
        $config=@{InstallRoot=$InstallRoot;RuntimeDir=$RuntimeDir;StateDir=$StateDir;HubDir=$HubDir;Targets=$Targets;WatcherEnabled=$WatcherEnabled}
        Up-Paths $config;$repo=Up-Repo $RepoUrl
        $statePath=Up-Child $config.StateDir 'update-state.json'
        if(-not $PSCmdlet.ShouldProcess($config.StateDir,'Initialize verified update coordinator')){return [pscustomobject](Up-Result $null 'WHAT_IF')}
        $owned=Up-Lock $mutex
        if(-not $owned){return [pscustomobject](Up-Result $null 'BUSY' 3)}
        if([IO.File]::Exists($statePath)){
            $s=Up-State (Join-Path $config.StateDir 'watch-config.json')
            if($s.Identity.RepoUrl -ne $repo -or $s.Config.InstallRoot -ne $config.InstallRoot){throw 'Installation identity changed; existing state preserved.'}
            if(($s.Mode -eq 'LOCAL_DEV') -ne [bool]$LocalDevelopment){throw 'Do not silently mix development and verified installations. Use a separate state/bootstrap directory.'}
            $s.Config.WatcherEnabled=$WatcherEnabled;Up-Save $s
            return (Invoke-AgentOpsUpdate -ConfigPath (Join-Path $config.StateDir 'watch-config.json') -Action Check -Verifier $Verifier -GitRunner $GitRunner -TaskController $TaskController)
        }
        $s=@{SchemaVersion=1;Mode=if($LocalDevelopment){'LOCAL_DEV'}else{'MANAGED'};Identity=@{RepoUrl=$repo;Channel='stable'};Config=$config;Active=$null;LastGood=$null;Candidate=@{};Deferred=@{};LastAttemptUtc=$null;LastSuccessfulCheckUtc=$null;LastError=$null;Samples=@{PrepareSeconds=@();ActivateSeconds=@()}}
        & $script:library {param($c) Save-SkillSyncConfiguration -HubDir $c.HubDir -Targets $c.Targets -StateDir $c.StateDir -FrameworkDir $c.InstallRoot} $config|Out-Null
        Up-Save $s
        if($LocalDevelopment){return [pscustomobject](Up-Result $s 'LOCAL_DEV')}
        $session='install-'+[guid]::NewGuid().ToString('N')
        $check=Invoke-AgentOpsUpdate -ConfigPath (Join-Path $config.StateDir 'watch-config.json') -Action Check -SessionId $session -Verifier $Verifier -GitRunner $GitRunner -TaskController $TaskController
        if($check.Code -ne 0 -or -not $check.CandidateSha){return $check}
        return (Invoke-AgentOpsUpdate -ConfigPath (Join-Path $config.StateDir 'watch-config.json') -Action Apply -CandidateSha $check.CandidateSha -SessionId $session -Verifier $Verifier -GitRunner $GitRunner -TaskController $TaskController)
    }catch{$r=Up-Result $s 'FAILED' 1;$r.Issues=@($_.Exception.Message);return [pscustomobject]$r}
    finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
}

function Invoke-AgentOpsUpdate {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'),
          [ValidateSet('Check','Prepare','Apply','Defer','Repair')][string]$Action='Check',
          [string]$SessionId='',[switch]$BeginSession,[string]$CandidateSha='',[string]$RepoUrl='',
          [switch]$Background,[switch]$Worker,[scriptblock]$Verifier,[scriptblock]$GitRunner,[scriptblock]$TaskController)
    $s=$null;$mutex=Up-Mutex 'Update';$owned=$false
    try{
        if(-not [IO.File]::Exists($ConfigPath)){return [pscustomobject](Up-Result $null 'NOT_INSTALLED')}
        if(-not [IO.File]::Exists((Join-Path (Split-Path -Parent $ConfigPath) 'update-state.json'))){return [pscustomobject](Up-Result $null 'MIGRATION_REQUIRED' 2)}
        $s=Up-State $ConfigPath
        if($RepoUrl -and (Up-Repo $RepoUrl) -ne $s.Identity.RepoUrl){throw 'Repository/channel mismatch; cached releases cannot be reused.'}
        if($s.Mode -eq 'LOCAL_DEV'){return [pscustomobject](Up-Result $s 'LOCAL_DEV')}
        if($s.Active -and -not [IO.File]::Exists((Join-Path $s.Config.StateDir 'activation-pending.json'))){Up-ValidateRelease $s $s.Active|Out-Null}
        if($BeginSession -and -not $SessionId){$SessionId=[guid]::NewGuid().ToString('N')}
        if($SessionId.Length -gt 128 -or $SessionId -match '[\x00-\x1f]'){throw 'Invalid session identifier.'}
        if($Action -notin @('Check','Repair') -and -not $SessionId){throw 'A decision must be bound to a work-session identifier.'}
        if(-not $PSCmdlet.ShouldProcess($s.Config.StateDir,($Action+' verified framework update'))){return [pscustomobject](Up-Result $s 'WHAT_IF')}
        $owned=Up-Lock $mutex $(if($Worker){5000}else{0})
        if(-not $owned){return [pscustomobject](Up-Result $s 'BUSY' 3)}
        # Re-read after acquiring the lock; another process may have prepared a release.
        $s=Up-State $ConfigPath
        $guard=Up-Child $s.Config.StateDir 'activation-pending.json'
        if([IO.File]::Exists($guard)){
            $syncLock=Up-Mutex 'SkillsSync';$syncOwned=Up-Lock $syncLock
            if(-not $syncOwned){$syncLock.Dispose();return [pscustomobject](Up-Result $s 'BUSY' 3)}
            try{$recovery=Up-Recover $s $TaskController}finally{$syncLock.ReleaseMutex();$syncLock.Dispose()}
            return [pscustomobject](Up-Result $recovery.State $(if($recovery.Complete){'RECOVERED'}else{'ACTIVATION_REVIEW_REQUIRED'}) $(if($recovery.Complete){0}else{2}))
        }
        if($s.Active){Up-ValidateRelease $s $s.Active|Out-Null}
        if($Action -eq 'Repair'){return [pscustomobject](Up-Result $s 'UP_TO_DATE')}
        if($Worker -and ($Action -ne 'Prepare' -or -not $s.Candidate.Count -or $s.Candidate.Sha -ne $CandidateSha -or $s.Candidate.SessionId -ne $SessionId -or -not $s.Candidate.Approved -or $s.Candidate.Status -ne 'PREPARING')){
            # A delayed child cannot grant consent or replace a newer decision.
            return [pscustomobject](Up-Result $s 'WORKER_CANCELLED')
        }
        if($s.Candidate.Count -and $s.Candidate.Status -eq 'PREPARING' -and -not $Worker -and -not (Up-WorkerAlive $s.Candidate.Worker)){$s.Candidate.Status='FAILED';$s.Candidate.Approved=$false;$s.LastError='Preparation worker stopped; active release preserved.';Up-Save $s}
        if($Action -eq 'Check'){
            if($s.Candidate.Count -and $s.Candidate.Status -eq 'PREPARING'){$r=Up-Result $s 'PREPARING';$r.SessionId=$SessionId;return [pscustomobject]$r}
            if($BeginSession -and $s.Candidate.Count -and $s.Candidate.Status -eq 'READY' -and $s.Candidate.Approved -and $s.Candidate.SessionId -ne $SessionId){
                Up-Apply $s $TaskController;$r=Up-Result $s 'UPDATED';$r.SessionId=$SessionId;return [pscustomobject]$r
            }
            $s.LastAttemptUtc=[datetime]::UtcNow.ToString('o');$clock=[Diagnostics.Stopwatch]::StartNew()
            try{$line=Up-GitOk @('ls-remote',$s.Identity.RepoUrl,'refs/heads/stable') 5 $GitRunner}
            catch{
                $s.LastError='Remote unavailable; active release preserved.';Up-Save $s
                $r=Up-Result $s $(if($s.Active){'OFFLINE_CACHED'}else{'NO_VERIFIED_INSTALLATION'}) $(if($s.Active){0}else{1});$r.SessionId=$SessionId;return [pscustomobject]$r
            }
            $remote=@($line.Trim() -split '\s+')
            if($remote.Count -ne 2 -or $remote[0] -notmatch '^[a-fA-F0-9]{40}$' -or $remote[1] -ne 'refs/heads/stable'){throw 'Invalid remote SHA or stable reference.'}
            $sha=$remote[0].ToLowerInvariant()
            if($s.Active -and $sha -eq $s.Active.Sha){$s.LastSuccessfulCheckUtc=[datetime]::UtcNow.ToString('o');$s.LastError=$null;Up-Save $s;$r=Up-Result $s 'UP_TO_DATE';$r.SessionId=$SessionId;return [pscustomobject]$r}
            try{
                if($s.Candidate.Count -and $s.Candidate.Sha -eq $sha -and $s.Candidate.VerifiedCI){$evidence=@{Verified=$true;Sha=$sha;Summary=@($s.Candidate.Summary)}}
                elseif($Verifier){$evidence=& $Verifier $s.Identity.RepoUrl $sha (5-$clock.Elapsed.TotalSeconds)}
                else{$evidence=Up-CIProof $s.Identity.RepoUrl $sha (5-$clock.Elapsed.TotalSeconds)}
            }catch{
                $s.LastError='CI verification unavailable; active release and previous approval preserved.';Up-Save $s
                $r=Up-Result $s $(if($s.Active){'OFFLINE_CACHED'}else{'NO_VERIFIED_INSTALLATION'}) $(if($s.Active){0}else{1});$r.SessionId=$SessionId;return [pscustomobject]$r
            }
            if(-not $evidence.Verified -or $evidence.Sha -ne $sha){$s.LastError='Candidate has no successful trusted CI run.';Up-Save $s;return [pscustomobject](Up-Result $s 'UNVERIFIED_CANDIDATE' 2)}
            if(-not $s.Candidate.Count -or $s.Candidate.Sha -ne $sha){$s.Candidate=@{Sha=$sha;Status='DETECTED';Path=$null;VerifiedCI=$true;Summary=@($evidence.Summary);SessionId='';Approved=$false;Worker=@{}}}
            $s.LastSuccessfulCheckUtc=[datetime]::UtcNow.ToString('o');$s.LastError=$null;Up-Save $s
            $status=if($s.Candidate.Status -eq 'READY' -and $s.Candidate.Approved){'READY_NEXT_SESSION'}elseif($s.Deferred.Count -and $s.Deferred.Sha -eq $sha -and $s.Deferred.SessionId -eq $SessionId){'DEFERRED'}else{'UPDATE_AVAILABLE'}
            $r=Up-Result $s $status;$r.NeedsUserChoice=$status -eq 'UPDATE_AVAILABLE';$r.SessionId=$SessionId;return [pscustomobject]$r
        }
        if($CandidateSha -notmatch '^[a-f0-9]{40}$' -or -not $s.Candidate.Count -or $s.Candidate.Sha -ne $CandidateSha){throw 'Decision must refer to the exact verified candidate shown to the user.'}
        if($Action -eq 'Defer'){$s.Deferred=@{Sha=$CandidateSha;SessionId=$SessionId};$s.Candidate.Approved=$false;Up-Save $s;return [pscustomobject](Up-Result $s 'DEFERRED')}
        if($Background -and $Action -ne 'Prepare'){throw 'Only preparation may run in the background.'}
        if($Background -and $s.Candidate.Status -eq 'PREPARING' -and (Up-WorkerAlive $s.Candidate.Worker)){$r=Up-Result $s 'PREPARING';$r.WorkerId=$s.Candidate.Worker.Id;return [pscustomobject]$r}
        $s.Candidate.SessionId=$SessionId;$s.Candidate.Approved=$true;Up-Save $s
        if($Background -and $s.Candidate.Status -ne 'READY'){$workerId=Up-LaunchWorker $s $ConfigPath;$r=Up-Result $s 'PREPARING';$r.WorkerId=$workerId;return [pscustomobject]$r}
        Up-Prepare $s $GitRunner
        if($Action -eq 'Apply'){Up-Apply $s $TaskController;return [pscustomobject](Up-Result $s 'UPDATED')}
        return [pscustomobject](Up-Result $s 'READY_NEXT_SESSION')
    }catch{
        $message=$_.Exception.Message
        $pending=$s -and [IO.File]::Exists((Join-Path $s.Config.StateDir 'activation-pending.json'))
        if($s -and $owned -and -not $pending){try{if($s.Candidate.Count){$s.Candidate.Status='FAILED';$s.Candidate.Approved=$false};$s.LastError=$message;Up-Save $s}catch{}}
        $status=if($pending){'ACTIVATION_REVIEW_REQUIRED'}elseif($message.StartsWith('SKILL_CONFLICT:')){'SKILL_CONFLICT'}else{'FAILED'}
        $code=if($status -in @('SKILL_CONFLICT','ACTIVATION_REVIEW_REQUIRED')){2}else{1}
        $r=Up-Result $s $status $code;if($pending){$r.ActivePath=$null};$r.Issues=@($message);return [pscustomobject]$r
    }finally{if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
function Get-AgentOpsActiveRelease {
    [CmdletBinding()]
    param([string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'),[switch]$ForWatcher)
    $s=Up-State $ConfigPath
    if($s.Mode -eq 'LOCAL_DEV'){return [pscustomobject]@{Sha=$null;Path=$s.Config.InstallRoot;Mode='LOCAL_DEV'}}
    $guard=Up-Child $s.Config.StateDir 'activation-pending.json'
    if([IO.File]::Exists($guard)){
        $pending=Up-Read $guard
        if($pending.Journal -notmatch '^updates/[a-f0-9]{32}/journal\.json$'){throw 'Invalid activation guard.'}
        $j=Up-Read (Up-Child $s.Config.StateDir $pending.Journal)
        if(-not $ForWatcher -or $j.Status -ne 'Probing' -or -not $s.Active -or $s.Active.Sha -ne $j.Candidate.Sha){throw 'Activation pending; recover before starting a session.'}
    }
    if(-not $s.Active){throw 'No verified installation available.'}
    Up-ValidateRelease $s $s.Active|Out-Null
    return [pscustomobject]@{Sha=$s.Active.Sha;Path=$s.Active.Path;Mode='MANAGED'}
}
function Get-AgentOpsReleasePolicy {
    [CmdletBinding()]
    param([string]$RepositoryPath=(Split-Path -Parent $PSScriptRoot),[string]$Commit='HEAD')
    $result=[ordered]@{Code=0;Files=0;SkillDefinitions=0;Issues=@()}
    try{
        $RepositoryPath=Up-Root $RepositoryPath
        if($Commit -notmatch '^(HEAD|[a-f0-9]{40})$'){throw 'Select HEAD or an exact commit SHA.'}
        $tree=Up-GitOk @('-C',$RepositoryPath,'ls-tree','-r','-z',$Commit) 10 $null
        $seen=@{};$definitions=@()
        foreach($line in @($tree -split "`0"|Where-Object {$_})){
            if($line -notmatch '^(100644|100755) blob ([a-f0-9]{40})\t(.+)$'){throw 'Links/submodules are not allowed in public releases.'}
            $blob=$Matches[2];$path=$Matches[3]
            if(-not (Up-AllowedFile $path) -or $seen.ContainsKey($path)){throw ('Unexpected/private release path: '+$path)}
            $seen[$path]=$true
            if($path -match '(^|/)SKILL\.md$'){$definitions+=$path}
            $size=[long](Up-GitOk @('-C',$RepositoryPath,'cat-file','-s',$blob) 10 $null).Trim()
            if($size -gt 10485760){throw ('Oversized public file: '+$path)}
            $text=Up-GitOk @('-C',$RepositoryPath,'cat-file','blob',$blob) 10 $null
            if($text -match '-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[A-Za-z0-9_-]{30,}|sk-[A-Za-z0-9_-]{24,}') {throw ('Possible credential in public file: '+$path)}
        }
        $expected=@($script:core|ForEach-Object {"skills/$_/SKILL.md"}|Sort-Object)
        if($definitions.Count -ne 6 -or @(Compare-Object $expected @($definitions|Sort-Object)).Count){throw 'Release must contain exactly the six public skill definitions.'}
        if(-not $seen.ContainsKey('release-contract.json')){throw 'Release contract missing.'}
        $contract=(Up-GitOk @('-C',$RepositoryPath,'show',($Commit+':release-contract.json')) 10 $null)|ConvertFrom-Json
        if($contract.ProtocolVersion -ne 1 -or $contract.SyncStateSchema -ne 1 -or @(Compare-Object @($contract.CoreSkills|Sort-Object) @($script:core|Sort-Object)).Count){throw 'Release contract/catalogue mismatch.'}
        $result.Files=$seen.Count;$result.SkillDefinitions=$definitions.Count
    }catch{$result.Code=1;$result.Issues=@($_.Exception.Message)}
    return [pscustomobject]$result
}
Export-ModuleMember -Function Initialize-AgentOpsUpdate,Invoke-AgentOpsUpdate,Get-AgentOpsActiveRelease,Get-AgentOpsReleasePolicy
