Set-StrictMode -Version 2
# Protocol 7 verifier: SemVer declarations, Keep a Changelog files and release tags.
$script:semver='(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?'
$script:maxReleased=10

function Vr-Git([string]$root,[string[]]$arguments,[switch]$AllowFailure){
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=(Get-Command git.exe -ErrorAction Stop).Source
    $all=@('-C',$root,'-c','core.quotepath=false')+$arguments
    $info.Arguments=($all|ForEach-Object {'"'+($_ -replace '"','\"')+'"'}) -join ' '
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.StandardOutputEncoding=[Text.Encoding]::UTF8;$info.StandardErrorEncoding=[Text.Encoding]::UTF8
    $info.EnvironmentVariables['GIT_TERMINAL_PROMPT']='0'
    $p=New-Object Diagnostics.Process;$p.StartInfo=$info
    [void]$p.Start();$out=$p.StandardOutput.ReadToEnd();[void]$p.StandardError.ReadToEnd();$p.WaitForExit()
    if($p.ExitCode -ne 0){if($AllowFailure){return $null};throw ('git '+($arguments -join ' ')+' failed.')}
    return $out
}
function Vr-Paths([string]$text){ @($text -split "`0"|Where-Object {$_}) }

function Get-ChangelogInfo([string]$text){
    $lines=@($text -split "\r?\n")
    $released=@($lines|ForEach-Object {if($_ -match ('^## \[('+$script:semver+')\] - \d{4}-\d{2}-\d{2}\s*$')){$Matches[1]}})
    [pscustomobject]@{
        HasUnreleased=[bool](@($lines|Where-Object {$_ -match '^## \[Unreleased\]\s*$'}).Count)
        Released=$released
        Latest=$(if($released.Count){$released[0]}else{$null})
    }
}
function Get-SkillVersion([string]$text){
    if($text -notmatch ('(?s)^'+[char]0xFEFF+'?---\r?\n(.*?)\r?\n---')){return $null}
    foreach($line in ($Matches[1] -split "\r?\n")){
        if($line -match '^version:\s*["'']?([^"''\s]+)["'']?\s*$'){return $Matches[1]}
    }
    return $null
}
function Get-FrontmatterIssue([string]$text){
    # A key inserted right after 'key: >-' (or '|') leaves the block scalar empty and the YAML invalid.
    if($text -notmatch ('(?s)^'+[char]0xFEFF+'?---\r?\n(.*?)\r?\n---')){return $null}
    $lines=@($Matches[1] -split "\r?\n")
    for($i=0;$i -lt $lines.Count;$i++){
        if($lines[$i] -match '^([A-Za-z0-9_-]+):\s*[>|][+-]?\s*$'){
            $key=$Matches[1]
            if($i+1 -ge $lines.Count -or $lines[$i+1] -notmatch '^\s+\S'){return "block scalar '$key' has no indented content right after it (a key was probably inserted inside it)"}
        }
    }
    return $null
}
function Test-SemVer([string]$v){ return ($v -and $v -match ('^'+$script:semver+'$')) }

