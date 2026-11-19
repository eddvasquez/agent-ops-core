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
            $current=[pscustomobject]@{Id=$id;Type=$type;Scopes=$scopes;State=$state;Text='';Detect=@();Require=@()}
            $rules+=$current
        }elseif($current -and $line -match '^-\s*([^:]+):\s*(.*)$'){
            $key=Rc-Fold $Matches[1];$value=$Matches[2]
            switch($key){
                'regla'{$current.Text=$value}
                'detectar'{$current.Detect+=Rc-Values $value}
                'exigir'{$current.Require+=Rc-Values $value}
            }
        }
    }
    foreach($r in $rules){
        foreach($p in $r.Detect){if($p -match '^re:(.+)$'){try{[void][regex]::new($Matches[1])}catch{$issues.Add("$($r.Id) has an invalid regular expression: $p")}}}
    }
    return [pscustomobject]@{Rules=$rules;Issues=@($issues)}
}

function Test-AgentOpsRules {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RulesPath,[Parameter(Mandatory)][string[]]$Path,[string]$Scope='')
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
        $review=@($applied|Where-Object {-not $_.Detect.Count -and -not $_.Require.Count}|ForEach-Object {[pscustomobject]@{Id=$_.Id;Type=$_.Type;Text=$_.Text}})
    }catch{$issues.Add($_.Exception.Message)}
    [pscustomobject]@{
        Code=$(if($issues.Count -or $violations.Count){1}else{0})
        Violations=@($violations);ReviewRules=@($review);Rules=@($all);Applied=@($applied|ForEach-Object Id)
        Files=@($files);Issues=@($issues)
    }
}
Export-ModuleMember -Function Test-AgentOpsRules
