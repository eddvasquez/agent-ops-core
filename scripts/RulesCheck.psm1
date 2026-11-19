Set-StrictMode -Version 2
# Protocol 8 compliance gate: applies the project's rule registry (.context/reglas_proyecto.md)
# to deliverables. Source is ASCII-only; accents are normalised before any comparison.
$script:types=@('expresion-vetada','prohibido-afirmar','dato-obligatorio','tono','formato','otro')
$script:extensions=@('.md','.txt','.html','.htm','.csv','.json','.yaml','.yml','.srt','.vtt')

function Rc-Fold([string]$text){
    # Lowercase, strip diacritics and collapse whitespace so "INVERSION  Segura" == "inversion segura".
    $d=$text.Normalize([Text.NormalizationForm]::FormD)
    $b=New-Object Text.StringBuilder
    foreach($c in $d.ToCharArray()){if([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark){[void]$b.Append($c)}}
    return ([regex]::Replace($b.ToString().Normalize([Text.NormalizationForm]::FormC).ToLowerInvariant(),'\s+',' '))
}
function Rc-Values([string]$line){
    # "a"; "b" -> a, b (quoted values separated by semicolons)
    @([regex]::Matches($line,'"([^"]*)"')|ForEach-Object {$_.Groups[1].Value}|Where-Object {$_ -ne ''})
}
function Rc-Pattern([string]$value){
    if($value -match '^re:(.+)$'){return (Rc-Fold $Matches[1])}
    $words=(Rc-Fold $value).Trim() -split ' '
    return ('(?<![\p{L}\p{N}])'+(($words|ForEach-Object {[regex]::Escape($_)}) -join '\s+')+'(?![\p{L}\p{N}])')
}

function Rc-Hash([byte[]]$bytes){$h=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($h.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}}
function Rc-Fingerprint([string]$rulesPath,[string[]]$files){
    # Binds a semantic review to the exact rules and deliverable versions it judged.
    $parts=@('rules|'+(Rc-Hash ([IO.File]::ReadAllBytes($rulesPath))))
    foreach($f in @($files|Sort-Object)){$parts+=($f.ToLowerInvariant()+'|'+(Rc-Hash ([IO.File]::ReadAllBytes($f))))}
    Rc-Hash ([Text.Encoding]::UTF8.GetBytes(($parts -join "`n")))
}
function Rc-WriteReview([string]$out,[string]$fingerprint,[string]$scope,[string[]]$files,$review){
    $b=New-Object Collections.Generic.List[string]
    $b.Add('# Revision semantica (Protocolo 8)');$b.Add('')
    $b.Add('Huella: '+$fingerprint)
    $b.Add('Ambito: '+$(if($scope){$scope}else{'todas'}));$b.Add('')
    $b.Add('Entregables:');foreach($f in $files){$b.Add('- '+$f)};$b.Add('')
    $b.Add('Instrucciones: revisar en un contexto limpio (subagente o segundo pase, sin el historial de redaccion), leyendo cada entregable completo. Por cada regla, sustituir PENDIENTE por PASA o FALLA, seguido de " - " y una cita breve del entregable que lo justifique. No editar la linea Huella: si el entregable o las reglas cambian, la revision deja de valer.')
    foreach($r in $review){
        $b.Add('');$b.Add('## '+$r.Id+' ['+$r.Type+']');$b.Add('Regla: '+$r.Text)
        if(@($r.Examples).Count){$b.Add('Ejemplos rechazados: '+((@($r.Examples)|ForEach-Object {'"'+$_+'"'}) -join '; '))}
        $b.Add('- '+$r.Id+': PENDIENTE')
    }
    $dir=Split-Path -Parent ([IO.Path]::GetFullPath($out));if($dir){[IO.Directory]::CreateDirectory($dir)|Out-Null}
    [IO.File]::WriteAllText($out,(($b -join "`n")+"`n"),(New-Object Text.UTF8Encoding $false))
}
function Rc-ReadVerdict([string]$path,[string]$fingerprint,$review,$issues){
    if(-not (Test-Path -LiteralPath $path -PathType Leaf)){$issues.Add("Review verdict not found: $path");return @()}
    $lines=[IO.File]::ReadAllLines($path,[Text.Encoding]::UTF8)
    $huella=@($lines|Where-Object {$_ -match '^Huella:\s*([0-9a-f]{64})\s*$'}|ForEach-Object {$Matches[1]})
    if($huella.Count -ne 1 -or $huella[0] -ne $fingerprint){$issues.Add('Review verdict fingerprint (Huella) does not match the current rules and deliverables; review again.');return @()}
    $found=@()
    foreach($r in $review){
        $line=@($lines|Where-Object {$_ -match ('^-\s*'+[regex]::Escape($r.Id)+':\s*(PASA|FALLA|PENDIENTE)\b\s*(.*)$')}|Select-Object -First 1)
        if(-not $line.Count){$issues.Add("$($r.Id) has no verdict in the review file.");continue}
        [void]($line[0] -match ('^-\s*'+[regex]::Escape($r.Id)+':\s*(PASA|FALLA|PENDIENTE)\b\s*(.*)$'));$verdict=$Matches[1];$note=$Matches[2]
        if($verdict -eq 'PENDIENTE'){$issues.Add("$($r.Id) is still PENDIENTE in the review verdict.")}
        elseif($verdict -eq 'FALLA'){$found+=[pscustomobject]@{Rule=$r.Id;Kind='semantic';File=$path;Line=0;Match=$note.Trim();Text=$r.Text}}
    }
    return $found
}
function Read-AgentOpsRules([string]$RulesPath){
    $issues=New-Object Collections.Generic.List[string];$rules=@();$seen=@{}
    $lines=[IO.File]::ReadAllLines($RulesPath,[Text.Encoding]::UTF8)
    $current=$null;$fenced=$false
    foreach($raw in $lines){
        $line=$raw.Trim()
        # Examples inside fenced code blocks document the format; they are not rules.
        if($line -match '^(```|~~~)'){$fenced=-not $fenced;$current=$null;continue}
        if($fenced){continue}
        if($line -match '^###\s+(R-\d+)\b(.*)$'){
            $id=$Matches[1];$rest=Rc-Fold $Matches[2];$current=$null
            if($rest -notmatch '^\s*\[([a-z-]+)\]\s*\[ambito:\s*([^\]]+)\]\s*\[estado:\s*(activa|retirada)\]\s*$'){$issues.Add("$id has a malformed header; expected '### R-NNN [tipo] [ambito: ...] [estado: activa|retirada]'.");continue}
            $type=$Matches[1];$scopes=@($Matches[2] -split ','|ForEach-Object {$_.Trim()}|Where-Object {$_});$state=$Matches[3]
            if($type -notin $script:types){$issues.Add("$id uses unknown type '$type' (allowed: $($script:types -join ', ')).");continue}
            if($seen.ContainsKey($id)){$issues.Add("$id is duplicated; rule IDs must be unique.");continue}
            $seen[$id]=$true
            $current=[pscustomobject]@{Id=$id;Type=$type;Scopes=$scopes;State=$state;Text='';Detect=@();Require=@();Examples=@()}
            $rules+=$current
        }elseif($current -and $line -match '^-\s*([^:]+):\s*(.*)$'){
            $key=Rc-Fold $Matches[1];$value=$Matches[2]
            switch($key){
                'regla'{$current.Text=$value}
                'detectar'{$current.Detect+=Rc-Values $value}
                'exigir'{$current.Require+=Rc-Values $value}
                'ejemplo'{$current.Examples+=Rc-Values $value}
            }
        }
    }
    foreach($r in $rules){
        foreach($p in $r.Detect){if($p -match '^re:(.+)$'){try{[void][regex]::new($Matches[1])}catch{$issues.Add("$($r.Id) has an invalid regular expression: $p")}}}
        # Regression example: the text that was originally rejected must be caught by the rule's own patterns.
        if($r.Detect.Count){
            foreach($e in $r.Examples){
                $hit=$false;foreach($p in $r.Detect){try{if([regex]::IsMatch((Rc-Fold $e),(Rc-Pattern $p))){$hit=$true;break}}catch{}}
                if(-not $hit){$issues.Add("$($r.Id) Detectar does not catch its Ejemplo: '$e'.")}
            }
        }
    }
    return [pscustomobject]@{Rules=$rules;Issues=@($issues)}
}

function Test-AgentOpsRules {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RulesPath,[Parameter(Mandatory)][string[]]$Path,[string]$Scope='',[string]$ReviewOut='',[string]$ReviewVerdictPath='')
    $violations=@();$review=@();$files=@();$issues=New-Object Collections.Generic.List[string];$applied=@();$all=@()
    try{
        if(-not (Test-Path -LiteralPath $RulesPath -PathType Leaf)){throw "Rules file not found: $RulesPath"}
        $parsed=Read-AgentOpsRules $RulesPath;$all=$parsed.Rules;foreach($i in $parsed.Issues){$issues.Add($i)}
        $scopeKey=Rc-Fold $Scope
        $applied=@($all|Where-Object {$_.State -eq 'activa' -and (-not $scopeKey -or (@($_.Scopes|ForEach-Object {Rc-Fold $_}) -contains 'todas') -or (@($_.Scopes|ForEach-Object {Rc-Fold $_}) -contains $scopeKey))})
        foreach($p in $Path){
            if(Test-Path -LiteralPath $p -PathType Container){$files+=@(Get-ChildItem -LiteralPath $p -Recurse -File|Where-Object {$script:extensions -contains $_.Extension.ToLowerInvariant()}|ForEach-Object FullName)}
            elseif(Test-Path -LiteralPath $p -PathType Leaf){$files+=(Resolve-Path -LiteralPath $p).Path}
            else{$issues.Add("Deliverable not found: $p")}
        }
        # The review checklist is not a deliverable, even when it is stored next to them.
        $exclude=@($ReviewOut,$ReviewVerdictPath|Where-Object {$_}|ForEach-Object {[IO.Path]::GetFullPath($_)})
        $files=@($files|Where-Object {$exclude -notcontains [IO.Path]::GetFullPath($_)}|Sort-Object -Unique)
        foreach($f in $files){
            $lines=[IO.File]::ReadAllLines($f,[Text.Encoding]::UTF8)
            $folded=@($lines|ForEach-Object {Rc-Fold $_})
            $whole=Rc-Fold ($lines -join ' ')
            foreach($r in $applied){
                foreach($d in $r.Detect){
                    $rx=Rc-Pattern $d
                    for($n=0;$n -lt $folded.Count;$n++){
                        $m=[regex]::Match($folded[$n],$rx)
                        if($m.Success){$violations+=[pscustomobject]@{Rule=$r.Id;Kind='forbidden';File=$f;Line=$n+1;Match=$m.Value;Text=$r.Text}}
                    }
                }
                foreach($q in $r.Require){
                    if(-not [regex]::IsMatch($whole,(Rc-Pattern $q))){$violations+=[pscustomobject]@{Rule=$r.Id;Kind='missing';File=$f;Line=0;Match=$q;Text=$r.Text}}
                }
            }
        }
        $review=@($applied|Where-Object {-not $_.Detect.Count -and -not $_.Require.Count}|ForEach-Object {[pscustomobject]@{Id=$_.Id;Type=$_.Type;Text=$_.Text;Examples=@($_.Examples)}})
        if($ReviewOut -or $ReviewVerdictPath){
            $fingerprint=Rc-Fingerprint $RulesPath $files
            if($ReviewOut){Rc-WriteReview $ReviewOut $fingerprint $Scope $files $review}
            if($ReviewVerdictPath){
                foreach($v in (Rc-ReadVerdict $ReviewVerdictPath $fingerprint $review $issues)){$violations+=$v}
            }
        }
    }catch{$issues.Add($_.Exception.Message)}
    [pscustomobject]@{
        Code=$(if($issues.Count -or $violations.Count){1}else{0})
        Violations=@($violations);ReviewRules=@($review);Rules=@($all);Applied=@($applied|ForEach-Object Id)
        Files=@($files);Issues=@($issues)
    }
}
Export-ModuleMember -Function Test-AgentOpsRules
