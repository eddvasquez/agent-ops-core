Set-StrictMode -Version 2
# Project hygiene sensor (read-only). Reports leftovers that silently pile up in a project:
# copies of hub skills, old provisional files and governance not saved in history. It never changes anything;
# what to remove is decided by the user in that project's own session (R-006).
Import-Module (Join-Path $PSScriptRoot 'NativeProcess.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'HarnessRadar.psm1') -Force
$script:scratchDirs=@('scratch','tmp','.tmp')
$script:scratchDays=7
$script:governance=@('AGENTS.md','.context','CHANGELOG.md','VERSION','docs/CHANGELOG.md','docs/VERSION')

function Ph-TreeHash([string]$dir){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{
        $parts=foreach($f in @(Get-ChildItem -LiteralPath $dir -Recurse -Force -File|Where-Object {$_.FullName -notmatch '\\__pycache__\\'}|Sort-Object FullName)){
            $rel=$f.FullName.Substring($dir.Length).TrimStart('\').Replace('\','/')
            $rel+':'+([BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($f.FullName)))).Replace('-','')
        }
        return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($parts -join "`n"))))).Replace('-','')
    }finally{$sha.Dispose()}
}
function Ph-Count([int]$n,[string]$one,[string]$many){if($n -eq 1){"1 $one"}else{"$n $many"}}
function Ph-Finding([string]$kind,[string]$message,[string]$fix,[string[]]$paths,[hashtable]$extra=@{}){
    $f=[ordered]@{Kind=$kind;Message=$message;Fix=$fix;Paths=@($paths)};foreach($k in $extra.Keys){$f[$k]=$extra[$k]};[pscustomobject]$f
}

