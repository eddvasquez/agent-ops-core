Set-StrictMode -Version 2
# Commit (and optionally tag) explicit paths as one verified operation for agents.
# Each step checks its postcondition and stops the sequence on failure: no tag after a failed
# commit, no tag on the wrong commit, messages passed by file so quotes and accents survive 5.1.
Import-Module (Join-Path $PSScriptRoot 'NativeProcess.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Versioning.psm1') -Force
$script:emptyTree='4b825dc642cb6eb9a060e54bf8d69288fbee4904'

function Ac-List($r){@(($r.Output -split "`0")|Where-Object {$_})}
function Ac-Temp([string]$text){
    $p=Join-Path ([IO.Path]::GetTempPath()) ('aoc-msg-'+[guid]::NewGuid().ToString('N')+'.txt')
    [IO.File]::WriteAllText($p,$text,(New-Object Text.UTF8Encoding($false)));return $p
}

function Invoke-AgentOpsCommit {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryPath,[Parameter(Mandatory)][string[]]$Paths,
          [string]$Message='',[string]$MessageFile='',[string]$Tag='',[string]$TagMessage='',[switch]$SkipChecks)
    $res=[ordered]@{Code=1;Status='FAILED';Step='';Sha=$null;PreviousSha=$null;Tag=$null;Files=@();Issues=@()}
    $temp=@()
    $step={param($name) $res.Step=$name}
    try{
        & $step 'input'
        $root=(Resolve-Path -LiteralPath $RepositoryPath).Path
        if($MessageFile){$Message=[IO.File]::ReadAllText((Resolve-Path -LiteralPath $MessageFile).Path,[Text.Encoding]::UTF8)}
        if(-not $Message.Trim()){throw 'A commit message is required (-Message or -MessageFile).'}
        if($Tag -and $Tag -notmatch '^[A-Za-z0-9._@/-]+$'){throw "Invalid tag name: $Tag"}

        & $step 'index'
        $pre=@(Ac-List (Invoke-Git $root @('diff','--cached','--name-only','-z','--no-renames')))
        if($pre.Count){throw ('The index already has staged changes not requested here: '+($pre -join ', ')+'. Unstage them or include them in -Paths.')}

        & $step 'stage'
        Invoke-Git $root (@('add','--')+$Paths)|Out-Null
        $staged=@(Ac-List (Invoke-Git $root @('diff','--cached','--name-only','-z','--no-renames')))
        if(-not $staged.Count){throw 'Nothing to commit: the requested paths have no changes.'}
        $res.Files=$staged

        & $step 'commit'
        $head=Invoke-Git $root @('rev-parse','--verify','-q','HEAD') -AllowFailure
        $old=$(if($head.ExitCode -eq 0){$head.Output.Trim()}else{$null});$res.PreviousSha=$old
        $msg=Ac-Temp $Message;$temp+=$msg
        Invoke-Git $root @('commit','-q','-F',$msg)|Out-Null
        $new=(Invoke-Git $root @('rev-parse','HEAD')).Output.Trim()
        if(-not $new -or $new -eq $old){throw 'HEAD did not move; the commit was not created.'}
        $committed=@(Ac-List (Invoke-Git $root @('diff-tree','--root','--no-commit-id','--name-only','-r','-z','--no-renames',$new)))
        if(@(Compare-Object @($committed|Sort-Object) @($staged|Sort-Object)).Count){throw ('The commit does not contain exactly the requested paths: '+($committed -join ', '))}
        $res.Sha=$new

        if(-not $SkipChecks){
            & $step 'versioning'
            $base=$(if($old){$old}else{$script:emptyTree})
            $v=Test-AgentOpsVersioning -RepositoryPath $root -Base $base -Head $new
            if($v.Code -ne 0){
                # Undo only the commit just created; the changes stay staged for the agent to fix.
                if($old){Invoke-Git $root @('reset','-q','--soft',$old)|Out-Null}else{Invoke-Git $root @('update-ref','-d','HEAD')|Out-Null}
                $res.Sha=$null
                throw ('Versioning check failed; the commit was undone and the changes remain staged: '+($v.Issues -join '; '))
            }
        }
        $res.Status='COMMITTED'

        if($Tag){
            & $step 'tag'
            if((Invoke-Git $root @('rev-parse','-q','--verify',"refs/tags/$Tag") -AllowFailure).ExitCode -eq 0){throw "Tag $Tag already exists; existing tags are never moved."}
            $tagMsg=Ac-Temp $(if($TagMessage){$TagMessage}else{$Tag});$temp+=$tagMsg
            Invoke-Git $root @('tag','-a',$Tag,$new,'-F',$tagMsg)|Out-Null
            $target=(Invoke-Git $root @('rev-parse',"$Tag^{commit}")).Output.Trim()
            if($target -ne $new){Invoke-Git $root @('tag','-d',$Tag) -AllowFailure|Out-Null;throw "Tag $Tag did not point to $new; it was removed."}
            if(-not $SkipChecks){
                $t=Test-AgentOpsVersioning -RepositoryPath $root
                $bad=@($t.Issues|Where-Object {$_ -match [regex]::Escape($Tag)})
                if($bad.Count){Invoke-Git $root @('tag','-d',$Tag) -AllowFailure|Out-Null;throw ('Tag rejected by the versioning check and removed: '+($bad -join '; '))}
            }
            $res.Tag=$Tag;$res.Status='TAGGED'
        }
        $res.Code=0;$res.Step=''
    }catch{$res.Issues=@($_.Exception.Message)}
    finally{foreach($f in $temp){Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}}
    return [pscustomobject]$res
}
Export-ModuleMember -Function Invoke-AgentOpsCommit
