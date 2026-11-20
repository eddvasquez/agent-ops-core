Set-StrictMode -Version 2
# Crash-only handoff. The working agent records a cheap checkpoint after every step (no commit), so
# losing the session to quota, context or a crash costs nothing. Another harness resumes from
# physical Git (authoritative), the checkpoint and the user's recent turns (untrusted data).
Import-Module (Join-Path $PSScriptRoot 'NativeProcess.psm1')
Import-Module (Join-Path $PSScriptRoot 'InstructionHarvest.psm1')
$script:file='.context/checkpoint.json'
$script:maxSteps=20

function Sc-Root([string]$p){[IO.Path]::GetFullPath($p).TrimEnd('\','/')}
function Sc-Path([string]$project){Join-Path $project $script:file}
function Sc-Now{[DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')}
function Sc-Date($v){
    # pwsh's ConvertFrom-Json already returns DateTime; Windows PowerShell 5.1 returns the string.
    if($null -eq $v -or $v -eq ''){return $null}
    if($v -is [datetime]){return $v.ToUniversalTime()}
    try{[datetime]::Parse([string]$v,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()}catch{$null}
}
function Sc-Iso($v){$d=Sc-Date $v;if($d){$d.ToString('yyyy-MM-ddTHH:mm:ssZ')}else{$null}}
function Sc-Require([string]$project){
    if(-not [IO.Directory]::Exists((Join-Path $project '.context'))){throw 'Project has no .context directory.'}
    $r=Invoke-Git -RepositoryPath $project -Arguments @('rev-parse','--is-inside-work-tree') -AllowFailure
    if($r.ExitCode -ne 0){throw 'Project is not a Git work tree.'}
}
function Sc-Head([string]$project){
    $r=Invoke-Git -RepositoryPath $project -Arguments @('rev-parse','--verify','-q','HEAD') -AllowFailure
    if($r.ExitCode -eq 0){$r.Output.Trim()}else{$null}
}
function Sc-Dirty([string]$project){
    # Paths with uncommitted work, excluding the checkpoint itself.
    $out=(Invoke-Git -RepositoryPath $project -Arguments @('status','--porcelain=v1','-z','-uall')).Output
    $parts=@($out -split "`0");$paths=@();$i=0
    while($i -lt $parts.Count){
        $e=$parts[$i];$i++
        if($e.Length -lt 4){continue}
        $paths+=$e.Substring(3)
        if($e[0] -eq 'R' -or $e[0] -eq 'C'){$i++}
    }
    @($paths|Where-Object {$_ -ne $script:file}|Sort-Object -Unique)
}
function Sc-Fingerprint([string]$project,[string[]]$paths){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{
        $sb=New-Object Text.StringBuilder
        foreach($p in $paths){
            $full=Join-Path $project $p
            $h=if([IO.File]::Exists($full)){[BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($full))).Replace('-','')}else{'deleted'}
            [void]$sb.Append($p).Append(':').Append($h).Append("`n")
        }
        [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($sb.ToString()))).Replace('-','').ToLowerInvariant()
    }finally{$sha.Dispose()}
}
function Sc-Read([string]$project){
    $path=Sc-Path $project
    if(-not [IO.File]::Exists($path)){return $null}
    try{[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)|ConvertFrom-Json}catch{throw 'CHECKPOINT_UNREADABLE'}
}
function Sc-Write([string]$project,$data){
    $path=Sc-Path $project;$tmp=$path+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($tmp,($data|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding $false))
    try{
        if([IO.File]::Exists($path)){[IO.File]::Replace($tmp,$path,[NullString]::Value)}else{[IO.File]::Move($tmp,$path)}
    }finally{if([IO.File]::Exists($tmp)){[IO.File]::Delete($tmp)}}
}
function Sc-Prop($o,[string]$n){if($null -ne $o -and $o.PSObject.Properties[$n]){$o.$n}else{$null}}

function Write-SessionCheckpoint {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$Agent,
          [Parameter(Mandatory=$true)][string]$Step,[Parameter(Mandatory=$true)][string]$Next,
          [string[]]$Files=@())
    $r=[ordered]@{Code=0;Status='WRITTEN';SessionId=$null;Path=$null;Issues=@()}
    try{
        $project=Sc-Root $ProjectPath;Sc-Require $project;$r.Path=Sc-Path $project
        $prev=$null;try{$prev=Sc-Read $project}catch{$prev=$null}
        $open=$prev -and (Sc-Prop $prev 'State') -eq 'OPEN'
        $now=Sc-Now
        $steps=@(if($open){@(Sc-Prop $prev 'Steps')})+@([pscustomobject]@{At=$now;Step=$Step;Next=$Next})
        if($steps.Count -gt $script:maxSteps){$steps=@($steps[($steps.Count-$script:maxSteps)..($steps.Count-1)])}
        $dirty=Sc-Dirty $project
        $data=[ordered]@{
            Schema=1;State='OPEN'
            SessionId=if($open){$prev.SessionId}else{[guid]::NewGuid().ToString('N')}
            Agent=$Agent;StartedAt=if($open){Sc-Iso $prev.StartedAt}else{$now};UpdatedAt=$now
            Head=Sc-Head $project;LastStep=$Step;NextStep=$Next;Files=@($Files)
            Worktree=Sc-Fingerprint $project $dirty;Steps=$steps
        }
        Sc-Write $project $data;$r.SessionId=$data.SessionId
    }catch{$r.Code=1;$r.Status='FAILED';$r.Issues=@($_.Exception.Message)}
    [pscustomobject]$r
}

function Close-SessionCheckpoint {
    # MODO SALIDA: mark the session as handed off; the relevo commit carries the closed checkpoint.
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectPath)
    $r=[ordered]@{Code=0;Status='CLOSED';SessionId=$null;Issues=@()}
    try{
        $project=Sc-Root $ProjectPath;Sc-Require $project
        $cp=Sc-Read $project
        if(-not $cp){$r.Status='NO_CHECKPOINT';return [pscustomobject]$r}
        $cp.State='CLOSED'
        $cp|Add-Member -NotePropertyName ClosedAt -NotePropertyValue (Sc-Now) -Force
        $cp|Add-Member -NotePropertyName HeadAtClose -NotePropertyValue (Sc-Head $project) -Force
        Sc-Write $project $cp;$r.SessionId=$cp.SessionId
    }catch{$r.Code=1;$r.Status=if($_.Exception.Message -eq 'CHECKPOINT_UNREADABLE'){'CHECKPOINT_UNREADABLE'}else{'FAILED'};$r.Issues=@($_.Exception.Message)}
    [pscustomobject]$r
}

function Get-SessionResume {
    # Read-only. INTERRUPTED: the previous agent stopped before MODO SALIDA; finish it on its behalf.
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectPath,
          [string]$ClaudeProjectsRoot=(Join-Path $env:USERPROFILE '.claude/projects'),
          [string]$CodexSessionsRoot=(Join-Path $env:USERPROFILE '.codex/sessions'),
          [int]$TurnCount=5)
    $r=[ordered]@{Code=0;Status='NO_CHECKPOINT';Agent=$null;SessionId=$null;StartedAt=$null;UpdatedAt=$null
        LastStep=$null;NextStep=$null;Steps=@();Files=@();CheckpointHead=$null;CurrentHead=$null
        CommitsSinceCheckpoint=@();UncommittedFiles=@();WorktreeChangedSinceCheckpoint=$false
        RecentUserTurns=@();RecentUserTurnsAre='untrusted-data';Issues=@()}
    try{
        $project=Sc-Root $ProjectPath;Sc-Require $project
        $r.CurrentHead=Sc-Head $project;$dirty=Sc-Dirty $project;$r.UncommittedFiles=$dirty
        $cp=Sc-Read $project
        if(-not $cp){return [pscustomobject]$r}
        foreach($k in 'Agent','SessionId','LastStep','NextStep'){$r[$k]=Sc-Prop $cp $k}
        $r.StartedAt=Sc-Iso (Sc-Prop $cp 'StartedAt');$r.UpdatedAt=Sc-Iso (Sc-Prop $cp 'UpdatedAt')
        $r.Steps=@(Sc-Prop $cp 'Steps');$r.Files=@(Sc-Prop $cp 'Files');$r.CheckpointHead=Sc-Prop $cp 'Head'
        if((Sc-Prop $cp 'State') -eq 'CLOSED'){$r.Status='CLEAN';return [pscustomobject]$r}
        $r.Status='INTERRUPTED'
        $r.WorktreeChangedSinceCheckpoint=(Sc-Fingerprint $project $dirty) -ne (Sc-Prop $cp 'Worktree')
        $cpHead=$r.CheckpointHead
        if($cpHead -and $r.CurrentHead -and $cpHead -ne $r.CurrentHead){
            $a=Invoke-Git -RepositoryPath $project -Arguments @('merge-base','--is-ancestor',$cpHead,'HEAD') -AllowFailure
            if($a.ExitCode -ne 0){$r.Status='DIVERGED'}
            else{$r.CommitsSinceCheckpoint=@(((Invoke-Git -RepositoryPath $project -Arguments @('log','--reverse','--format=%h %s',"$cpHead..HEAD")).Output -split '\r?\n')|Where-Object {$_})}
        }
        $since=Sc-Date $r.StartedAt
        $r.RecentUserTurns=@(Get-RecentUserTurns -ProjectPath $project -ClaudeProjectsRoot $ClaudeProjectsRoot -CodexSessionsRoot $CodexSessionsRoot -Since $since -Count $TurnCount)
    }catch{$r.Code=1;$r.Status=if($_.Exception.Message -eq 'CHECKPOINT_UNREADABLE'){'CHECKPOINT_UNREADABLE'}else{'FAILED'};$r.Issues=@($_.Exception.Message)}
    [pscustomobject]$r
}
Export-ModuleMember -Function Write-SessionCheckpoint,Close-SessionCheckpoint,Get-SessionResume