function Get-AgentOpsProjectHygiene {
    [CmdletBinding()]
    param([string]$ProjectPath=(Get-Location).Path,[string]$HubDir='',
          [string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'),
          [int]$CodexRefsThreshold=25)
    $res=[ordered]@{Code=0;Status='CLEAN';Findings=@();Lines=@();Issues=@()}
    try{
        $root=(Resolve-Path -LiteralPath $ProjectPath).Path
        if(-not $HubDir -and [IO.File]::Exists($ConfigPath)){$HubDir=[string](([IO.File]::ReadAllText($ConfigPath)|ConvertFrom-Json).HubDir)}

        # 1. Copies of hub skills (the framework repository keeps its own skill sources: not copies).
        if($HubDir -and [IO.Directory]::Exists($HubDir) -and -not (Test-AgentOpsFrameworkRepository -ProjectPath $root)){
            $identical=@();$different=@();$paths=@()
            foreach($folder in @('skills','_ai-skills-hub')){
                $dir=Join-Path $root $folder;if(-not [IO.Directory]::Exists($dir)){continue}
                foreach($skill in @(Get-ChildItem -LiteralPath $dir -Directory -Force|Where-Object {[IO.File]::Exists((Join-Path $_.FullName 'SKILL.md'))})){
                    $hubSkill=Join-Path $HubDir $skill.Name
                    if(-not [IO.File]::Exists((Join-Path $hubSkill 'SKILL.md'))){continue}
                    $paths+="$folder/$($skill.Name)"
                    if((Ph-TreeHash $skill.FullName) -eq (Ph-TreeHash $hubSkill)){$identical+=$skill.Name}else{$different+=$skill.Name}
                }
            }
            $n=$identical.Count+$different.Count
            if($n){
                $res.Findings+=Ph-Finding 'skills-copy' "Hay $(Ph-Count $n 'copia' 'copias') de skills del hub dentro del proyecto ($($identical.Count) idénticas, $($different.Count) distintas); un agente podría seguir instrucciones antiguas." 'Revísalas en la sesión de este proyecto: las idénticas se pueden retirar; en las distintas, compara antes por si guardan cambios propios que deban pasar al hub.' $paths @{Identical=@($identical);Different=@($different)}
            }
        }

        # 2. Old provisional files.
        $limit=(Get-Date).AddDays(-$script:scratchDays);$old=@()
        foreach($folder in $script:scratchDirs){
            $dir=Join-Path $root $folder;if(-not [IO.Directory]::Exists($dir)){continue}
            $old+=@(Get-ChildItem -LiteralPath $dir -Recurse -Force -File|Where-Object {$_.LastWriteTime -lt $limit}|ForEach-Object {$_.FullName.Substring($root.Length).TrimStart('\').Replace('\','/')})
        }
        if($old.Count){
            $res.Findings+=Ph-Finding 'old-scratch' "Hay $(Ph-Count $old.Count 'archivo provisional' 'archivos provisionales') con más de $($script:scratchDays) días en $(($script:scratchDirs|ForEach-Object {"$_/"}) -join ', ')." 'Revísalos: bórralos si ya no sirven o guarda en el proyecto lo que deba conservarse.' $old
        }

        # 3. Governance not saved in history (only for Git projects, and only what the project does not ignore).
        $top=Invoke-Git $root @('rev-parse','--show-toplevel') -AllowFailure
        $isGit=($top.ExitCode -eq 0 -and [IO.Path]::GetFullPath(($top.Output.Trim() -replace '/','\')).TrimEnd('\') -eq $root.TrimEnd('\'))
        if($isGit){
            $raw=(Invoke-Git $root (@('--no-optional-locks','-c','core.quotePath=false','status','--porcelain=v1','-z','--untracked-files=all','--')+$script:governance)).Output
            $unsaved=@(@($raw -split "`0")|Where-Object {$_.Length -gt 3}|ForEach-Object {$_.Substring(3)}|Sort-Object -Unique)
            if($unsaved.Count){
                $res.Findings+=Ph-Finding 'unsaved-governance' "Hay $(Ph-Count $unsaved.Count 'archivo de gobernanza' 'archivos de gobernanza') sin guardar en el historial; si el equipo falla o se cambia de carpeta, se pierden." 'Guárdalos con la herramienta de commit del marco en la sesión de este proyecto.' $unsaved
            }
        }

        # 4. Old backups, dumps, state files and unreferenced leftovers (WSTG-CONF-03, read-only).
        $skipRe='(^|/)(\.git|node_modules|\.venv|venv|vendor|scratch|tmp|\.tmp|__pycache__)(/|$)'
        $webRe='^(web|public|www|dist|build)/'
        $candidates=@()
        foreach($f in @(Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction SilentlyContinue)){
            $rel=$f.FullName.Substring($root.Length).TrimStart('\').Replace('\','/')
            if($rel -match $skipRe){continue}
            $isSql=($rel -match '\.sql$' -and ($rel -notmatch '^(?:.*/)?(?:db/)?(?:migrations?|schema|seeds?)/' -or $rel -match '(?i)(dump|backup)'))
            $isBak=($rel -match '\.(bak|old|orig|save|swp|swo|dump|tfstate|tfstate\.backup|kdbx)$' -or $rel -match '~$' -or $rel -match '(?i)(^|/)\.htpasswd$')
            $isDiag=($rel -match '(?i)(^|/)(phpinfo\.php|debug\.log|error_log)$')
            if(-not ($isSql -or $isBak -or $isDiag)){continue}
            if($isGit -and $rel -notmatch $webRe){
                $ig=Invoke-Git $root @('check-ignore','-q','--',$rel) -AllowFailure
                if($ig.ExitCode -eq 0){continue}
            }
            $candidates+=$rel
        }
        $candidates=@($candidates|Sort-Object -Unique)
        if($candidates.Count){
            $res.Findings+=Ph-Finding 'backup-or-unreferenced' "Hay $(Ph-Count $candidates.Count 'copia de respaldo o resto sensible olvidado' 'copias de respaldo o restos sensibles olvidados') en el proyecto." 'Revisa estas rutas: borra las copias que ya no sirvan o muevelas fuera del proyecto (y fuera de carpetas web).' $candidates
        }

        # 5. Accumulated Codex turn-diff references (read-only).
        if($isGit){
            $cref=Invoke-Git $root @('for-each-ref','--format=%(refname)','refs/codex/turn-diffs') -AllowFailure
            $refs=@($cref.Output -split "\r?\n"|Where-Object {$_.Trim()})
            if($refs.Count -gt $CodexRefsThreshold){
                $res.Findings+=Ph-Finding 'codex-turn-diffs' "Hay $($refs.Count) referencias internas de Codex acumuladas en el repositorio (refs/codex/turn-diffs)." 'Si ya no las necesitas, puedes limpiarlas en este proyecto (por ejemplo con git update-ref -d).' @('.git/refs/codex/turn-diffs')
            }
        }
        if(@($res.Findings).Count){$res.Status='FINDINGS';$res.Lines=@($res.Findings|ForEach-Object {"Higiene del proyecto: $($_.Message)"})}
    }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($_.Exception.Message)}
    return [pscustomobject]$res
}
Export-ModuleMember -Function Get-AgentOpsProjectHygiene
