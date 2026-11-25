Set-StrictMode -Version 2
# Acceptance review (R-016, R-017). A contract fixes, before the work, the user's literal request, verifiable criteria,
# what must not change (invariants, optionally with a pattern) and a closed scope. Before delivery a reviewer in a
# clean context judges every item with a citation: clean means without the drafting history, never without the
# project, so the sheet always carries the active rules, the declared sources and the contract. The reviewer only
# judges and suggests; invariants with a pattern are checked by script. At most three rounds.
Import-Module (Join-Path $PSScriptRoot 'RulesCheck.psm1')
$script:dir='.context/aceptacion'
$script:scope='No cambiar la oferta ni crear variantes; señalar riesgos como observación. El revisor juzga y sugiere; nunca reescribe el entregable.'
$script:maxRounds=3
$script:utf8=New-Object Text.UTF8Encoding($false)

function Ac-Sha([byte[]]$b){$h=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($h.ComputeHash($b))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}}
function Ac-Root([string]$p){[IO.Path]::GetFullPath($p).TrimEnd('\','/')}
function Ac-Path([string]$root,[string]$id){Join-Path $root "$script:dir/$id.md"}
function Ac-Sheet([string]$root,[string]$id){Join-Path $root "$script:dir/$id.review.md"}
function Ac-Rel([string]$root,[string]$path){$f=[IO.Path]::GetFullPath($(if([IO.Path]::IsPathRooted($path)){$path}else{Join-Path $root $path}));if($f.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){$f.Substring($root.Length+1).Replace('\','/')}else{$f}}
function Ac-Full([string]$root,[string]$rel){if([IO.Path]::IsPathRooted($rel)){$rel}else{Join-Path $root $rel}}

function Ac-Read([string]$path){
    $t=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
    $c=[ordered]@{State='abierto';Round=0;Request='';Criteria=@();Invariants=@();Sources=@();Text=$t}
    if($t -match '(?m)^Estado:\s*(\S+)'){$c.State=$Matches[1]}
    if($t -match '(?m)^Ronda:\s*(\d+)'){$c.Round=[int]$Matches[1]}
    $section=''
    foreach($line in ($t -split '\r?\n')){
        if($line -match '^##\s+(.+)$'){$section=$Matches[1].Trim();continue}
        switch($section){
            'Petición literal'{if($line -match '^>\s?(.*)$'){$c.Request+=$(if($c.Request){"`n"}else{''})+$Matches[1]}}
            'Criterios'{if($line -match '^- (C\d+): (.+)$'){$c.Criteria+=[pscustomobject]@{Id=$Matches[1];Text=$Matches[2]}}}
            'No se toca'{if($line -match '^- (I\d+): (.+)$'){$id=$Matches[1];$parts=$Matches[2] -split '\s\|\s',2;$c.Invariants+=[pscustomobject]@{Id=$id;Text=$parts[0].Trim();Pattern=$(if($parts.Count -gt 1){$parts[1].Trim()}else{''})}}}
            'Fuentes del proyecto'{if($line -match '^- (.+)$'){$c.Sources+=$Matches[1].Trim()}}
        }
    }
    return [pscustomobject]$c
}
function Ac-SetHeader([string]$path,[string]$key,[string]$value){
    $t=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)
    $t=[regex]::Replace($t,'(?m)^'+[regex]::Escape($key)+':\s*.*$',"${key}: $value")
    [IO.File]::WriteAllText($path,$t,$script:utf8)
}
# Binds a verdict to the exact contract (request, criteria, invariants), rules and deliverables it judged.
function Ac-Fingerprint([string]$root,$contract,[string[]]$deliverables){
    $parts=@('request|'+$contract.Request)
    foreach($x in $contract.Criteria){$parts+="$($x.Id)|$($x.Text)"}
    foreach($x in $contract.Invariants){$parts+="$($x.Id)|$($x.Text)|$($x.Pattern)"}
    $rules=Join-Path $root '.context/reglas_proyecto.md'
    if([IO.File]::Exists($rules)){$parts+='rules|'+(Ac-Sha ([IO.File]::ReadAllBytes($rules)))}
    foreach($d in @($deliverables|Sort-Object)){$f=Ac-Full $root $d;$parts+=($d.ToLowerInvariant()+'|'+$(if([IO.File]::Exists($f)){Ac-Sha ([IO.File]::ReadAllBytes($f))}else{'missing'}))}
    return (Ac-Sha ([Text.Encoding]::UTF8.GetBytes(($parts -join "`n"))))
}

function New-AgentOpsAcceptance {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$Request,
          [Parameter(Mandatory=$true)][string[]]$Criteria,[string[]]$Invariants=@(),[string[]]$Sources=@())
    $root=Ac-Root $ProjectPath
    $id=[datetime]::Now.ToString('yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,4)
    $b=New-Object Collections.Generic.List[string]
    $b.Add("# Contrato de aceptación $id");$b.Add('');$b.Add('Estado: abierto');$b.Add('Ronda: 0');$b.Add('')
    $b.Add('## Petición literal');foreach($l in ($Request -split '\r?\n')){$b.Add('> '+$l)};$b.Add('')
    $b.Add('## Criterios');$n=0;foreach($x in $Criteria){$n++;$b.Add("- C${n}: $x")};$b.Add('')
    $b.Add('## No se toca');$n=0;foreach($x in $Invariants){$n++;$b.Add("- I${n}: $x")};$b.Add('')
    $b.Add('## Fuentes del proyecto');foreach($x in $Sources){$b.Add("- $x")};$b.Add('')
    $b.Add('## Alcance');$b.Add($script:scope)
    $path=Ac-Path $root $id;[IO.Directory]::CreateDirectory((Split-Path $path))|Out-Null
    [IO.File]::WriteAllText($path,(($b -join "`n")+"`n"),$script:utf8)
    return [pscustomobject]@{Code=0;Status='OPEN';Id=$id;Path=$path}
}

function New-AgentOpsAcceptanceReview {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$Id,[Parameter(Mandatory=$true)][string[]]$Deliverable)
    $root=Ac-Root $ProjectPath;$path=Ac-Path $root $Id
    if(-not [IO.File]::Exists($path)){return [pscustomobject]@{Code=2;Status='NO_CONTRACT';Id=$Id;Round=0;Sheet=$null;Automatic=@()}}
    $c=Ac-Read $path
    if($c.Round -ge $script:maxRounds){return [pscustomobject]@{Code=2;Status='ROUND_LIMIT';Id=$Id;Round=$c.Round;Sheet=(Ac-Sheet $root $Id);Automatic=@()}}
    $round=$c.Round+1;Ac-SetHeader $path 'Ronda' ([string]$round)
    $rel=@($Deliverable|ForEach-Object {Ac-Rel $root $_})
    $text=(@($rel|ForEach-Object {$f=Ac-Full $root $_;if([IO.File]::Exists($f)){[IO.File]::ReadAllText($f,[Text.Encoding]::UTF8)}})) -join "`n"
    $b=New-Object Collections.Generic.List[string]
    $b.Add("# Revisión de aceptación $Id");$b.Add('')
    $b.Add('Huella: '+(Ac-Fingerprint $root $c $rel));$b.Add("Ronda: $round");$b.Add('')
    $b.Add('Entregables:');foreach($d in $rel){$b.Add("- $d")};$b.Add('')
    $b.Add('Instrucciones: revisa en un contexto limpio (sin el historial de redacción), pero con todo lo de abajo: la petición literal, las reglas del proyecto, sus fuentes y el contrato. Tu papel es de juez: no reescribas el entregable, no generes versiones nuevas ni propongas otra oferta. Por cada punto sustituye PENDIENTE por PASA o FALLA, seguido de " - " y una cita literal del entregable. Lo marcado «automático» lo comprobó un script y no se cambia. Si crees que la oferta o la estrategia deberían cambiar, escríbelo en Observaciones para el usuario; no lo apliques. Alcance: '+$script:scope);$b.Add('')
    $b.Add('## Petición literal');foreach($l in ($c.Request -split '\n')){$b.Add('> '+$l)};$b.Add('')
    $b.Add('## Reglas activas del proyecto (literales)')
    $rules=Join-Path $root '.context/reglas_proyecto.md'
    if([IO.File]::Exists($rules)){foreach($r in @(& (Get-Module RulesCheck) {param($p) (Read-AgentOpsRules $p).Rules} $rules|Where-Object {$_.State -eq 'activa'})){$b.Add("- $($r.Id): «$($r.Text)»")}}
    $b.Add('')
    $b.Add('## Fuentes del proyecto')
    foreach($src in $c.Sources){$f=Ac-Full $root $src;$b.Add("### $src");if([IO.File]::Exists($f)){$s=[IO.File]::ReadAllText($f,[Text.Encoding]::UTF8);if($s.Length -gt 4000){$s=$s.Substring(0,4000)+"`n… (recortado)"};$b.Add($s)}else{$b.Add('(no encontrada)')};$b.Add('')}
    $b.Add('## Criterios')
    foreach($x in $c.Criteria){$b.Add("### $($x.Id): $($x.Text)");$b.Add("- $($x.Id): PENDIENTE")}
    $b.Add('');$b.Add('## No se toca')
    $auto=@()
    foreach($x in $c.Invariants){
        $b.Add("### $($x.Id): $($x.Text)"+$(if($x.Pattern){" (patrón: $($x.Pattern))"}else{''}))
        if($x.Pattern -and $text -notmatch $x.Pattern){$auto+=$x.Id;$b.Add("- $($x.Id): FALLA - automático: el entregable ya no contiene «$($x.Text)»")}
        else{$b.Add("- $($x.Id): PENDIENTE")}
    }
    $b.Add('');$b.Add('## Observaciones para el usuario');$b.Add('(opcional: riesgos o cambios de estrategia que el revisor recomiende; nunca se aplican sin el usuario)')
    $sheet=Ac-Sheet $root $Id;[IO.File]::WriteAllText($sheet,(($b -join "`n")+"`n"),$script:utf8)
    return [pscustomobject]@{Code=0;Status='REVIEW_READY';Id=$Id;Round=$round;Sheet=$sheet;Automatic=$auto}
}

function Test-AgentOpsAcceptance {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$Id)
    $root=Ac-Root $ProjectPath;$path=Ac-Path $root $Id;$sheet=Ac-Sheet $root $Id
    $res=[ordered]@{Code=2;Status='NO_REVIEW';Id=$Id;Round=0;Failed=@();Issues=@()}
    if(-not [IO.File]::Exists($path)){$res.Status='NO_CONTRACT';return [pscustomobject]$res}
    $c=Ac-Read $path;$res.Round=$c.Round
    if(-not [IO.File]::Exists($sheet)){return [pscustomobject]$res}
    $lines=[IO.File]::ReadAllLines($sheet,[Text.Encoding]::UTF8)
    $rel=@();$in=$false
    foreach($l in $lines){if($l -eq 'Entregables:'){$in=$true;continue};if($in){if($l -match '^- (.+)$'){$rel+=$Matches[1]}else{break}}}
    $huella=@($lines|Where-Object {$_ -match '^Huella:\s*([0-9a-f]{64})\s*$'}|ForEach-Object {$Matches[1]})
    if($huella.Count -ne 1 -or $huella[0] -ne (Ac-Fingerprint $root $c $rel)){$res.Status='STALE';$res.Issues=@('El entregable, el contrato o las reglas cambiaron después de la revisión: revisa de nuevo.');return [pscustomobject]$res}
    $pending=@();$uncited=@();$failed=@()
    foreach($x in @($c.Criteria)+@($c.Invariants)){
        $line=@($lines|Where-Object {$_ -match ('^- '+[regex]::Escape($x.Id)+':\s*(PASA|FALLA|PENDIENTE)\b(.*)$')}|Select-Object -First 1)
        if(-not $line.Count){$pending+=$x.Id;continue}
        [void]($line[0] -match ('^- '+[regex]::Escape($x.Id)+':\s*(PASA|FALLA|PENDIENTE)\b(.*)$'));$v=$Matches[1];$note=$Matches[2].Trim()
        if($v -eq 'PENDIENTE'){$pending+=$x.Id}
        elseif($v -eq 'FALLA'){$failed+=$x.Id}
        elseif($note -notmatch '^-\s*\S'){$uncited+=$x.Id}
    }
    if($pending.Count){$res.Status='PENDING';$res.Issues=@("Sin veredicto: $($pending -join ', ').");return [pscustomobject]$res}
    if($uncited.Count){$res.Status='INVALID';$res.Issues=@("PASA sin cita del entregable: $($uncited -join ', ').");return [pscustomobject]$res}
    $res.Failed=$failed
    if($failed.Count){
        if($c.Round -ge $script:maxRounds){$res.Code=1;$res.Status='DELIVER_WITH_GAPS';$res.Issues=@("Tras $($c.Round) rondas sigue sin cumplirse: $($failed -join ', '). Entrégalo diciendo qué falta y por qué.");Ac-SetHeader $path 'Estado' 'cerrado-con-pendientes'}
        else{$res.Code=1;$res.Status='FAILED';$res.Issues=@("Corrige $($failed -join ', ') dentro del contrato y revisa de nuevo (ronda $($c.Round) de $script:maxRounds).")}
        return [pscustomobject]$res
    }
    Ac-SetHeader $path 'Estado' 'aceptado'
    $res.Code=0;$res.Status='ACCEPTED'
    return [pscustomobject]$res
}
# When a subagent stops (Claude Code SubagentStop): a reviewer that edited the deliverable (the verdict went STALE)
# or passed items without a citation is sent back. Pending reviews do not block: the subagent may be unrelated.
function Test-AgentOpsReviewerStop {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectPath)
    $root=Ac-Root $ProjectPath;$res=[ordered]@{Decision='ALLOW';Status='NONE';Id=$null;Reason=''}
    $dir=Join-Path $root $script:dir;if(-not [IO.Directory]::Exists($dir)){return [pscustomobject]$res}
    foreach($f in @(Get-ChildItem -LiteralPath $dir -Filter '*.review.md' -ErrorAction SilentlyContinue)){
        $id=$f.Name -replace '\.review\.md$',''
        $contract=Ac-Path $root $id
        if(-not [IO.File]::Exists($contract) -or [IO.File]::ReadAllText($contract) -notmatch '(?m)^Estado:\s*abierto\b'){continue}
        $v=Test-AgentOpsAcceptance -ProjectPath $root -Id $id
        $res.Id=$id;$res.Status=$v.Status
        if($v.Status -eq 'STALE'){$res.Decision='BLOCK';$res.Reason="Agent Ops: el entregable de la revisión de aceptación $id cambió mientras se revisaba. El revisor no debe editar el entregable (R-017): restáuralo tal como estaba, marca FALLA con una cita en .context/aceptacion/$id.review.md y deja tus propuestas en «Observaciones para el usuario».";return [pscustomobject]$res}
        if($v.Status -eq 'INVALID'){$res.Decision='BLOCK';$res.Reason="Agent Ops: en la revisión de aceptación $id hay PASA sin cita. Cada PASA necesita una cita literal del entregable (.context/aceptacion/$id.review.md).";return [pscustomobject]$res}
    }
    return [pscustomobject]$res
}
Export-ModuleMember -Function New-AgentOpsAcceptance,New-AgentOpsAcceptanceReview,Test-AgentOpsAcceptance,Test-AgentOpsReviewerStop