function Test-AgentOpsVersioning {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryPath,[string]$Base='',[string]$Head='HEAD')
    $issues=New-Object Collections.Generic.List[string];$warnings=New-Object Collections.Generic.List[string];$artifacts=@()
    try{
        $root=(Resolve-Path -LiteralPath $RepositoryPath).Path
        $files=Vr-Paths (Vr-Git $root @('ls-files','-z','--cached','--others','--exclude-standard'))
        $files=@($files|Where-Object {Test-Path -LiteralPath (Join-Path $root $_) -PathType Leaf})

        # Changed paths: an explicit range (CI) or the working tree against HEAD (handoff).
        if($Base){$changed=Vr-Paths (Vr-Git $root @('diff','--name-only','-z',$Base,$Head))}
        else{
            $hasHead=$null -ne (Vr-Git $root @('rev-parse','--verify','-q','HEAD') -AllowFailure)
            $changed=@()
            if($hasHead){$changed+=Vr-Paths (Vr-Git $root @('diff','--name-only','-z','HEAD'))}
            $changed+=Vr-Paths (Vr-Git $root @('ls-files','-z','--others','--exclude-standard'))
        }
        $changed=@($changed|Sort-Object -Unique)

        # Skills: every folder holding SKILL.md, with its changelog at changelogs/<name>.md.
        $skills=@{}
        foreach($f in $files){
            if($f -match '^(?:(.*)/)?([^/]+)/SKILL\.md$'){
                $dir=$(if($Matches[1]){$Matches[1]+'/'+$Matches[2]}else{$Matches[2]})
                $skills[$Matches[2]]=$dir
            }
        }
        # Files may live at the root or under docs/ (the framework uses docs/ so old bootstraps accept it).
        $first={param([string[]]$candidates) foreach($c in $candidates){if(Test-Path -LiteralPath (Join-Path $root $c) -PathType Leaf){return $c}};return $candidates[0]}
        foreach($name in ($skills.Keys|Sort-Object)){
            $dir=$skills[$name];$log=& $first @("changelogs/$name.md","docs/changelogs/$name.md")
            $skillText=[IO.File]::ReadAllText((Join-Path $root "$dir/SKILL.md"))
            $declared=Get-SkillVersion $skillText
            $yaml=Get-FrontmatterIssue $skillText
            if($yaml){$issues.Add("Skill $name ($dir/SKILL.md) frontmatter: $yaml.")}
            $artifacts+=[pscustomobject]@{Name=$name;Kind='skill';Path=$dir;Version=$declared;Changelog=$log}
            if(-not (Test-SemVer $declared)){$issues.Add("Skill $name ($dir/SKILL.md) must declare a SemVer 'version:' in its frontmatter (found '$declared').")}
            $logPath=Join-Path $root $log
            if(-not (Test-Path -LiteralPath $logPath -PathType Leaf)){$issues.Add("Skill $name has no changelog at $log.")}
            else{
                $info=Get-ChangelogInfo ([IO.File]::ReadAllText($logPath))
                if(-not $info.HasUnreleased){$issues.Add("$log must keep a '## [Unreleased]' section.")}
                if($info.Latest -and (Test-SemVer $declared) -and $declared -ne $info.Latest){$issues.Add("Skill $name declares $declared but the latest released entry in $log is $($info.Latest).")}
                if($info.Released.Count -gt $script:maxReleased){$warnings.Add("Skill $name changelog keeps $($info.Released.Count) released sections; archive older ones to changelogs/archive/$name.md.")}
            }
            $touched=@($changed|Where-Object {$_.StartsWith($dir+'/')})
            if($touched.Count -and $changed -notcontains $log){$issues.Add("Skill $name changed ($($touched -join ', ')) without an entry in $log.")}
        }

        # Root project: CHANGELOG.md (and optional VERSION) cover everything except handoff metadata.
        $rootLogKey=& $first @('CHANGELOG.md','docs/CHANGELOG.md')
        $rootLog=Join-Path $root $rootLogKey
        if(Test-Path -LiteralPath $rootLog -PathType Leaf){
            $info=Get-ChangelogInfo ([IO.File]::ReadAllText($rootLog))
            $versionKey=& $first @('VERSION','docs/VERSION')
            $versionFile=Join-Path $root $versionKey
            $declared=$(if(Test-Path -LiteralPath $versionFile){([IO.File]::ReadAllText($versionFile)).Trim()}else{$null})
            $artifacts+=[pscustomobject]@{Name='(project)';Kind='project';Path='.';Version=$declared;Changelog=$rootLogKey}
            if(-not $info.HasUnreleased){$issues.Add("$rootLogKey must keep a '## [Unreleased]' section.")}
            if($null -ne $declared){
                if(-not (Test-SemVer $declared)){$issues.Add("$versionKey must contain a SemVer value (found '$declared').")}
                elseif($info.Latest -and $declared -ne $info.Latest){$issues.Add("$versionKey declares $declared but the latest released entry in $rootLogKey is $($info.Latest).")}
            }
            if($info.Released.Count -gt $script:maxReleased){$warnings.Add("$rootLogKey keeps $($info.Released.Count) released sections; archive older ones to changelogs/archive/project.md.")}
            $touched=@($changed|Where-Object {$_ -ne $rootLogKey -and $_ -notmatch '^(\.context|changelogs|docs/changelogs)/'})
            if($touched.Count -and $changed -notcontains $rootLogKey){$issues.Add("Changes outside .context/ ($($touched -join ', ')) require an entry in $rootLogKey.")}
        }

        # Tags: vX.Y.Z (project) and <skill>@vX.Y.Z must match the files at the tagged commit.
        foreach($tag in @((Vr-Git $root @('tag','--list')) -split "\r?\n"|Where-Object {$_})){
            if($tag -match ('^v('+$script:semver+')$')){
                $v=$Matches[1]
                $log=Vr-Git $root @('show',"$tag^{commit}:CHANGELOG.md") -AllowFailure
                if($null -eq $log){$log=Vr-Git $root @('show',"$tag^{commit}:docs/CHANGELOG.md") -AllowFailure}
                if($null -eq $log -or (Get-ChangelogInfo $log).Released -notcontains $v){$issues.Add("Tag $tag has no '## [$v]' entry in CHANGELOG.md at that commit.");continue}
                $ver=Vr-Git $root @('show',"$tag^{commit}:VERSION") -AllowFailure
                if($null -eq $ver){$ver=Vr-Git $root @('show',"$tag^{commit}:docs/VERSION") -AllowFailure}
                if($null -ne $ver -and $ver.Trim() -ne $v){$issues.Add("Tag $tag points to a commit whose VERSION is $($ver.Trim()).")}
            }elseif($tag -match ('^([^@]+)@v('+$script:semver+')$')){
                $name=$Matches[1];$v=$Matches[2]
                $log=Vr-Git $root @('show',"$tag^{commit}:changelogs/$name.md") -AllowFailure
                if($null -eq $log){$log=Vr-Git $root @('show',"$tag^{commit}:docs/changelogs/$name.md") -AllowFailure}
                $tree=Vr-Paths (Vr-Git $root @('ls-tree','-r','-z','--name-only',"$tag^{commit}"))
                $def=@($tree|Where-Object {$_ -match ('(^|/)'+[regex]::Escape($name)+'/SKILL\.md$')})|Select-Object -First 1
                $ver=$(if($def){Get-SkillVersion (Vr-Git $root @('show',"$tag^{commit}:$def"))}else{$null})
                if($null -eq $log -or (Get-ChangelogInfo $log).Released -notcontains $v -or $ver -ne $v){$issues.Add("Tag $tag does not match changelogs/$name.md and the skill version at that commit.")}
            }
        }
    }catch{$issues.Add($_.Exception.Message)}
    [pscustomobject]@{Code=$(if($issues.Count){1}else{0});Issues=@($issues);Warnings=@($warnings);Artifacts=$artifacts;Changed=@($changed)}
}
Export-ModuleMember -Function Test-AgentOpsVersioning
