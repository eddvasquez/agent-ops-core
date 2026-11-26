# Governed learning: candidates are captured in the hub inbox and proposals are validated
# before a human decides. Nothing here modifies a skill.
Set-StrictMode -Version 2
$script:Signals=@('correccion','fallo','patron','exito')
$script:Risks=@('bajo','medio','alto')
$script:SkillCeiling=25
$script:DescriptionLimit=300
$script:OfficialDescriptionLimit=1024
$script:MaxBodyLines=500
$script:DefaultListingBudget=6000
$script:UsageOutcomes=@('used','helped','hurt','neutral','skipped','error')
$script:CoreSkills=@('dev-systematic-debugging','dev-tdd','ops-git-worktrees','ops-project-init','ops-project-migrate','ops-session-handoff')

function ConvertTo-LearningKey([string]$Text){
    $d=$Text.Trim().ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
    -join @($d.ToCharArray()|Where-Object {[Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark'})
}
function Get-LearningHubSkills([string]$HubPath){
    if(-not [IO.Directory]::Exists($HubPath)){return @()}
    @([IO.Directory]::GetDirectories($HubPath)|Where-Object {[IO.File]::Exists((Join-Path $_ 'SKILL.md'))}|ForEach-Object {[IO.Path]::GetFileName($_)})
}
function Test-LearningSkillName([string]$Name){ $Name -cmatch '^[a-z0-9][a-z0-9-]{0,63}$' }

function New-LearningCandidate {
    param([Parameter(Mandatory=$true)][string]$HubPath,[Parameter(Mandatory=$true)][string]$Signal,
          [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Project,[Parameter(Mandatory=$true)][AllowEmptyString()][string]$Harness,
          [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Summary,[Parameter(Mandatory=$true)][AllowEmptyString()][string]$Evidence,
          [string]$Skill='',[Nullable[datetime]]$Now=$null)
    $issues=New-Object Collections.Generic.List[string]
    if(-not [IO.Directory]::Exists($HubPath)){$issues.Add("Hub no encontrado: $HubPath")}
    $sig=ConvertTo-LearningKey $Signal
    if($script:Signals -notcontains $sig){$issues.Add("Señal no válida '$Signal'; usar: $($script:Signals -join ', ').")}
    foreach($f in @(@('Proyecto',$Project),@('Arnés',$Harness),@('Resumen',$Summary),@('Evidencia',$Evidence))){
        if([string]::IsNullOrWhiteSpace($f[1])){$issues.Add("$($f[0]) vacío.")}
    }
    if($Skill -and (Get-LearningHubSkills $HubPath) -notcontains $Skill){$issues.Add("SKILL_NOT_IN_HUB: '$Skill' no es una skill del hub; las de terceros no reciben propuestas.")}
    if($issues.Count){return @{Code=2;Status='INVALID';Path=$null;Id=$null;Issues=@($issues)}}
    $stamp=if($null -ne $Now){[datetime]$Now}else{Get-Date}
    $inbox=Join-Path $HubPath 'proposals/inbox';[IO.Directory]::CreateDirectory($inbox)|Out-Null
    $body=@('# Candidata {0}','',"- Señal: $sig","- Proyecto: $($Project.Trim())","- Arnés: $($Harness.Trim())",
            "- Fecha: $($stamp.ToString('yyyy-MM-ddTHH:mm:ss'))","- Skill: $(if($Skill){$Skill}else{'(sin asignar)'})",
            '','## Resumen',$Summary.Trim(),'','## Evidencia',$Evidence.Trim(),'') -join "`n"
    for($attempt=0;$attempt -lt 20;$attempt++){
        $id=$stamp.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,6)
        $path=Join-Path $inbox "$id.md"
        try{
            $stream=[IO.File]::Open($path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
            try{$bytes=[Text.UTF8Encoding]::new($false).GetBytes(($body -f $id));$stream.Write($bytes,0,$bytes.Length)}finally{$stream.Dispose()}
            return @{Code=0;Status='CAPTURED';Path=$path;Id=$id;Issues=@()}
        }catch [IO.IOException]{ if([IO.File]::Exists($path)){continue}; throw }
    }
    return @{Code=1;Status='FAILED';Path=$null;Id=$null;Issues=@('No se pudo crear un identificador único.')}
}

function Read-LearningProposal([string]$Text){
    $fields=@{};$sections=@{};$current=$null
    foreach($line in ($Text -split "`r?`n")){
        if($line -match '^##\s+(?!#)(.+?)\s*$'){$current=ConvertTo-LearningKey $Matches[1];$sections[$current]=New-Object Collections.Generic.List[string];continue}
        if($null -eq $current){ if($line -match '^-\s+([^:]+):\s*(.*)$'){$fields[(ConvertTo-LearningKey $Matches[1])]=$Matches[2].Trim()}; continue }
        $sections[$current].Add($line)
    }
    return @{Fields=$fields;Sections=$sections}
}
function Get-LearningSection($Parsed,[string]$Name){
    $k=ConvertTo-LearningKey $Name
    if($Parsed.Sections.ContainsKey($k)){return (@($Parsed.Sections[$k]) -join "`n").Trim()}
    return ''
}

function Test-LearningProposal {
    param([Parameter(Mandatory=$true)][string]$Path,[string]$HubPath='')
    if(-not [IO.File]::Exists($Path)){return @{Code=1;Status='FAILED';Issues=@("Ficha no encontrada: $Path");Proposal=$null}}
    $p=Read-LearningProposal ([IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8))
    $issues=New-Object Collections.Generic.List[string]
    $f=$p.Fields
    $get={param($k) if($f.ContainsKey($k)){$f[$k]}else{''}}
    $proposal=@{Destination=$null;Skill=(& $get 'skill');From=$null;To=$null;Risk=(ConvertTo-LearningKey (& $get 'riesgo'));Added=$null;Removed=$null;Blocks=0}

    $dest=& $get 'destino'
    if($dest -match '^[34567]$'){$proposal.Destination=[int]$dest}
    elseif($dest -match '^[12]$'){$issues.Add("Destino $dest no es una propuesta de skill: va a 'nada' o a reglas_proyecto.md.")}
    else{$issues.Add("Destino no válido '$dest'; usar 3 (parche), 4 (referencia), 5 (skill nueva), 6 (archivar) o 7 (fusionar).")}

    if(-not (Test-LearningSkillName $proposal.Skill)){$issues.Add("Skill no válida '$($proposal.Skill)'.")}
    if($script:Risks -notcontains $proposal.Risk){$issues.Add("Riesgo no válido; usar: $($script:Risks -join ', ').")}

    $ver=& $get 'version'
    if($proposal.Destination -eq 6 -and $ver -match '^(\d+\.\d+\.\d+)\s*->\s*archived$'){
        $proposal.From=$Matches[1];$proposal.To='archived'
    }elseif($ver -match '^(nueva|\d+\.\d+\.\d+)\s*->\s*(\d+\.\d+\.\d+)$'){
        $proposal.From=$Matches[1];$proposal.To=$Matches[2]
        if($proposal.Destination -eq 5 -and $proposal.From -ne 'nueva'){$issues.Add("Versión: una skill nueva se declara 'nueva -> X.Y.Z'.")}
        if($proposal.Destination -in 3,4,7){
            if($proposal.From -eq 'nueva'){$issues.Add('Versión: un parche, referencia o fusión parte de la versión actual de la skill.')}
            elseif([version]$proposal.To -le [version]$proposal.From){$issues.Add("Versión: $($proposal.To) no es mayor que $($proposal.From).")}
        }
    }else{$issues.Add("Versión no válida '$ver'; formato 'X.Y.Z -> X.Y.Z', 'nueva -> X.Y.Z' o 'X.Y.Z -> archived'.")}

    $size=& $get 'tamano'
    if($size -match '^\+(\d+)\s+-(\d+)$'){$proposal.Added=[int]$Matches[1];$proposal.Removed=[int]$Matches[2]}
    else{$issues.Add("Tamaño no válido '$size'; formato '+N -M' (líneas añadidas y quitadas).")}

    if($f.ContainsKey('descripcion nueva') -and $f['descripcion nueva'].Length -gt $script:DescriptionLimit){
        $issues.Add("Descripción nueva de $($f['descripcion nueva'].Length) caracteres; máximo $($script:DescriptionLimit).")
    }
    foreach($s in @('Por qué','Evidencia','Solapamientos','Alternativas descartadas')){
        if(-not (Get-LearningSection $p $s)){$issues.Add("Falta la sección '## $s'.")}
    }
    $change=Get-LearningSection $p 'Cambio'
    $proposal.Blocks=@([regex]::Matches($change,'(?m)^###\s+Bloque\s+\d+')).Count
    if(-not $proposal.Blocks){$issues.Add("'## Cambio' necesita al menos un '### Bloque N' aprobable por separado.")}
    if($proposal.Risk -in 'medio','alto' -and -not (Get-LearningSection $p 'Validación')){
        $issues.Add("Riesgo $($proposal.Risk): falta '## Validación' con la prueba antes y después.")
    }

    $hubSkills=if($HubPath){Get-LearningHubSkills $HubPath}else{$null}
    if($proposal.Destination -in 3,4,6,7 -and $null -ne $hubSkills -and $hubSkills -notcontains $proposal.Skill){
        $issues.Add("SKILL_NOT_IN_HUB: '$($proposal.Skill)' no es una skill del hub; las de terceros no reciben parches.")
    }
    if($proposal.Destination -eq 7){
        $absorbed=& $get 'habilidad absorbida'
        $proposal['Absorbed']=$absorbed
        if(-not (Test-LearningSkillName $absorbed) -or $absorbed -eq $proposal.Skill){$issues.Add("Falta '- Habilidad absorbida: <nombre>' válida y distinta de '$($proposal.Skill)'.")}
        elseif($null -ne $hubSkills -and $hubSkills -notcontains $absorbed){$issues.Add("SKILL_NOT_IN_HUB: '$absorbed' no existe en el hub para fusionar.")}
    }
    if($proposal.Destination -eq 5){
        $umbral=Get-LearningSection $p 'Umbral'
        $checked=@([regex]::Matches($umbral,'(?m)^-\s+\[[xX]\]')).Count
        $open=@([regex]::Matches($umbral,'(?m)^-\s+\[\s\]')).Count
        if($checked -lt 4 -or $open){$issues.Add("Umbral: una skill nueva exige las cuatro condiciones marcadas ($checked de 4).")}
        if($null -ne $hubSkills){
            if($hubSkills -contains $proposal.Skill){$issues.Add("La skill '$($proposal.Skill)' ya existe; proponer un parche (destino 3).")}
            if($hubSkills.Count -ge $script:SkillCeiling -and -not (Get-LearningSection $p 'Fusión o archivo')){
                $issues.Add("Techo de $($script:SkillCeiling) skills alcanzado ($($hubSkills.Count)): añadir '## Fusión o archivo' con la skill que se fusiona o archiva.")
            }
        }
    }
    if($issues.Count){return @{Code=2;Status='INVALID';Issues=@($issues);Proposal=$proposal}}
    return @{Code=0;Status='VALID';Issues=@();Proposal=$proposal}
}

function Get-LearningQueue {
    param([Parameter(Mandatory=$true)][string]$HubPath)
    if(-not [IO.Directory]::Exists($HubPath)){return @{Code=1;Status='FAILED';Issues=@("Hub no encontrado: $HubPath")}}
    $list={param($d) $dir=Join-Path $HubPath "proposals/$d"; if([IO.Directory]::Exists($dir)){@([IO.Directory]::GetFiles($dir,'*.md')|Sort-Object|ForEach-Object {[IO.Path]::GetFileName($_)})}else{@()}}
    $inbox=@(& $list 'inbox');$pending=@(& $list 'pending')
    $skills=@(Get-LearningHubSkills $HubPath)
    return @{Code=0;Status='OK';Inbox=$inbox.Count;Pending=$pending.Count;InboxItems=$inbox;PendingItems=$pending
             ActiveSkills=$skills.Count;SkillCeiling=$script:SkillCeiling;Issues=@()}
}

function Invoke-LearningTriage {
    param([Parameter(Mandatory=$true)][string]$HubPath,[string]$DiscardId='',[string]$Reason='')
    if(-not [IO.Directory]::Exists($HubPath)){return @{Code=1;Status='FAILED';Issues=@("Hub no encontrado: $HubPath");Groups=@()}}
    $inbox=Join-Path $HubPath 'proposals/inbox'
    if($DiscardId){
        $src=Join-Path $inbox "$DiscardId.md"
        if(-not [IO.File]::Exists($src)){return @{Code=1;Status='FAILED';Issues=@("Candidata no encontrada: $src")}}
        $rej=Join-Path $HubPath 'proposals/rejected';[IO.Directory]::CreateDirectory($rej)|Out-Null
        $dst=Join-Path $rej "$DiscardId.md"
        $txt=[IO.File]::ReadAllText($src,[Text.Encoding]::UTF8)+"`n- Motivo rechazo: $Reason`n"
        [IO.File]::WriteAllText($dst,$txt,[Text.UTF8Encoding]::new($false))
        Remove-Item -LiteralPath $src -Force
        return @{Code=0;Status='DISCARDED';Id=$DiscardId;Path=$dst;Issues=@()}
    }
    $bySkill=@{}
    if([IO.Directory]::Exists($inbox)){
        foreach($f in @(Get-ChildItem -LiteralPath $inbox -Filter '*.md' -ErrorAction SilentlyContinue|Sort-Object Name)){
            $p=Read-LearningProposal ([IO.File]::ReadAllText($f.FullName,[Text.Encoding]::UTF8))
            $skill=if($p.Fields.ContainsKey('skill') -and $p.Fields['skill']){$p.Fields['skill']}else{'(sin asignar)'}
            $proj=if($p.Fields.ContainsKey('proyecto')){$p.Fields['proyecto']}else{''}
            $sig=if($p.Fields.ContainsKey('senal')){$p.Fields['senal']}else{''}
            $dt=if($p.Fields.ContainsKey('fecha')){$p.Fields['fecha']}else{$f.BaseName}
            if(-not $bySkill.ContainsKey($skill)){$bySkill[$skill]=@{Skill=$skill;Items=@();Projects=@();Sessions=@();Signals=@()}}
            $bySkill[$skill].Items+=@($f.BaseName)
            if($proj -and $bySkill[$skill].Projects -notcontains $proj){$bySkill[$skill].Projects+=@($proj)}
            if($dt -and $bySkill[$skill].Sessions -notcontains $dt){$bySkill[$skill].Sessions+=@($dt)}
            if($sig -and $bySkill[$skill].Signals -notcontains $sig){$bySkill[$skill].Signals+=@($sig)}
        }
    }
    $groups=@(foreach($k in ($bySkill.Keys|Sort-Object)){
        $g=$bySkill[$k]
        $ready=($g.Projects.Count -ge 2) -or ($g.Sessions.Count -ge 3) -or ($k -ne '(sin asignar)' -and $g.Signals -contains 'correccion')
        [pscustomobject]@{Skill=$k;Count=$g.Items.Count;Items=$g.Items;Projects=$g.Projects;Sessions=$g.Sessions;Signals=$g.Signals;Decision=$(if($ready){'READY_FOR_PROPOSAL'}else{'PROJECT_RULE_CANDIDATE'})}
    })
    return @{Code=0;Status='OK';Groups=$groups;Issues=@()}
}

function Invoke-LearningProposalApply {
    param([Parameter(Mandatory=$true)][string]$HubPath,[Parameter(Mandatory=$true)][string]$Path,
          [int[]]$ApprovedBlocks=@(),[switch]$Reject,[string]$Reason='')
    if(-not [IO.File]::Exists($Path)){return @{Code=1;Status='FAILED';Issues=@("Ficha no encontrada: $Path")}}
    $raw=[IO.File]::ReadAllText($Path,[Text.Encoding]::UTF8)
    if($Reject){
        $rej=Join-Path $HubPath 'proposals/rejected';[IO.Directory]::CreateDirectory($rej)|Out-Null
        $dst=Join-Path $rej ([IO.Path]::GetFileName($Path))
        [IO.File]::WriteAllText($dst,($raw+"`n- Motivo rechazo: $Reason`n"),[Text.UTF8Encoding]::new($false))
        Remove-Item -LiteralPath $Path -Force
        return @{Code=0;Status='REJECTED';Path=$dst;Issues=@()}
    }
    $v=Test-LearningProposal -Path $Path -HubPath $HubPath
    if($v.Code -ne 0){return $v}
    $p=Read-LearningProposal $raw
    if(-not $ApprovedBlocks.Count){return @{Code=2;Status='NO_BLOCKS_APPROVED';Issues=@('Especifica -ApprovedBlocks o -Reject.')}}
    $skill=$v.Proposal.Skill
    $moveArchive={param([string]$targetSkill)
        $srcDir=Join-Path $HubPath $targetSkill
        if(-not [IO.Directory]::Exists($srcDir)){throw "Skill no encontrada para archivar: $srcDir"}
        $arcRoot=Join-Path $HubPath 'proposals/archived';[IO.Directory]::CreateDirectory($arcRoot)|Out-Null
        $arcDst=Join-Path $arcRoot $targetSkill
        if([IO.Directory]::Exists($arcDst)){$arcDst=Join-Path $arcRoot ($targetSkill+'-'+[datetime]::UtcNow.ToString('yyyyMMddHHmmss'))}
        [IO.Directory]::Move($srcDir,$arcDst)
        return $arcDst
    }
    if($v.Proposal.Destination -eq 6){
        $arcDst=& $moveArchive $skill
        $appDir=Join-Path $HubPath 'proposals/applied';[IO.Directory]::CreateDirectory($appDir)|Out-Null
        $appPath=Join-Path $appDir ([IO.Path]::GetFileName($Path))
        Move-Item -LiteralPath $Path -Destination $appPath -Force
        return @{Code=0;Status='APPLIED';Skill=$skill;Version='archived';AppliedBlocks=1;Path=$appPath;ArchivedPath=$arcDst;Issues=@()}
    }
    $change=Get-LearningSection $p 'Cambio'
    $blockMatches=[regex]::Matches($change,'(?ms)^###\s+Bloque\s+(\d+)\s*\r?\n(.*?)(?=^###\s+Bloque\s+\d+|\z)')
    $blocks=@{}
    foreach($bm in $blockMatches){
        $num=[int]$bm.Groups[1].Value;$body=$bm.Groups[2].Value
        $before='';$after=''
        if($body -match '(?ms)Antes:\s*\r?\n```[^\r\n]*\r?\n(.*?)\r?\n```'){$before=$Matches[1]}
        if($body -match '(?ms)Despu[eé]s:\s*\r?\n```[^\r\n]*\r?\n(.*?)\r?\n```'){$after=$Matches[1]}
        $blocks[$num]=@{Before=$before;After=$after}
    }
    $skillMd=Join-Path $HubPath "$skill/SKILL.md"
    if(-not [IO.File]::Exists($skillMd)){return @{Code=1;Status='FAILED';Issues=@("SKILL.md no encontrado: $skillMd")}}
    $content=[IO.File]::ReadAllText($skillMd,[Text.Encoding]::UTF8)
    foreach($b in $ApprovedBlocks){
        if(-not $blocks.ContainsKey($b)){return @{Code=1;Status='PATCH_MISMATCH';Issues=@("Bloque $b no encontrado.")}}
        $bef=$blocks[$b].Before
        if(-not $bef -or -not $content.Contains($bef)){return @{Code=1;Status='PATCH_MISMATCH';Issues=@("Bloque $b no coincide en $skillMd.")}}
        $content=$content.Replace($bef,$blocks[$b].After)
    }
    if($content -match '(?m)^version:\s*\d+\.\d+\.\d+'){
        $content=[regex]::Replace($content,'(?m)^version:\s*\d+\.\d+\.\d+',"version: $($v.Proposal.To)",1)
    }
    [IO.File]::WriteAllText($skillMd,$content,[Text.UTF8Encoding]::new($false))
    $arcDst=$null
    if($v.Proposal.Destination -eq 7 -and $v.Proposal.Absorbed){$arcDst=& $moveArchive $v.Proposal.Absorbed}
    $clDir=Join-Path $HubPath 'changelogs';[IO.Directory]::CreateDirectory($clDir)|Out-Null
    $clPath=Join-Path $clDir "$skill.md"
    $why=(Get-LearningSection $p 'Por que');if(-not $why){$why=(Get-LearningSection $p 'Por qué')}
    $entry="## [$($v.Proposal.To)] - $([datetime]::Now.ToString('yyyy-MM-dd'))`n### Changed`n- $why`n"
    if([IO.File]::Exists($clPath)){
        $clRaw=[IO.File]::ReadAllText($clPath,[Text.Encoding]::UTF8)
        [IO.File]::WriteAllText($clPath,($clRaw+"`n"+$entry),[Text.UTF8Encoding]::new($false))
    }else{
        [IO.File]::WriteAllText($clPath,("# Changelog: $skill`n`n"+$entry),[Text.UTF8Encoding]::new($false))
    }
    $appDir=Join-Path $HubPath 'proposals/applied';[IO.Directory]::CreateDirectory($appDir)|Out-Null
    $appPath=Join-Path $appDir ([IO.Path]::GetFileName($Path))
    Move-Item -LiteralPath $Path -Destination $appPath -Force
    return @{Code=0;Status='APPLIED';Skill=$skill;Version=$v.Proposal.To;AppliedBlocks=$ApprovedBlocks.Count;Path=$appPath;ArchivedPath=$arcDst;Issues=@()}
}

function Get-UsageLockName([string]$Path){
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$h=([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Path.ToLowerInvariant())))).Replace('-','').Substring(0,16).ToLowerInvariant()}finally{$sha.Dispose()}
    $name='Local\AgentOpsUsage-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value+'-'+$h
    if($env:AGENT_OPS_LOCK_NAMESPACE){$name+='-'+$env:AGENT_OPS_LOCK_NAMESPACE}
    return $name
}
function Get-OutcomeRank([string]$o){
    switch($o){
        'hurt'{5}; 'error'{4}; 'helped'{3}; 'skipped'{2}; 'neutral'{1}; default{0}
    }
}
function Get-SkillUsageHistory {
    param([string]$HubPath='',[string]$UsagePath='')
    $dir=if($UsagePath){Split-Path -Parent $UsagePath}elseif($HubPath){Join-Path $HubPath 'proposals'}else{''}
    if(-not $dir -or -not [IO.Directory]::Exists($dir)){return @()}
    $files=@(Get-ChildItem -LiteralPath $dir -Filter 'usage*.jsonl' -File -ErrorAction SilentlyContinue|Sort-Object LastWriteTimeUtc,Name)
    if($UsagePath -and [IO.File]::Exists($UsagePath) -and ($files.FullName -notcontains $UsagePath)){$files+=@(Get-Item -LiteralPath $UsagePath)}
    $bySession=@{};$anon=New-Object Collections.ArrayList
    foreach($f in $files){
        foreach($raw in [IO.File]::ReadAllLines($f.FullName,[Text.Encoding]::UTF8)){
            if(-not $raw.Trim()){continue}
            try{$e=$raw|ConvertFrom-Json}catch{continue}
            if(-not $e.PSObject.Properties['skill']){continue}
            if($e.PSObject.Properties['session_id'] -and $e.session_id){
                $k="$($e.session_id)|$($e.skill)"
                if(-not $bySession.ContainsKey($k)){$bySession[$k]=$e}
                else{
                    $cur=$bySession[$k]
                    if((Get-OutcomeRank ([string]$e.outcome)) -ge (Get-OutcomeRank ([string]$cur.outcome))){$bySession[$k]=$e}
                }
            }else{[void]$anon.Add($e)}
        }
    }
    return @($bySession.Values)+$anon.ToArray()
}
function Register-SkillUsage {
    param([Parameter(Mandatory=$true)][string]$Skill,[string]$Project='(sin proyecto)',[string]$Outcome='used',
          [string]$SessionId='',[string]$Harness='unknown',[string]$Source='declared',
          [string]$HubPath='',[string]$UsagePath='',[Nullable[datetime]]$Now=$null)
    $issues=New-Object Collections.Generic.List[string]
    if(-not (Test-LearningSkillName $Skill)){$issues.Add("Skill no válida '$Skill'.")}
    $outKey=ConvertTo-LearningKey $Outcome
    if($script:UsageOutcomes -notcontains $outKey){$issues.Add("Outcome no válido '$Outcome'; usar: $($script:UsageOutcomes -join ', ').")}
    if(-not $UsagePath -and -not $HubPath){$issues.Add('Especifica -HubPath o -UsagePath.')}
    if($issues.Count){return @{Code=2;Status='INVALID';Path=$null;Issues=@($issues)}}
    $target=if($UsagePath){$UsagePath}else{Join-Path $HubPath 'proposals/usage.jsonl'}
    [IO.Directory]::CreateDirectory((Split-Path -Parent $target))|Out-Null
    $stamp=$(if($null -ne $Now){([datetime]$Now).ToUniversalTime()}else{[datetime]::UtcNow}).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $mutex=New-Object Threading.Mutex($false,(Get-UsageLockName $target))
    $owned=$false;$utf8=New-Object Text.UTF8Encoding($false)
    try{
        try{$owned=$mutex.WaitOne(5000)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){return @{Code=1;Status='BUSY';Path=$target;Issues=@('No se pudo adquirir bloqueo de uso.')}}
        $rows=New-Object Collections.ArrayList
        if([IO.File]::Exists($target)){
            foreach($raw in [IO.File]::ReadAllLines($target,[Text.Encoding]::UTF8)){
                if(-not $raw.Trim()){continue}
                try{[void]$rows.Add(($raw|ConvertFrom-Json))}catch{}
            }
        }
        $updated=$false
        if($SessionId){
            for($i=0;$i -lt $rows.Count;$i++){
                $r=$rows[$i]
                if($r.PSObject.Properties['session_id'] -and [string]$r.session_id -eq $SessionId -and [string]$r.skill -eq $Skill){
                    if((Get-OutcomeRank $outKey) -ge (Get-OutcomeRank ([string]$r.outcome))){
                        $r.outcome=$outKey;$r.timestamp=$stamp;$r.source=$Source
                    }
                    $updated=$true;break
                }
            }
        }
        if($updated){
            $lines=@($rows|ForEach-Object {$_|ConvertTo-Json -Compress})
            [IO.File]::WriteAllText($target,(($lines -join "`n")+"`n"),$utf8)
            return @{Code=0;Status='UPDATED';Path=$target;Skill=$Skill;Outcome=$outKey;Issues=@()}
        }
        $entry=[ordered]@{timestamp=$stamp;skill=$Skill;project=$Project;session_id=$SessionId;harness=$Harness;source=$Source;outcome=$outKey}
        [IO.File]::AppendAllText($target,(($entry|ConvertTo-Json -Compress)+"`n"),$utf8)
        return @{Code=0;Status='RECORDED';Path=$target;Skill=$Skill;Outcome=$outKey;Issues=@()}
    }finally{
        if($owned){$mutex.ReleaseMutex()};$mutex.Dispose()
    }
}
function Sync-SkillUsageFromTranscripts {
    param([string]$HubPath='',[string]$FrameworkPath='',[string]$ProjectPath='',[string]$UsagePath='',
          [Nullable[datetime]]$Since=$null,
          [string]$ClaudeProjectsRoot=(Join-Path $env:USERPROFILE '.claude/projects'),
          [string]$CodexSessionsRoot=(Join-Path $env:USERPROFILE '.codex/sessions'),
          [string]$AntigravityBrainRoot=(Join-Path $env:USERPROFILE '.gemini/antigravity/brain'))
    $known=New-Object 'Collections.Generic.HashSet[string]'
    if($HubPath){foreach($s in (Get-LearningHubSkills $HubPath)){[void]$known.Add($s)}}
    if($FrameworkPath -and [IO.Directory]::Exists((Join-Path $FrameworkPath 'skills'))){
        foreach($s in (Get-LearningHubSkills (Join-Path $FrameworkPath 'skills'))){[void]$known.Add($s)}
    }
    foreach($c in $script:CoreSkills){[void]$known.Add($c)}
    $projName=if($ProjectPath){Split-Path -Leaf ([IO.Path]::GetFullPath($ProjectPath).TrimEnd('\','/'))}else{'(sin proyecto)'}
    $projNorm=if($ProjectPath){[IO.Path]::GetFullPath($ProjectPath).TrimEnd('\','/')}else{''}
    $share=[IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
    $readLines={param($p) $sr=New-Object IO.StreamReader((New-Object IO.FileStream($p,[IO.FileMode]::Open,[IO.FileAccess]::Read,$share)),[Text.Encoding]::UTF8);try{while($null -ne ($l=$sr.ReadLine())){$l}}finally{$sr.Dispose()}}
    $recorded=0;$seen=@{}
    $record={param($skill,$sid,$harness,$ts)
        if(-not $known.Contains($skill)){return}
        $k="$sid|$skill";if($seen.ContainsKey($k)){return};$seen[$k]=$true
        $dt=$null;try{if($ts){$dt=[datetime]::Parse([string]$ts,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)}}catch{}
        $r=Register-SkillUsage -Skill $skill -Project $projName -Outcome 'used' -SessionId $sid -Harness $harness -Source 'transcript' -HubPath $HubPath -UsagePath $UsagePath -Now $dt
        if($r.Code -eq 0 -and $r.Status -eq 'RECORDED'){$script:tmpRec++}
    }
    $script:tmpRec=0
    if([IO.Directory]::Exists($ClaudeProjectsRoot)){
        foreach($f in @(Get-ChildItem -LiteralPath $ClaudeProjectsRoot -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)){
            if($null -ne $Since -and $f.LastWriteTimeUtc -lt ([datetime]$Since).ToUniversalTime()){continue}
            foreach($line in (& $readLines $f.FullName)){
                if($line -notmatch '"Skill"|SKILL\.md'){continue}
                try{$o=$line|ConvertFrom-Json}catch{continue}
                if($projNorm -and $o.PSObject.Properties['cwd'] -and $o.cwd -and ([IO.Path]::GetFullPath([string]$o.cwd).TrimEnd('\','/') -ne $projNorm)){continue}
                $sid=if($o.PSObject.Properties['sessionId']){[string]$o.sessionId}else{$f.BaseName}
                $ts=if($o.PSObject.Properties['timestamp']){$o.timestamp}else{$null}
                foreach($m in [regex]::Matches($line,'"skill"\s*:\s*"([a-z0-9-]+)"')){& $record $m.Groups[1].Value $sid 'claude' $ts}
                foreach($m in [regex]::Matches($line,'([a-z0-9-]+)[/\\]+SKILL\.md')){& $record $m.Groups[1].Value $sid 'claude' $ts}
            }
        }
    }
    if([IO.Directory]::Exists($CodexSessionsRoot)){
        foreach($f in @(Get-ChildItem -LiteralPath $CodexSessionsRoot -Recurse -Filter '*.jsonl' -File -ErrorAction SilentlyContinue)){
            if($null -ne $Since -and $f.LastWriteTimeUtc -lt ([datetime]$Since).ToUniversalTime()){continue}
            $sid=$f.BaseName
            foreach($line in (& $readLines $f.FullName)){
                if($line -notmatch 'SKILL\.md'){continue}
                foreach($m in [regex]::Matches($line,'([a-z0-9-]+)[/\\]+SKILL\.md')){& $record $m.Groups[1].Value $sid 'codex' $null}
            }
        }
    }
    if([IO.Directory]::Exists($AntigravityBrainRoot)){
        foreach($d in @(Get-ChildItem -LiteralPath $AntigravityBrainRoot -Directory -ErrorAction SilentlyContinue)){
            $tf=Join-Path $d.FullName '.system_generated/logs/transcript.jsonl'
            if(-not [IO.File]::Exists($tf)){continue}
            if($null -ne $Since -and (Get-Item -LiteralPath $tf).LastWriteTimeUtc -lt ([datetime]$Since).ToUniversalTime()){continue}
            $sid=$d.Name
            foreach($line in (& $readLines $tf)){
                if($line -notmatch 'SKILL\.md'){continue}
                try{$o=$line|ConvertFrom-Json}catch{continue}
                $ts=if($o.PSObject.Properties['created_at']){$o.created_at}else{$null}
                foreach($m in [regex]::Matches($line,'([a-z0-9-]+)[/\\]+SKILL\.md')){& $record $m.Groups[1].Value $sid 'antigravity' $ts}
            }
        }
    }
    $recorded=$script:tmpRec
    return @{Code=0;Status='SYNCED';Recorded=$recorded;Sessions=$seen.Count;Issues=@()}
}

function Read-SkillFrontmatter([string]$SkillMdPath){
    $raw=[IO.File]::ReadAllText($SkillMdPath,[Text.Encoding]::UTF8)
    $allLines=@($raw -split "\r?\n")
    $res=[ordered]@{Valid=$false;Name='';Version='';Description='';AlwaysKeep=$false;Triggers=@();BodyLines=0;Error=''}
    if($raw -notmatch ('(?s)^'+[char]0xFEFF+'?---\r?\n(.*?)\r?\n---(?:\r?\n(.*))?$')){
        $res.Error='Frontmatter YAML ausente o sin cierre ---.';return [pscustomobject]$res
    }
    $fmLines=@($Matches[1] -split "\r?\n")
    $body=if($Matches.Count -ge 3 -and $null -ne $Matches[2]){$Matches[2]}else{''}
    $res.BodyLines=if($body){@($body -split "\r?\n").Count}else{0}
    $triggers=New-Object Collections.Generic.List[string]
    for($i=0;$i -lt $fmLines.Count;$i++){
        $line=$fmLines[$i]
        if($line -match '^([A-Za-z0-9_-]+):\s*([>|][+-]?)\s*$'){
            $k=$Matches[1].ToLowerInvariant();$buf=New-Object Collections.Generic.List[string]
            $j=$i+1
            while($j -lt $fmLines.Count -and ($fmLines[$j] -match '^\s+(.*)$' -or $fmLines[$j].Trim() -eq '')){
                if($fmLines[$j] -match '^\s+(.*)$'){$buf.Add($Matches[1].Trim())}
                $j++
            }
            if(-not $buf.Count){$res.Error="Escalar de bloque '$k' vacío.";return [pscustomobject]$res}
            $val=($buf -join ' ').Trim()
            if($k -eq 'description'){$res.Description=$val}
            $i=$j-1;continue
        }
        if($line -match '^triggers:\s*$'){
            $j=$i+1
            while($j -lt $fmLines.Count -and $fmLines[$j] -match '^\s*-\s*(.+)$'){
                $t=$Matches[1].Trim().Trim('"','''')
                if($t){$triggers.Add($t)}
                $j++
            }
            $i=$j-1;continue
        }
        if($line -match '^([A-Za-z0-9_-]+):\s*(.*)$'){
            $k=$Matches[1].ToLowerInvariant();$v=$Matches[2].Trim().Trim('"','''')
            switch($k){
                'name'{$res.Name=$v}
                'version'{$res.Version=$v}
                'description'{$res.Description=$v}
                'always_keep'{if($v -match '^(?i:true|yes|1)$'){$res.AlwaysKeep=$true}}
            }
        }
    }
    $res.Triggers=@($triggers)
    $res.Valid=([string]::IsNullOrWhiteSpace($res.Error))
    return [pscustomobject]$res
}

function Get-SkillSemanticTokens([string]$Text){
    if([string]::IsNullOrWhiteSpace($Text)){return @()}
    $stop=@('de','la','el','los','las','un','una','unos','unas','y','o','en','con','para','por','al','del','se','su','sus','que','como','cuando','si','no','mas','solo','usar','uso','skill','skills','agente','usuario','archivo','archivos','proyecto','proyectos','the','and','or','for','with','when','use','to','in','of','on','a','an','is','are','this','that','from','by')
    $norm=ConvertTo-LearningKey $Text
    $words=@([regex]::Split($norm,'[^a-z0-9]+')|Where-Object {$_.Length -ge 3 -and $stop -notcontains $_})
    $tokens=New-Object 'Collections.Generic.HashSet[string]'
    foreach($w in $words){
        $s=$w
        if($s.Length -gt 5 -and $s -match '(aciones|iciones|amientos)$'){$s=$s.Substring(0,$s.Length-4)}
        elseif($s.Length -gt 4 -and $s -match '(es|ar|er|ir|ed)$'){$s=$s.Substring(0,$s.Length-2)}
        elseif($s.Length -gt 4 -and $s.EndsWith('s')){$s=$s.Substring(0,$s.Length-1)}
        [void]$tokens.Add($s)
    }
    return @($tokens)
}

function Get-SkillPruningCandidates {
    param([Parameter(Mandatory=$true)][string]$HubPath,[string]$FrameworkPath='',[string]$UsagePath='',
          [int]$InactiveDays=90,[int]$HurtThreshold=2,[Nullable[datetime]]$Now=$null,
          [switch]$EmitProposals,[switch]$ExcludePending)
    if(-not [IO.Directory]::Exists($HubPath)){return @{Code=1;Status='FAILED';Issues=@("Hub no encontrado: $HubPath");Candidates=@();EmittedProposals=@()}}
    $nowUtc=if($null -ne $Now){([datetime]$Now).ToUniversalTime()}else{[datetime]::UtcNow}
    $hist=@(Get-SkillUsageHistory -HubPath $HubPath -UsagePath $UsagePath)
    $earliest=$null;$bySkill=@{}
    foreach($h in $hist){
        $dt=$null;try{$dt=[datetime]::Parse([string]$h.timestamp,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()}catch{}
        if($null -ne $dt -and ($null -eq $earliest -or $dt -lt $earliest)){$earliest=$dt}
        $sn=[string]$h.skill
        if(-not $bySkill.ContainsKey($sn)){$bySkill[$sn]=@{LastUsed=$null;FirstUsed=$null;Count=0;HurtCount=0}}
        $bySkill[$sn].Count++
        if($null -ne $dt){
            if($null -eq $bySkill[$sn].LastUsed -or $dt -gt $bySkill[$sn].LastUsed){$bySkill[$sn].LastUsed=$dt}
            if($null -eq $bySkill[$sn].FirstUsed -or $dt -lt $bySkill[$sn].FirstUsed){$bySkill[$sn].FirstUsed=$dt}
        }
        if(([string]$h.outcome) -in @('hurt','error')){$bySkill[$sn].HurtCount++}
    }
    $historyDays=if($null -ne $earliest){[Math]::Max(0,[Math]::Floor(($nowUtc-$earliest).TotalDays))}else{0}
    $matureHistory=($historyDays -ge $InactiveDays)
    $candidates=@();$emitted=@()
    $pendingDir=Join-Path $HubPath 'proposals/pending';$rejectedDir=Join-Path $HubPath 'proposals/rejected'
    foreach($skill in (Get-LearningHubSkills $HubPath | Sort-Object)){
        $dir=Join-Path $HubPath $skill;$smPath=Join-Path $dir 'SKILL.md'
        $fm=Read-SkillFrontmatter $smPath
        $item=Get-Item -LiteralPath $smPath
        $stats=if($bySkill.ContainsKey($skill)){$bySkill[$skill]}else{@{LastUsed=$null;FirstUsed=$null;Count=0;HurtCount=0}}
        $originTicks=[Math]::Min($item.CreationTimeUtc.Ticks,$item.LastWriteTimeUtc.Ticks)
        if($null -ne $stats.FirstUsed){$originTicks=[Math]::Min($originTicks,$stats.FirstUsed.Ticks)}
        $originUtc=New-Object datetime $originTicks,([DateTimeKind]::Utc)
        $ageDays=[Math]::Max(0,[Math]::Floor(($nowUtc-$originUtc).TotalDays))
        $daysIdle=if($null -ne $stats.LastUsed){[Math]::Max(0,[Math]::Floor(($nowUtc-$stats.LastUsed).TotalDays))}else{$ageDays}
        $status='ACTIVE';$reason=''
        if(($script:CoreSkills -contains $skill) -or $fm.AlwaysKeep){
            $status='PROTECTED';$reason='Core o always_keep'
        }elseif($stats.HurtCount -ge $HurtThreshold){
            $status='REVIEW_HURT';$reason="$($stats.HurtCount) sesiones con resultado hurt/error"
        }elseif(-not $matureHistory -or $ageDays -lt $InactiveDays){
            $status='INSUFFICIENT_HISTORY';$reason="Historial de $historyDays dias / skill de $ageDays dias (< $InactiveDays)"
        }elseif($daysIdle -ge $InactiveDays){
            $status='PRUNE_INACTIVE';$reason="$daysIdle dias sin uso (>= $InactiveDays)"
        }
        $candidates+=[pscustomobject]@{Skill=$skill;Status=$status;Reason=$reason;DaysIdle=$daysIdle;AgeDays=$ageDays;Uses=$stats.Count;HurtCount=$stats.HurtCount;Version=$fm.Version}
        if($EmitProposals -and $status -in @('PRUNE_INACTIVE','REVIEW_HURT')){
            $already=$false
            foreach($d in @($pendingDir,$rejectedDir)){
                if([IO.Directory]::Exists($d) -and @(Get-ChildItem -LiteralPath $d -Filter "prune-$skill*.md" -ErrorAction SilentlyContinue).Count){$already=$true}
            }
            if(-not $already){
                [IO.Directory]::CreateDirectory($pendingDir)|Out-Null
                $ver=if($fm.Version){$fm.Version}else{'1.0.0'}
                $propFile=Join-Path $pendingDir ("prune-$skill-"+$nowUtc.ToString('yyyyMMdd')+'.md')
                $propText=@(
                    "# Propuesta prune-$skill",'',
                    '- Destino: 6',"- Skill: $skill","- Version: $ver -> archived",'- Riesgo: bajo','- Tamano: +0 -1','',
                    '## Por que',"Poda automatica ($status): $reason.",'',
                    '## Evidencia',"- Ventana historial: $historyDays dias; dias sin uso: $daysIdle; reportes hurt/error: $($stats.HurtCount).",'',
                    '## Cambio','### Bloque 1',"Mover $skill a proposals/archived/$skill sin borrar archivos.",'',
                    '## Solapamientos','Ninguno.','','## Alternativas descartadas','Mantener activa: genera ruido en la seleccion.'
                ) -join "`n"
                [IO.File]::WriteAllText($propFile,$propText,[Text.UTF8Encoding]::new($false))
                if((Test-LearningProposal -Path $propFile -HubPath $HubPath).Code -eq 0){$emitted+=@($propFile)}
            }
        }
    }
    $overall=if(-not $matureHistory){'INSUFFICIENT_HISTORY'}else{'OK'}
    return @{Code=0;Status=$overall;HistoryDays=$historyDays;Candidates=$candidates;EmittedProposals=$emitted;Issues=@()}
}

function Test-SkillCatalog {
    param([string]$HubPath='',[string]$FrameworkPath='',
          [int]$DescriptionLimit=$script:DescriptionLimit,[int]$OfficialLimit=$script:OfficialDescriptionLimit,
          [int]$MaxBodyLines=$script:MaxBodyLines,[int]$ListingBudget=$script:DefaultListingBudget,
          [double]$JaccardThreshold=0.45,[double]$ContainmentThreshold=0.70,[switch]$Strict)
    $errors=New-Object Collections.ArrayList
    $warnings=New-Object Collections.ArrayList
    $overlaps=New-Object Collections.ArrayList
    $skills=New-Object Collections.ArrayList
    $seenNames=@{};$counts=@{Hub=0;Chars=0}
    $addSkill={param($name,$path,$origin)
        if($origin -eq 'framework' -and $seenNames.ContainsKey($name) -and ($script:CoreSkills -contains $name)){return}
        $fm=Read-SkillFrontmatter $path
        if(-not $fm.Valid){[void]$errors.Add([pscustomobject]@{Skill=$name;Origin=$origin;Message="YAML invalido en ${path}: $($fm.Error)";Fix='Corrige el frontmatter YAML (escalares vacios o cierre ---).'});return}
        if($seenNames.ContainsKey($name)){[void]$errors.Add([pscustomobject]@{Skill=$name;Origin=$origin;Message="Nombre duplicado '$name' en $origin y $($seenNames[$name]).";Fix='Fusiona o renombra la skill del hub.'});return}
        $seenNames[$name]=$origin
        if($origin -eq 'hub' -and ($script:CoreSkills -notcontains $name)){$counts.Hub++}
        $descLen=$fm.Description.Length
        $counts.Chars+=($name.Length+$descLen)
        if($descLen -gt $OfficialLimit){
            [void]$errors.Add([pscustomobject]@{Skill=$name;Origin=$origin;Message="Descripcion de $descLen caracteres supera limite oficial de $OfficialLimit.";Fix="Reduce description bajo $DescriptionLimit caracteres y mueve el detalle a references/."})
        }elseif($descLen -gt $DescriptionLimit){
            [void]$warnings.Add([pscustomobject]@{Skill=$name;Origin=$origin;Message="Descripcion de $descLen caracteres supera recomendacion de $DescriptionLimit.";Fix="Acorta description dejando los disparadores primero."})
        }
        if($fm.BodyLines -gt $MaxBodyLines){
            [void]$warnings.Add([pscustomobject]@{Skill=$name;Origin=$origin;Message="Cuerpo de $($fm.BodyLines) lineas supera tope recomendado de $MaxBodyLines.";Fix='Extrae secciones extensas a references/.'})
        }
        $tokText=($name -replace '-',' ')+' '+$fm.Description+' '+($fm.Triggers -join ' ')
        [void]$skills.Add([pscustomobject]@{Name=$name;Origin=$origin;DescriptionLength=$descLen;BodyLines=$fm.BodyLines;Tokens=(Get-SkillSemanticTokens $tokText)})
    }
    if($HubPath -and [IO.Directory]::Exists($HubPath)){
        foreach($s in (Get-LearningHubSkills $HubPath | Sort-Object)){& $addSkill $s (Join-Path $HubPath "$s/SKILL.md") 'hub'}
    }
    if($FrameworkPath){
        $fwSkills=if([IO.Directory]::Exists((Join-Path $FrameworkPath 'skills'))){Join-Path $FrameworkPath 'skills'}else{$FrameworkPath}
        if([IO.Directory]::Exists($fwSkills)){
            foreach($s in (Get-LearningHubSkills $fwSkills | Sort-Object)){& $addSkill $s (Join-Path $fwSkills "$s/SKILL.md") 'framework'}
        }
    }
    if($counts.Hub -gt $script:SkillCeiling){
        [void]$errors.Add([pscustomobject]@{Skill='(catalog)';Origin='hub';Message="Catalogo del hub tiene $($counts.Hub) skills activas (techo: $($script:SkillCeiling)).";Fix='Archiva o fusiona skills antes de crear nuevas.'})
    }
    if($counts.Chars -gt $ListingBudget){
        [void]$warnings.Add([pscustomobject]@{Skill='(catalog)';Origin='all';Message="Presupuesto total del listado ($($counts.Chars) caracteres) supera $ListingBudget.";Fix='Acorta las descripciones mas largas o archiva skills inactivas.'})
    }
    for($i=0;$i -lt $skills.Count;$i++){
        for($j=$i+1;$j -lt $skills.Count;$j++){
            $a=$skills[$i];$b=$skills[$j]
            if(-not $a.Tokens.Count -or -not $b.Tokens.Count){continue}
            $inter=@($a.Tokens|Where-Object {$b.Tokens -contains $_}).Count
            if(-not $inter){continue}
            $union=$a.Tokens.Count+$b.Tokens.Count-$inter
            $minLen=[Math]::Min($a.Tokens.Count,$b.Tokens.Count)
            $jacc=[Math]::Round(($inter/[double]$union),3)
            $cont=[Math]::Round(($inter/[double]$minLen),3)
            if($jacc -ge $JaccardThreshold -or $cont -ge $ContainmentThreshold){
                $ov=[pscustomobject]@{SkillA=$a.Name;SkillB=$b.Name;Jaccard=$jacc;Containment=$cont;Fix="Diferencia los disparadores de '$($a.Name)' y '$($b.Name)' o evalua fusionarlas."}
                [void]$overlaps.Add($ov);[void]$warnings.Add([pscustomobject]@{Skill="$($a.Name) <-> $($b.Name)";Origin='overlap';Message="Solapamiento detectado (Jaccard=$jacc, Contencion=$cont).";Fix=$ov.Fix})
            }
        }
    }
    $code=if($Strict -and $errors.Count){2}else{0}
    $status=if($code -ne 0){'ERRORS'}elseif($warnings.Count){'WARNINGS'}else{'CLEAN'}
    return @{Code=$code;Status=$status;Summary=@{HubSkills=$counts.Hub;TotalSkills=$skills.Count;TotalDescriptionChars=$counts.Chars;Errors=$errors.Count;Warnings=$warnings.Count;Overlaps=$overlaps.Count};Errors=$errors.ToArray();Warnings=$warnings.ToArray();Overlaps=$overlaps.ToArray();Skills=$skills.ToArray()}
}

Export-ModuleMember -Function New-LearningCandidate,Test-LearningProposal,Get-LearningQueue,Invoke-LearningTriage,Invoke-LearningProposalApply,Register-SkillUsage,Get-SkillUsageHistory,Sync-SkillUsageFromTranscripts,Get-SkillPruningCandidates,Test-SkillCatalog
