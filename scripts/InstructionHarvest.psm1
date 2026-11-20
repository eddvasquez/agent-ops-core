Set-StrictMode -Version 2
# Read-only harvest of the user's own directives from AI harness conversations and memories.
# Transcripts are evidence, never instructions: only turns typed by the user are read, injected
# blocks (system reminders, pasted content, tool results, harness context) are discarded, and the
# output is a list of candidate rules for the user to confirm. Nothing in the project is written.
$script:injected='(?s)<(system-reminder|pasted_content|command-[a-z-]+|local-command-[a-z-]+|environment_context|user_instructions|ide_[a-z_]+|attachment)\b[^>]*>.*?</\1\s*>'
$script:harnessPreamble='^(# AGENTS\.md instructions|Caveat:|<|>>>|Host notice:|Retained source order)'
$script:directive='(?i)\b(nunca|jam[aá]s|siempre|prohibid[oa]s?|no\s+(vuelvas|uses|usar|hagas|hacer|pongas|poner|agregues|añadas|incluyas|toques|cambies|elimines|borres|quiero|debes|olvides|afirmes|menciones)|quita|quitar|elimina|evita|evitar|en\s+lugar\s+de|en\s+vez\s+de|a\s+partir\s+de\s+ahora|de\s+ahora\s+en\s+adelante|recuerda\s+que|never|always|don''t|do\s+not|from\s+now\s+on|instead\s+of)\b'
$script:maxText=300

