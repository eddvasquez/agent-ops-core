# Project metadata transactions use the same path, blob and hash primitives as sync.
Set-StrictMode -Version 2
$script:engine=Import-Module (Join-Path $PSScriptRoot 'SkillsSync.psm1') -Force -PassThru
$script:coordinator=Import-Module (Join-Path $PSScriptRoot 'UpdateCoordinator.psm1') -Force -PassThru
$script:keys=@('AGENTS.md','.context/projectbrief.md','.context/systemPatterns.md','.context/activeContext.md','.context/progress.md','.context/lessons_learned.md','.context/reglas_proyecto.md','.context/agent-ops.json','CHANGELOG.md')
# AGENTS.md keeps the framework protocols inside a managed block; everything outside belongs to the project.
$script:blockBegin='<!-- agent-ops:begin version=(?<v>\S*) hash=(?<h>[a-f0-9]{64}) -->'
$script:blockEnd='<!-- agent-ops:end -->'
$script:ownHeading='## Reglas particulares del proyecto'
# Instruction files of other AI harnesses: inventoried read-only as candidate rules, never written.
$script:harnessFiles=@('CLAUDE.md','GEMINI.md','.cursorrules','.windsurfrules','.github/copilot-instructions.md')
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
function Pm-Norm([string]$s){([regex]::Replace($s,'\s+',' ')).Trim()}
function Pm-TextHash([string]$t){Pm-BytesHash ([Text.Encoding]::UTF8.GetBytes(($t -replace "`r",'').TrimEnd()))}
function Pm-NewBlock([string]$body,[string]$version){
    $b=($body -replace "`r",'').TrimEnd()
    return ('<!-- agent-ops:begin version='+$version+' hash='+(Pm-TextHash $b)+" -->`n"+$b+"`n"+$script:blockEnd)
}
function Pm-SplitBlock([string]$text){
    $m=[regex]::Match($text,'(?s)'+$script:blockBegin+'\r?\n(?<body>.*?)\r?\n'+[regex]::Escape($script:blockEnd))
    if(-not $m.Success){return $null}
    return [pscustomobject]@{Before=$text.Substring(0,$m.Index);After=$text.Substring($m.Index+$m.Length);Body=$m.Groups['body'].Value
        Hash=$m.Groups['h'].Value;Version=$m.Groups['v'].Value;Edited=((Pm-TextHash $m.Groups['body'].Value) -ne $m.Groups['h'].Value)}
}
function Pm-FrameworkLines($frame,[string]$templateText){
    $set=New-Object 'Collections.Generic.HashSet[string]'
    foreach($l in ($templateText -split "\r?\n")){$n=Pm-Norm $l;if($n){[void]$set.Add($n)}}
    $legacy=Pm-Child $frame 'templates/agents-legacy-lines.txt'
    if([IO.File]::Exists($legacy)){foreach($l in [IO.File]::ReadAllLines($legacy,[Text.Encoding]::UTF8)){$n=Pm-Norm $l;if($n){[void]$set.Add($n)}}}
    return ,$set
}
function Pm-ProjectLines([string]$text,$framework){
    # Project content: every non-blank line that is not official framework text or a migration marker.
    $own=New-Object Collections.Generic.List[string]
    foreach($l in ($text -split "\r?\n")){
        $n=Pm-Norm $l
        if(-not $n -or $n -match '^<!-- (agent-ops:(begin|end)|AgentOps migration:)' -or $n -eq $script:ownHeading -or $framework.Contains($n)){continue}
        $own.Add($l.TrimEnd())
    }
    return ,$own
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
function Pm-Rollback($project,$private,[string]$id,$state,$r){
    # Undo a completed migration only if no migrated file was edited afterwards; otherwise change nothing.
    if($id -notmatch '^[a-f0-9]{32}$'){throw 'Invalid journal id.'}
    $path=Pm-Child $private ($id+'.json')
    if(-not [IO.File]::Exists($path)){throw "Migration journal not found: $id"}
    $j=Pm-Read $path
    if($j.SchemaVersion -ne 1 -or $j.Project -ne $project){throw 'Invalid migration journal.'}
    if($j.Status -ne 'Complete'){$r.Code=2;$r.Status='ROLLBACK_REVIEW_REQUIRED';$r.Issues=@("Journal status is $($j.Status); only completed migrations can be rolled back.");return}
    $changed=@()
    foreach($a in @($j.Actions)){
        if($a.Root -ne $project -or $a.Key -notin $script:keys){throw 'Invalid migration journal action.'}
        if((Pm-Hash (Pm-Child $project $a.Key)) -ne $a.Hash){$changed+=$a.Key}
    }
    if($changed.Count){$r.Code=2;$r.Status='ROLLBACK_REVIEW_REQUIRED';$r.Issues=@('Edited after the migration (nothing was changed): '+($changed -join ', '));return}
    foreach($a in @($j.Actions)){
        $file=Pm-Child $project $a.Key
        $capture=(Pm-BytesHash ([Text.Encoding]::UTF8.GetBytes('rollback/'+$id+'/'+$a.Key))).Substring(0,32)
        $inverse=@{Root=$project;Key=$a.Key;Before=$a.Hash;Hash=$a.Before;BackupPath=(Join-Path (Split-Path $file) ('.aoc-'+$capture+'.tmp'))}
        Pm-Set $inverse $state
    }
    $j.Status='RolledBack';Pm-Write $path $j
    $r.Status='ROLLED_BACK';$r.JournalId=$id
}
function Invoke-ProjectMigration {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory=$true)][string]$ProjectPath,
          [string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'),
          [ValidateSet('Plan','Apply','Rollback','Defer')][string]$Mode='Plan',[string[]]$ImportSources=@(),
          [string]$AgentsCandidatePath='',[string]$ExpectedAgentsHash='',[string]$ApprovedRemovalsPath='',
          [string]$Journal='',[switch]$Commit,
          [scriptblock]$ReleaseResolver,[scriptblock]$FaultHook)
    $r=[ordered]@{Code=0;Status='PLANNED';Project=$null;Actions=@();ImportSources=@();AgentsHash=$null;AgentsProposal=$null;MissingLines=@();HarnessInstructions=@();UpToDate=$false;Deferred=$false;Issues=@();Conflicts=@();RescueManifest=$null;Journal=$null;JournalId=$null;RestoreRef=$null;Commit=$null}
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
        # "Not for this version": remembered in private state (never in the project) for this template only.
        $deferredPath=Pm-Child $private 'deferred.json'
        $currentTemplateHash=Pm-TextHash ([IO.File]::ReadAllText((Pm-Child $frame 'templates/AGENTS.md')))
        if($Mode -eq 'Defer'){
            if(-not $WhatIfPreference){Pm-Write $deferredPath @{SchemaVersion=1;TemplateHash=$currentTemplateHash}}
            $r.Status='DEFERRED';$r.Deferred=$true;return [pscustomobject]$r
        }
        if([IO.File]::Exists($deferredPath)){$r.Deferred=((Pm-Read $deferredPath).TemplateHash -eq $currentTemplateHash)}
        if($Mode -eq 'Rollback'){
            if(-not $Journal){throw 'Rollback requires -Journal <id> (the JournalId returned by Apply).'}
            if(-not $WhatIfPreference -and $PSCmdlet.ShouldProcess($project,'Roll back project migration '+$Journal)){Pm-Rollback $project $private $Journal $cfg.StateDir $r}
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
        $templateText=[IO.File]::ReadAllText((Pm-Child $frame 'templates/AGENTS.md'))
        $versionFile=Pm-Child $frame 'docs/VERSION'
        $frameworkVersion=$(if([IO.File]::Exists($versionFile)){([IO.File]::ReadAllText($versionFile)).Trim()}else{''})
        $templateHash=Pm-TextHash $templateText
        $newBlock=Pm-NewBlock $templateText $frameworkVersion
        $framework=Pm-FrameworkLines $frame $templateText
        foreach($name in $script:harnessFiles){
            $hp=Pm-Child $project $name
            if([IO.File]::Exists($hp)){$hl=Pm-ProjectLines ([IO.File]::ReadAllText($hp)) $framework;if($hl.Count){$r.HarnessInstructions+=@([pscustomobject]@{File=$name;Lines=@($hl)})}}
        }
        $agents=Pm-Child $project 'AGENTS.md';$r.AgentsHash=Pm-Hash $agents
        $current=$(if([IO.File]::Exists($agents)){[IO.File]::ReadAllText($agents)}else{$null})
        $texts=@{};$automatic=$null;$proposal=$null
        if($null -eq $current){$automatic=$newBlock+"`n"}
        else{
            $split=Pm-SplitBlock $current
            if($split -and -not $split.Edited){
                # Unedited managed block: replace only the block; text outside is kept byte for byte.
                if($split.Hash -ne $templateHash){$automatic=$split.Before+$newBlock+$split.After}
            }else{
                $own=Pm-ProjectLines $(if($split){$split.Body}else{$current}) $framework
                $section=$(if($own.Count){"`n`n"+$script:ownHeading+"`n`n"+($own -join "`n")+"`n"}else{"`n"})
                $candidateText=$(if($split){$split.Before+$newBlock+$split.After.TrimEnd()+$section}else{$newBlock+$section})
                # Legacy file made only of official template text: nothing of the project can be lost.
                if(-not $split -and -not $own.Count){$automatic=$candidateText}else{$proposal=$candidateText}
            }
        }
        if($AgentsCandidatePath){
            if($ExpectedAgentsHash -ne $r.AgentsHash){$r.Code=2;$r.Status='PROJECT_CHANGED';return [pscustomobject]$r}
            $candidate=[IO.Path]::GetFullPath($AgentsCandidatePath)
            & $script:engine {param($p) Assert-SyncNoLink $p} $candidate
            if($candidate.StartsWith($project+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Store reviewed candidates outside the project.'}
            $text=[IO.File]::ReadAllText($candidate)
            $cs=Pm-SplitBlock $text
            if(-not $cs -or $cs.Edited -or $cs.Hash -ne $templateHash){throw 'Candidate must contain the current agent-ops managed block unchanged; start from AgentsProposal.'}
            # Conservation gate: no project line of the original may disappear without explicit approval.
            $approved=New-Object 'Collections.Generic.HashSet[string]'
            if($ApprovedRemovalsPath){foreach($l in [IO.File]::ReadAllLines([IO.Path]::GetFullPath($ApprovedRemovalsPath),[Text.Encoding]::UTF8)){$n=Pm-Norm $l;if($n){[void]$approved.Add($n)}}}
            $present=New-Object 'Collections.Generic.HashSet[string]'
            foreach($l in ($text -split "\r?\n")){$n=Pm-Norm $l;if($n){[void]$present.Add($n)}}
            $required=Pm-ProjectLines $(if($null -ne $current){$current}else{''}) $framework
            $missing=@($required|Where-Object {-not $present.Contains((Pm-Norm $_)) -and -not $approved.Contains((Pm-Norm $_))})
            if($missing.Count){$r.Code=2;$r.Status='AGENTS_RULES_MISSING';$r.MissingLines=$missing;$r.AgentsProposal=$proposal;return [pscustomobject]$r}
            $texts['AGENTS.md']=$text.TrimEnd()+"`n"
        }elseif($proposal){$r.Code=2;$r.Status='AGENTS_REVIEW_REQUIRED';$r.AgentsProposal=$proposal;return [pscustomobject]$r}
        elseif($automatic){$texts['AGENTS.md']=$automatic}
        # Record which framework version this project follows (no timestamps: repeats stay idempotent).
        $texts['.context/agent-ops.json']=([ordered]@{SchemaVersion=1;FrameworkVersion=$frameworkVersion;FrameworkSha=[string]$release.Sha;TemplateHash=$templateHash}|ConvertTo-Json)+"`n"
        foreach($key in $script:keys|Where-Object {$_ -like '.context/*.md'}){
            $path=Pm-Child $project $key
            if(-not [IO.File]::Exists($path)){$texts[$key]=[IO.File]::ReadAllText((Pm-Child $frame ('templates/context/'+[IO.Path]::GetFileName($key))))}
        }
        # Protocol 7: every project keeps a changelog; an existing one is never touched.
        $changelogTemplate=Pm-Child $frame 'templates/CHANGELOG.md'
        if([IO.File]::Exists($changelogTemplate) -and -not [IO.File]::Exists((Pm-Child $project 'CHANGELOG.md'))){$texts['CHANGELOG.md']=[IO.File]::ReadAllText($changelogTemplate)}
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
        $registry=Pm-Child $project '.context/agent-ops.json'
        if(-not $actions.Count -and [IO.File]::Exists($registry)){$r.UpToDate=((Pm-Read $registry).TemplateHash -eq $templateHash)}
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
        # Restore point for Git projects: a hidden ref at the pre-migration HEAD (no branch moves).
        $top=& $script:coordinator {param($p) Up-Git @('-C',$p,'rev-parse','--show-toplevel') 5 $null} $project
        if($top.ExitCode -eq 0 -and (Pm-Root ([string]$top.Output).Trim()) -eq $project){
            $head=& $script:coordinator {param($p) Up-Git @('-C',$p,'rev-parse','--verify','-q','HEAD') 5 $null} $project
            if($head.ExitCode -eq 0){
                $ref='refs/agent-ops/pre-migration/'+$id
                & $script:coordinator {param($p,$f,$h) Up-GitOk @('-C',$p,'update-ref',$f,$h) 5 $null} $project $ref ([string]$head.Output).Trim()|Out-Null
                $r.RestoreRef=$ref
            }
        }
        $journalRecord=@{SchemaVersion=1;Id=$id;Project=$project;Status='Applying';Actions=$actions;RescueManifest=$r.RescueManifest}
        if($r.RestoreRef){$journalRecord.RestoreRef=$r.RestoreRef}
        $r.Journal=$pending;Pm-Write $pending $journalRecord
        foreach($a in $actions){Pm-Set $a $cfg.StateDir;if($FaultHook){& $FaultHook $a}}
        foreach($a in $actions){if((Pm-Hash (Pm-Child $project $a.Key)) -ne $a.Hash){throw 'Project changed during verification.'}}
        $verified=& $script:engine {param($p) Invoke-SkillSync @p -Mode Verify} $sync
        if($verified.Code -ne 0){throw 'Import changed after rescue; metadata migration requires recovery.'}
        $journalRecord.Status='Complete';Pm-Write $pending $journalRecord;Pm-Recover $pending $project $cfg.StateDir
        $r.Status='MIGRATED';$r.Journal=Pm-Child $private ($id+'.json');$r.JournalId=$id
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
