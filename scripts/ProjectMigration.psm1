# Project metadata transactions use the same path, blob and hash primitives as sync.
Set-StrictMode -Version 2
$script:engine=Import-Module (Join-Path $PSScriptRoot 'SkillsSync.psm1') -Force -PassThru
$script:coordinator=Import-Module (Join-Path $PSScriptRoot 'UpdateCoordinator.psm1') -Force -PassThru
$script:keys=@('AGENTS.md','.context/projectbrief.md','.context/systemPatterns.md','.context/activeContext.md','.context/progress.md','.context/lessons_learned.md')
function Pm-Root($p){& $script:engine {param($p) Get-SyncRoot $p} $p}
function Pm-Child($p,$k){& $script:engine {param($p,$k) Get-SyncChild $p $k} $p $k}
function Pm-Hash($p){if([IO.File]::Exists($p)){& $script:engine {param($p) Get-SyncHash $p} $p}else{'-'}}
function Pm-Write($p,$v){& $script:engine {param($p,$v) Write-SyncJson $p $v} $p $v}
function Pm-Read($p){& $script:coordinator {param($p) Up-Read $p} $p}
function Pm-BytesHash($bytes){$h=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($h.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}}
function Pm-Blob($state,$bytes){
    $hash=Pm-BytesHash $bytes;$path=Pm-Child $state ('blobs/'+$hash)
    [IO.Directory]::CreateDirectory((Split-Path $path))|Out-Null
    if(-not [IO.File]::Exists($path)){
        $temp=Pm-Child $state ('blobs/.aoc-'+[guid]::NewGuid().ToString('N')+'.tmp')
        try{
            $stream=[IO.File]::Open($temp,'CreateNew','Write','None')
            try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
            [IO.File]::Move($temp,$path)
        }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
    }
    if((Pm-Hash $path) -ne $hash){throw 'Corrupt migration blob.'};return $hash
}
function Pm-Set($action,$state){
    $backups=New-Object 'Collections.Generic.List[object]'
    & $script:engine {param($a,$s,$b) Set-SyncFile $a $s 'project-migration' $b} $action $state $backups
    foreach($b in $backups){if((Pm-Hash $b.Path) -ne $action.Before){throw 'Concurrent edit preserved in atomic backup; review required.'};[IO.File]::Delete($b.Path)}
}
function Pm-Recover($pending,$project,$state){
    $j=Pm-Read $pending
    if($j.SchemaVersion -ne 1 -or $j.Project -ne $project){throw 'Invalid migration recovery journal.'}
    foreach($a in $j.Actions){
        if($a.Root -ne $project -or $a.Key -notin $script:keys -or $a.Before -notmatch '^(-|[a-f0-9]{64})$' -or $a.Hash -notmatch '^[a-f0-9]{64}$'){throw 'Invalid migration recovery action.'}
        $path=Pm-Child $project $a.Key
        $capture=(Pm-BytesHash ([Text.Encoding]::UTF8.GetBytes($j.Id+'/'+$a.Key))).Substring(0,32)
        if($a.BackupPath -ne (Join-Path (Split-Path $path) ('.aoc-'+$capture+'.tmp'))){throw 'Invalid atomic backup path.'}
    }
    if($j.Status -ne 'Complete'){
        foreach($a in @($j.Actions)){
            if([IO.File]::Exists($a.BackupPath)){
                $actual=Pm-Hash $a.BackupPath
                & $script:engine {param($s,$p,$h) Save-SyncBlob $s $p $h} $state $a.BackupPath $actual|Out-Null
                if($actual -ne $a.Before){throw 'Concurrent edit captured during replacement; retained for review.'}
            }
            $current=Pm-Hash (Pm-Child $project $a.Key)
            if($current -eq $a.Before){continue}
            if($current -ne $a.Hash){throw ('Later edit preserved; review migration journal: '+$a.Key)}
            $inverse=@{Root=$project;Key=$a.Key;Before=$current;Hash=$a.Before;BackupPath=$a.BackupPath}
            # An interrupted replacement may have left the original capture.
            if([IO.File]::Exists($a.BackupPath)){[IO.File]::Delete($a.BackupPath)}
            Pm-Set $inverse $state
        }
        $j.Status='RolledBack'
    }
    foreach($a in $j.Actions){if([IO.File]::Exists($a.BackupPath)){if((Pm-Hash $a.BackupPath) -ne $a.Before){throw 'Atomic backup requires review.'};[IO.File]::Delete($a.BackupPath)}}
    $archive=Pm-Child (Split-Path $pending) ($j.Id+'.json');Pm-Write $archive $j;[IO.File]::Delete($pending)
}
function Invoke-ProjectMigration {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory=$true)][string]$ProjectPath,
          [string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'),
          [ValidateSet('Plan','Apply')][string]$Mode='Plan',[string[]]$ImportSources=@(),
          [string]$AgentsCandidatePath='',[string]$ExpectedAgentsHash='',[switch]$Commit,
          [scriptblock]$ReleaseResolver,[scriptblock]$FaultHook)
    $r=[ordered]@{Code=0;Status='PLANNED';Project=$null;Actions=@();ImportSources=@();AgentsHash=$null;Issues=@();Conflicts=@();RescueManifest=$null;Journal=$null;Commit=$null}
    $updateLock=$null;$syncLock=$null;$u=$false;$l=$false;$pending=$null;$project=$null;$cfg=$null;$applying=$false;$metadataComplete=$false
    try{
        if(-not [IO.File]::Exists($ConfigPath)){$r.Code=2;$r.Status='INSTALLATION_REQUIRED';return [pscustomobject]$r}
        $project=Pm-Root $ProjectPath;$r.Project=$project
        if(-not [IO.Directory]::Exists($project)){throw 'Project directory missing.'}
        $cfg=Pm-Read ([IO.Path]::GetFullPath($ConfigPath))
        if($cfg -isnot [hashtable] -or -not $cfg.HubDir -or -not $cfg.Targets -or -not $cfg.StateDir){throw 'Invalid installation configuration.'}
        if((Pm-Root (Split-Path ([IO.Path]::GetFullPath($ConfigPath)))) -ne (Pm-Root $cfg.StateDir)){throw 'Configuration belongs to a different state directory.'}
        $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $updateLock=New-Object Threading.Mutex($false,('Local\AgentOpsUpdate-'+$sid));try{$u=$updateLock.WaitOne(0)}catch [Threading.AbandonedMutexException]{$u=$true}
        if(-not $u){$r.Code=3;$r.Status='BUSY';return [pscustomobject]$r}
        $release=if($ReleaseResolver){& $ReleaseResolver $ConfigPath}else{& $script:coordinator {param($p) Get-AgentOpsActiveRelease -ConfigPath $p} $ConfigPath}
        if($release.Mode -ne 'MANAGED'){throw 'A managed, verified release is required.'}
        $frame=Pm-Root $release.Path
        if(-not $ReleaseResolver -and $frame -ne (Pm-Root (Split-Path $PSScriptRoot))){throw 'Run migrate-project.ps1 from the ActivePath returned by start-session.ps1.'}
        $cfg=Pm-Read $ConfigPath
        $protected=@($cfg.HubDir)+@($cfg.Targets)+@($frame)
        if(-not $ReleaseResolver){$s=Pm-Read (Pm-Child $cfg.StateDir 'update-state.json');$protected+=@($s.Config.InstallRoot,$s.Config.RuntimeDir)}
        # Treat the entire project as protected from overlap, including .context.
        # The active frame is intentionally inside RuntimeDir. Validate each
        # protected tree against the project, rather than rejecting that nesting.
        foreach($tree in @($protected|Sort-Object -Unique)){
            & $script:engine {param($p,$t,$s) Get-SkillSyncConfiguration -HubDir $p -Targets @($t) -StateDir $s} $project $tree $cfg.StateDir|Out-Null
        }
        $syncLock=New-Object Threading.Mutex($false,('Local\AgentOpsSkillsSync-'+$sid));try{$l=$syncLock.WaitOne(0)}catch [Threading.AbandonedMutexException]{$l=$true}
        if(-not $l){$r.Code=3;$r.Status='BUSY';return [pscustomobject]$r}
        $projectId=Pm-BytesHash ([Text.Encoding]::UTF8.GetBytes($project.ToLowerInvariant()))
        $private=Pm-Child $cfg.StateDir ('migrations/'+$projectId);$pending=Pm-Child $private 'pending.json'
        $write=$Mode -eq 'Apply' -and -not $WhatIfPreference
        if([IO.File]::Exists($pending)){
            $r.Code=2;$r.Status='RECOVERY_REQUIRED';$r.Journal=$pending
            if($write -and $PSCmdlet.ShouldProcess($project,'Recover interrupted project migration')){Pm-Recover $pending $project $cfg.StateDir;$r.Code=0;$r.Status='RECOVERED'}
            return [pscustomobject]$r
        }
        $sources=@($ImportSources)
        foreach($key in @('skills','_ai-skills-hub')){$p=Pm-Child $project $key;if([IO.Directory]::Exists($p)){$sources+=@($p)}}
        $sources=@($sources|ForEach-Object {Pm-Root $_}|Sort-Object -Unique)
        $r.ImportSources=@($sources)
        $sync=@{HubDir=$cfg.HubDir;Targets=$cfg.Targets;StateDir=$cfg.StateDir;FrameworkDir=$frame;ImportSources=$sources}
        $scan=& $script:engine {param($p) Invoke-SkillSync @p -Mode Plan} $sync
        $r.Conflicts=@($scan.Conflicts);if($scan.Code -ne 0){
            $r.Code=$scan.Code;$r.Status='SKILL_REVIEW_REQUIRED';$r.Issues=@($scan.Issues)
            if($write -and $scan.Code -eq 2 -and $PSCmdlet.ShouldProcess($project,'Rescue conflicting skills without propagation')){
                $rescue=& $script:engine {param($p) Invoke-SkillSync @p -Mode Rescue} $sync
                $r.RescueManifest=$rescue.RescueManifest
                if($rescue.Code -ne 0){$r.Code=$rescue.Code;$r.Issues=@($rescue.Issues)}
            }
            return [pscustomobject]$r
        }
        $template=Pm-Child $frame 'templates/AGENTS.md';$marker='<!-- AgentOps migration: '+(Pm-Hash $template)+' -->'
        $agents=Pm-Child $project 'AGENTS.md';$r.AgentsHash=Pm-Hash $agents
        $texts=@{}
        if($AgentsCandidatePath){
            if($ExpectedAgentsHash -ne $r.AgentsHash){$r.Code=2;$r.Status='PROJECT_CHANGED';return [pscustomobject]$r}
            $candidate=[IO.Path]::GetFullPath($AgentsCandidatePath)
            & $script:engine {param($p) Assert-SyncNoLink $p} $candidate
            if($candidate.StartsWith($project+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Store reviewed candidates outside the project.'}
            $text=[IO.File]::ReadAllText($candidate)
            if($text -notmatch 'ops-session-handoff' -or $text -notmatch 'MODO ENTRADA' -or $text -notmatch 'start-session\.ps1'){throw 'Candidate is missing the session entry integration.'}
            $texts['AGENTS.md']=$text.TrimEnd()+"`n`n"+$marker+"`n"
        }elseif($r.AgentsHash -eq '-'){$texts['AGENTS.md']=[IO.File]::ReadAllText($template).TrimEnd()+"`n`n"+$marker+"`n"}
        elseif(-not [IO.File]::ReadAllText($agents).Contains($marker)){$r.Code=2;$r.Status='AGENTS_REVIEW_REQUIRED';return [pscustomobject]$r}
        foreach($key in $script:keys|Where-Object {$_ -ne 'AGENTS.md'}){
            $path=Pm-Child $project $key
            if(-not [IO.File]::Exists($path)){$texts[$key]=[IO.File]::ReadAllText((Pm-Child $frame ('templates/context/'+[IO.Path]::GetFileName($key))))}
        }
        $patterns=Pm-Child $project '.context/systemPatterns.md'
        if([IO.File]::Exists($patterns)){
            $text=[IO.File]::ReadAllText($patterns)
            if($text -notmatch 'dev-tdd' -or $text -notmatch 'dev-systematic-debugging'){$texts['.context/systemPatterns.md']=$text+"`n`n<!-- AgentOps engineering -->`nPara trabajo de software, aplicar dev-tdd y dev-systematic-debugging cuando corresponda.`n"}
        }
        $payload=@{};$actions=@();$id=[guid]::NewGuid().ToString('N')
        foreach($key in @($texts.Keys|Sort-Object)){
            $path=Pm-Child $project $key;$bytes=[Text.Encoding]::UTF8.GetBytes($texts[$key]);$hash=Pm-BytesHash $bytes;$before=Pm-Hash $path
            $capture=(Pm-BytesHash ([Text.Encoding]::UTF8.GetBytes($id+'/'+$key))).Substring(0,32)
            if($before -ne $hash){$payload[$key]=$bytes;$actions+=@{Root=$project;Key=$key;Before=$before;Hash=$hash;BackupPath=(Join-Path (Split-Path $path) ('.aoc-'+$capture+'.tmp'))}}
        }
        $r.Actions=@($actions);$canCommit=$false
        if($Commit){
            $top=(& $script:coordinator {param($p) Up-GitOk @('-C',$p,'rev-parse','--show-toplevel') 5 $null} $project).Trim()
            if((Pm-Root $top) -ne $project){throw 'Commit requires the project Git root.'}
            $staged=& $script:coordinator {param($p) Up-GitOk @('-C',$p,'diff','--cached','--name-only') 5 $null} $project
            if($staged.Trim()){throw 'Index contains prior changes; commit refused.'}
            foreach($a in $actions){
                $dirty=& $script:coordinator {param($p,$k) Up-GitOk @('-C',$p,'diff','--name-only','--',$k) 5 $null} $project $a.Key
                if($dirty.Trim() -or ($a.Before -ne '-' -and -not (& $script:coordinator {param($p,$k) Up-Git @('-C',$p,'ls-files','--error-unmatch','--',$k) 5 $null} $project $a.Key).ExitCode.Equals(0))){throw 'Affected file has prior uncommitted content; commit refused.'}
            };$canCommit=$true
        }
        if(-not $write -or -not $PSCmdlet.ShouldProcess($project,'Import skills and apply reviewed project migration')){return [pscustomobject]$r}
        $applying=$true
        $rescued=& $script:engine {param($p) Invoke-SkillSync @p -Mode Apply} $sync;$r.RescueManifest=$rescued.RescueManifest
        if($rescued.Code -ne 0){$r.Code=$rescued.Code;$r.Status='SKILL_REVIEW_REQUIRED';$r.Conflicts=@($rescued.Conflicts);$r.Issues=@($rescued.Issues);return [pscustomobject]$r}
        foreach($a in $actions){
            if((Pm-Hash (Pm-Child $project $a.Key)) -ne $a.Before){throw 'Project changed after planning.'}
            if($a.Before -ne '-') {& $script:engine {param($s,$p,$h) Save-SyncBlob $s $p $h} $cfg.StateDir (Pm-Child $project $a.Key) $a.Before|Out-Null}
            if((Pm-Blob $cfg.StateDir $payload[$a.Key]) -ne $a.Hash){throw 'Payload changed.'}
        }
        $journal=@{SchemaVersion=1;Id=$id;Project=$project;Status='Applying';Actions=$actions;RescueManifest=$r.RescueManifest}
        $r.Journal=$pending;Pm-Write $pending $journal
        foreach($a in $actions){Pm-Set $a $cfg.StateDir;if($FaultHook){& $FaultHook $a}}
        foreach($a in $actions){if((Pm-Hash (Pm-Child $project $a.Key)) -ne $a.Hash){throw 'Project changed during verification.'}}
        $verified=& $script:engine {param($p) Invoke-SkillSync @p -Mode Verify} $sync
        if($verified.Code -ne 0){throw 'Import changed after rescue; metadata migration requires recovery.'}
        $journal.Status='Complete';Pm-Write $pending $journal;Pm-Recover $pending $project $cfg.StateDir
        $r.Status='MIGRATED';$r.Journal=Pm-Child $private ($id+'.json')
        $metadataComplete=$true
        if($canCommit -and $actions.Count){
            foreach($a in $actions){if((Pm-Hash (Pm-Child $project $a.Key)) -ne $a.Hash){throw 'Project changed before staging; commit refused.'}}
            $gitArguments=@('-C',$project,'add','--')+@($actions|ForEach-Object {$_.Key});& $script:coordinator {param($a) Up-GitOk $a 10 $null} $gitArguments|Out-Null
            $staged=(& $script:coordinator {param($p) Up-GitOk @('-C',$p,'diff','--cached','--name-only') 5 $null} $project) -split "`n"|Where-Object {$_}
            if(@(Compare-Object @($actions.Key|Sort-Object) @($staged|Sort-Object)).Count){throw 'Index changed concurrently; commit refused.'}
            & $script:coordinator {param($p) Up-GitOk @('-C',$p,'commit','-m','chore(arch): migrate project governance safely') 30 $null} $project|Out-Null
            $r.Commit=(& $script:coordinator {param($p) Up-GitOk @('-C',$p,'rev-parse','HEAD') 5 $null} $project).Trim()
        }
    }catch{
        $r.Code=1;$r.Status='FAILED';$r.Issues=@($_.Exception.Message)
        if($metadataComplete){$r.Code=2;$r.Status='COMMIT_REVIEW_REQUIRED'}
        if($applying -and $pending -and [IO.File]::Exists($pending)){
            try{Pm-Recover $pending $project $cfg.StateDir;$r.Status='ROLLED_BACK'}catch{$r.Code=2;$r.Status='RECOVERY_REVIEW_REQUIRED';$r.Issues+=@($_.Exception.Message)}
        }
    }finally{if($l){$syncLock.ReleaseMutex()};if($syncLock){$syncLock.Dispose()};if($u){$updateLock.ReleaseMutex()};if($updateLock){$updateLock.Dispose()}}
    return [pscustomobject]$r
}
Export-ModuleMember -Function Invoke-ProjectMigration