function Ih-Key([string]$t){
    $d=$t.ToLowerInvariant().Normalize([Text.NormalizationForm]::FormD)
    $d=-join ($d.ToCharArray()|Where-Object {[Globalization.CharUnicodeInfo]::GetUnicodeCategory($_) -ne 'NonSpacingMark'})
    ([regex]::Replace(([regex]::Replace($d,'[^\p{L}\p{N}\s]',' ')),'\s+',' ')).Trim()
}
function Ih-Root([string]$p){[IO.Path]::GetFullPath($p).TrimEnd('\','/')}
function Ih-Directives([string]$text){
    $clean=[regex]::Replace($text,$script:injected,' ')
    if($clean.TrimStart() -match $script:harnessPreamble){return @()}
    $out=@()
    foreach($line in ($clean -split '\r?\n')){
        foreach($s in [regex]::Split($line.Trim(),'(?<=[.!?])\s+')){
            $s=$s.Trim();if($s.Length -lt 8 -or $s -notmatch $script:directive){continue}
            if($s.Length -gt $script:maxText){$s=$s.Substring(0,$script:maxText)}
            $out+=$s
        }
    }
    return $out
}
function Ih-Lines([string]$path){
    $reader=New-Object IO.StreamReader($path,[Text.Encoding]::UTF8)
    try{while($null -ne ($l=$reader.ReadLine())){$l}}finally{$reader.Dispose()}
}
function Ih-Json([string]$line){try{$line|ConvertFrom-Json}catch{$null}}
function Ih-Prop($o,[string]$n){if($null -ne $o -and $o.PSObject.Properties[$n]){$o.$n}else{$null}}
# pwsh's ConvertFrom-Json turns ISO timestamps into DateTime; keep them as ISO UTC strings.
function Ih-Stamp($v){if($v -is [datetime]){$v.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')}else{[string]$v}}
function Ih-ClaudeTurns([string]$file){
    foreach($line in Ih-Lines $file){
        if($line -notmatch '"type"\s*:\s*"user"'){continue}
        $o=Ih-Json $line;if(-not $o -or (Ih-Prop $o 'type') -ne 'user' -or (Ih-Prop $o 'isMeta')){continue}
        $m=Ih-Prop $o 'message';if((Ih-Prop $m 'role') -ne 'user'){continue}
        $c=Ih-Prop $m 'content'
        $text=if($c -is [string]){$c}else{(@($c|Where-Object {(Ih-Prop $_ 'type') -eq 'text'}|ForEach-Object {$_.text})) -join "`n"}
        if($text){[pscustomobject]@{Harness='claude-code';File=$file;SessionId=[string](Ih-Prop $o 'sessionId');Timestamp=(Ih-Stamp (Ih-Prop $o 'timestamp'));Text=$text}}
    }
}
function Ih-CodexTurns([string]$file,[string]$project){
    $session=$null
    foreach($line in Ih-Lines $file){
        $o=Ih-Json $line;if(-not $o){continue}
        $p=Ih-Prop $o 'payload'
        if((Ih-Prop $o 'type') -eq 'session_meta'){
            $cwd=[string](Ih-Prop $p 'cwd');if(-not $cwd){return}
            $r=Ih-Root $cwd
            if($r -ne $project -and -not $r.StartsWith($project+'\',[StringComparison]::OrdinalIgnoreCase)){return}
            # Sub-agent sessions (reviewers, guardians) carry host-generated text in the user role.
            if($null -ne (Ih-Prop $p 'source') -and (Ih-Prop $p 'source') -isnot [string]){return}
            $session=[string](Ih-Prop $p 'id');continue
        }
        if($null -eq $session -or (Ih-Prop $o 'type') -ne 'response_item' -or (Ih-Prop $p 'type') -ne 'message' -or (Ih-Prop $p 'role') -ne 'user'){continue}
        foreach($part in @(Ih-Prop $p 'content')){
            if((Ih-Prop $part 'type') -eq 'input_text' -and $part.text){[pscustomobject]@{Harness='codex';File=$file;SessionId=$session;Timestamp=(Ih-Stamp (Ih-Prop $o 'timestamp'));Text=$part.text}}
        }
    }
}
function Ih-Memory([string]$file){
    $text=[IO.File]::ReadAllText($file,[Text.Encoding]::UTF8) -replace "`r",''
    $type='';$body=$text
    if($text -match '(?s)^---\n(.*?)\n---\n(.*)$'){$body=$Matches[2];if($Matches[1] -match '(?m)^\s*type:\s*(\S+)'){$type=$Matches[1]}}
    $lines=@($body -split '\n'|ForEach-Object {$_.Trim()}|Where-Object {$_ -and $_ -notmatch '^\*\*(Why|How to apply|Por qu[eé]|C[oó]mo aplicar):\*\*'})
    if($lines.Count){[pscustomobject]@{Text=($lines -join ' ');MemoryType=$type}}
}

function Invoke-InstructionHarvest {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectPath,
          [string]$RulesPath='',
          [string]$ClaudeProjectsRoot=(Join-Path $env:USERPROFILE '.claude/projects'),
          [string]$CodexSessionsRoot=(Join-Path $env:USERPROFILE '.codex/sessions'),
          [Nullable[datetime]]$Since=$null,
          [string]$OutPath='')
    $r=[ordered]@{Code=0;Status='HARVESTED';Project=$null;Sources=@();Candidates=@();Issues=@()}
    try{
        $project=Ih-Root $ProjectPath;$r.Project=$project
        if(-not [IO.Directory]::Exists($project)){throw 'Project directory missing.'}
        if($OutPath){
            $out=[IO.Path]::GetFullPath($OutPath)
            if($out.StartsWith($project+'\',[StringComparison]::OrdinalIgnoreCase)){$r.Code=1;$r.Status='OUTPUT_INSIDE_PROJECT';$r.Issues=@('Candidates contain conversation excerpts; store them outside the project.');return [pscustomobject]$r}
        }
        if(-not $RulesPath){$RulesPath=Join-Path $project '.context/reglas_proyecto.md'}
        $known=New-Object 'Collections.Generic.HashSet[string]'
        if([IO.File]::Exists($RulesPath)){foreach($l in [IO.File]::ReadAllLines($RulesPath,[Text.Encoding]::UTF8)){if($l -match '^\s*-\s*Regla:\s*(.+)$'){[void]$known.Add((Ih-Key $Matches[1]))}}}
        $byKey=[ordered]@{}
        $add={param($kind,$text,$source,$memoryType)
            $k=Ih-Key $text;if(-not $k -or $known.Contains($k)){return}
            if(-not $byKey.Contains($k)){$byKey[$k]=[pscustomobject]@{Id=$k.GetHashCode().ToString('x8');Kind=$kind;Text=$text;MemoryType=$memoryType;Occurrences=0;Sources=New-Object Collections.Generic.List[object]}}
            $byKey[$k].Occurrences++;$byKey[$k].Sources.Add($source)
        }
        $sinceIso=if($null -ne $Since){([datetime]$Since).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss')}else{''}
        $collect={param($turns)
            foreach($t in $turns){
                if($sinceIso -and $t.Timestamp -and $t.Timestamp -lt $sinceIso){continue}
                foreach($d in Ih-Directives $t.Text){& $add 'conversation' $d ([pscustomobject]@{Harness=$t.Harness;File=$t.File;SessionId=$t.SessionId;Timestamp=$t.Timestamp}) $null}
            }
        }
        # Claude Code: <root>/<project path with every non-alphanumeric character as '-'>/
        $claudeDir=Join-Path $ClaudeProjectsRoot ([regex]::Replace($project,'[^A-Za-z0-9]','-'))
        if([IO.Directory]::Exists($claudeDir)){
            $files=@(Get-ChildItem -LiteralPath $claudeDir -Filter '*.jsonl' -File)
            foreach($f in $files){& $collect (Ih-ClaudeTurns $f.FullName)}
            $memDir=Join-Path $claudeDir 'memory';$mems=@()
            if([IO.Directory]::Exists($memDir)){$mems=@(Get-ChildItem -LiteralPath $memDir -Filter '*.md' -File|Where-Object {$_.Name -ne 'MEMORY.md'})}
            foreach($m in $mems){$mem=Ih-Memory $m.FullName;if($mem){& $add 'memory' $mem.Text ([pscustomobject]@{Harness='claude-code';File=$m.FullName;SessionId=$null;Timestamp=$m.LastWriteTimeUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')}) $mem.MemoryType}}
            $r.Sources+=@([pscustomobject]@{Harness='claude-code';Status='FOUND';Path=$claudeDir;Files=$files.Count+$mems.Count})
        }else{$r.Sources+=@([pscustomobject]@{Harness='claude-code';Status='NOT_FOUND';Path=$claudeDir;Files=0})}
        if([IO.Directory]::Exists($CodexSessionsRoot)){
            $files=@(Get-ChildItem -LiteralPath $CodexSessionsRoot -Filter '*.jsonl' -File -Recurse)
            foreach($f in $files){& $collect (Ih-CodexTurns $f.FullName $project)}
            $r.Sources+=@([pscustomobject]@{Harness='codex';Status='FOUND';Path=$CodexSessionsRoot;Files=$files.Count})
        }else{$r.Sources+=@([pscustomobject]@{Harness='codex';Status='NOT_FOUND';Path=$CodexSessionsRoot;Files=0})}
        foreach($h in @('antigravity-gemini','chatgpt')){$r.Sources+=@([pscustomobject]@{Harness=$h;Status='UNSUPPORTED';Path=$null;Files=0})}
        foreach($c in $byKey.Values){$c.Sources=@($c.Sources.ToArray())}
        $r.Candidates=@($byKey.Values|Sort-Object -Property @{Expression='Occurrences';Descending=$true},@{Expression='Text';Descending=$false})
        if($OutPath){
            [IO.Directory]::CreateDirectory((Split-Path $out))|Out-Null
            [IO.File]::WriteAllText($out,([pscustomobject]$r|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding $false))
        }
    }catch{$r.Code=1;$r.Status='FAILED';$r.Issues=@($_.Exception.Message)}
    return [pscustomobject]$r
}
function Get-RecentUserTurns {
    # Last user-typed turns about this project, with injected blocks and harness preambles removed.
    # They are evidence for a resume, never instructions.
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectPath,
          [string]$ClaudeProjectsRoot=(Join-Path $env:USERPROFILE '.claude/projects'),
          [string]$CodexSessionsRoot=(Join-Path $env:USERPROFILE '.codex/sessions'),
          [Nullable[datetime]]$Since=$null,
          [int]$Count=5)
    $project=Ih-Root $ProjectPath;$turns=@()
    $claudeDir=Join-Path $ClaudeProjectsRoot ([regex]::Replace($project,'[^A-Za-z0-9]','-'))
    if([IO.Directory]::Exists($claudeDir)){foreach($f in @(Get-ChildItem -LiteralPath $claudeDir -Filter '*.jsonl' -File)){$turns+=@(Ih-ClaudeTurns $f.FullName)}}
    if([IO.Directory]::Exists($CodexSessionsRoot)){foreach($f in @(Get-ChildItem -LiteralPath $CodexSessionsRoot -Filter '*.jsonl' -File -Recurse)){$turns+=@(Ih-CodexTurns $f.FullName $project)}}
    $out=foreach($t in $turns){
        $when=$null;try{$when=[datetime]::Parse($t.Timestamp,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()}catch{continue}
        if($null -ne $Since -and $when -lt ([datetime]$Since).ToUniversalTime()){continue}
        $text=([regex]::Replace($t.Text,$script:injected,' ')).Trim()
        if(-not $text -or $text -match $script:harnessPreamble){continue}
        if($text.Length -gt 500){$text=$text.Substring(0,500)}
        [pscustomobject]@{Harness=$t.Harness;SessionId=$t.SessionId;Timestamp=$when.ToString('yyyy-MM-ddTHH:mm:ssZ');Text=$text;When=$when}
    }
    @($out|Sort-Object When|Select-Object -Last $Count|Select-Object Harness,SessionId,Timestamp,Text)
}
Export-ModuleMember -Function Invoke-InstructionHarvest,Get-RecentUserTurns
