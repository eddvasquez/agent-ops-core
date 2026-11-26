# Governed learning: candidates are captured in the hub inbox and proposals are validated
# before a human decides. Nothing here modifies a skill.
Set-StrictMode -Version 2
$script:Signals=@('correccion','fallo','patron','exito')
$script:Risks=@('bajo','medio','alto')
$script:SkillCeiling=25
$script:DescriptionLimit=300

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
    if($dest -match '^[345]$'){$proposal.Destination=[int]$dest}
    elseif($dest -match '^[12]$'){$issues.Add("Destino $dest no es una propuesta de skill: va a 'nada' o a reglas_proyecto.md.")}
    else{$issues.Add("Destino no válido '$dest'; usar 3 (parche), 4 (referencia) o 5 (skill nueva).")}

    if(-not (Test-LearningSkillName $proposal.Skill)){$issues.Add("Skill no válida '$($proposal.Skill)'.")}
    if($script:Risks -notcontains $proposal.Risk){$issues.Add("Riesgo no válido; usar: $($script:Risks -join ', ').")}

    $ver=& $get 'version'
    if($ver -match '^(nueva|\d+\.\d+\.\d+)\s*->\s*(\d+\.\d+\.\d+)$'){
        $proposal.From=$Matches[1];$proposal.To=$Matches[2]
        if($proposal.Destination -eq 5 -and $proposal.From -ne 'nueva'){$issues.Add("Versión: una skill nueva se declara 'nueva -> X.Y.Z'.")}
        if($proposal.Destination -in 3,4){
            if($proposal.From -eq 'nueva'){$issues.Add('Versión: un parche o referencia parte de la versión actual de la skill.')}
            elseif([version]$proposal.To -le [version]$proposal.From){$issues.Add("Versión: $($proposal.To) no es mayor que $($proposal.From).")}
        }
    }else{$issues.Add("Versión no válida '$ver'; formato 'X.Y.Z -> X.Y.Z' o 'nueva -> X.Y.Z'.")}

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
    if($proposal.Destination -in 3,4 -and $null -ne $hubSkills -and $hubSkills -notcontains $proposal.Skill){
        $issues.Add("SKILL_NOT_IN_HUB: '$($proposal.Skill)' no es una skill del hub; las de terceros no reciben parches.")
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
    if(-not $ApprovedBlocks.Count){return @{Code=2;Status='NO_BLOCKS_APPROVED';Issues=@('Especifica -ApprovedBlocks o -Reject.')}}
    $skill=$v.Proposal.Skill
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
    return @{Code=0;Status='APPLIED';Skill=$skill;Version=$v.Proposal.To;AppliedBlocks=$ApprovedBlocks.Count;Path=$appPath;Issues=@()}
}

Export-ModuleMember -Function New-LearningCandidate,Test-LearningProposal,Get-LearningQueue,Invoke-LearningTriage,Invoke-LearningProposalApply
