Set-StrictMode -Version 2
# Harness capabilities table, detector of the harnesses in use, and the novelty radar (R1: GitHub sources).
# Downloaded text is data: versions are accepted only if they match a strict pattern; nothing is evaluated.
$script:defaultTable=Join-Path $PSScriptRoot 'harness-capabilities.json'
$script:statuses=@('aprovechada','pendiente','esperando','descartada')
$script:versionPattern='^\d+\.\d+\.\d+$'

function Hr-ReadJson([string]$path){[IO.File]::ReadAllText($path)|ConvertFrom-Json}
function Hr-Harnesses($table){@($table.Harnesses.PSObject.Properties|ForEach-Object {[pscustomobject]@{Id=$_.Name;Spec=$_.Value}})}
function Hr-Has($obj,[string]$name){$null -ne $obj -and $null -ne $obj.PSObject.Properties[$name]}
function Hr-Text($obj,[string]$name){if(Hr-Has $obj $name){[string]$obj.$name}else{''}}
function Hr-Date($value){
    # pwsh turns ISO strings into DateTime on ConvertFrom-Json; Windows PowerShell keeps strings.
    if($value -is [datetime]){return $value.ToUniversalTime()}
    return [datetime]::Parse([string]$value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]'AdjustToUniversal,AssumeUniversal')
}

function Test-AgentOpsFrameworkRepository {
    # The maintainer works inside the framework repository; consumer projects never have these two files at their root.
    [CmdletBinding()]
    param([string]$ProjectPath=(Get-Location).Path)
    return [IO.File]::Exists((Join-Path $ProjectPath 'release-contract.json')) -and [IO.File]::Exists((Join-Path $ProjectPath 'scripts/harness-capabilities.json'))
}

function Get-AgentOpsHarnessCapabilities {
    [CmdletBinding()]
    param([string]$Path=$script:defaultTable)
    return Hr-ReadJson $Path
}

function Test-AgentOpsHarnessCapabilities {
    [CmdletBinding()]
    param([string]$Path=$script:defaultTable)
    $issues=New-Object Collections.Generic.List[string]
    try{
        $t=Hr-ReadJson $Path
        if((Hr-Text $t 'SchemaVersion') -ne '1'){$issues.Add('SchemaVersion debe ser 1.')}
        foreach($h in (Hr-Harnesses $t)){
            $seen=@{}
            foreach($c in @($h.Spec.Capabilities)){
                $id=Hr-Text $c 'Id';$where="$($h.Id)/$id"
                if(-not $id){$issues.Add("$($h.Id): capacidad sin Id.");continue}
                if($seen.ContainsKey($id)){$issues.Add("${where}: Id repetido.")};$seen[$id]=$true
                $status=Hr-Text $c 'Status'
                if($status -notin $script:statuses){$issues.Add("${where}: estado '$status' desconocido; usa $($script:statuses -join ', ').")}
                if((Hr-Text $c 'Doc') -notmatch '^https://'){$issues.Add("${where}: falta el enlace https a la documentación oficial.")}
                if((Hr-Text $c 'VerifiedAt') -notmatch '^\d{4}-\d{2}-\d{2}$'){$issues.Add("${where}: falta la fecha de verificación (AAAA-MM-DD).")}
                if($status -eq 'descartada' -and -not (Hr-Text $c 'Reason')){$issues.Add("${where}: una capacidad descartada necesita su motivo (Reason).")}
                if($status -eq 'aprovechada' -and -not (Hr-Text $c 'Fallback')){$issues.Add("${where}: una capacidad aprovechada necesita su respaldo (Fallback) para que lo obligatorio no dependa de un arnés.")}
            }
        }
    }catch{$issues.Add($_.Exception.Message)}
    return [pscustomobject]@{Code=$(if($issues.Count){1}else{0});Issues=@($issues)}
}

function Get-AgentOpsHarnessPresence {
    [CmdletBinding()]
    param([string]$ProjectPath=(Get-Location).Path,[string]$Path=$script:defaultTable,[scriptblock]$CommandResolver)
    if(-not $CommandResolver){$CommandResolver={param([string]$name) [bool](Get-Command $name -CommandType Application -ErrorAction SilentlyContinue)}}
    $t=Hr-ReadJson $Path
    foreach($h in (Hr-Harnesses $t)){
        $inProject=@($h.Spec.Detect.Dirs|Where-Object {[IO.Directory]::Exists((Join-Path $ProjectPath $_))}).Count -gt 0
        $installed=@($h.Spec.Detect.Commands|Where-Object {& $CommandResolver $_}).Count -gt 0
        [pscustomobject]@{Id=$h.Id;Name=$h.Spec.Name;InProject=$inProject;Installed=$installed}
    }
}

function Hr-Fetch([string]$url){
    $r=Invoke-WebRequest -Uri $url -Headers @{'User-Agent'='agent-ops-harness-radar';'Accept'='application/vnd.github+json'} -TimeoutSec 5 -UseBasicParsing
    return [string]$r.Content
}
function Hr-LatestVersion($src,[string]$text){
    if($src.Kind -eq 'github-release'){
        $tag=[string](($text|ConvertFrom-Json).tag_name)
        $v=$tag -replace '^(rust-)?v',''
    }elseif($src.Kind -eq 'markdown-changelog'){
        $m=[regex]::Match($text,'(?m)^##\s+\[?(\S+?)\]?\s*$')
        $v=$(if($m.Success){$m.Groups[1].Value}else{''})
    }else{throw "Tipo de fuente desconocido: $($src.Kind)"}
    if($v -notmatch $script:versionPattern){throw 'Formato de versión no reconocido; se ignora.'}
    return $v
}
function Hr-State([string]$stateDir){
    $p=Join-Path $stateDir 'harness-radar.json'
    $s=@{SchemaVersion=1;Sources=@{};Novelties=@();Acked=@()}
    if([IO.File]::Exists($p)){
        $j=Hr-ReadJson $p
        foreach($prop in @($j.Sources.PSObject.Properties)){$s.Sources[$prop.Name]=@{LastCheck=$prop.Value.LastCheck;Latest=$prop.Value.Latest}}
        $s.Novelties=@($j.Novelties|Where-Object {$_}|ForEach-Object {@{Harness=$_.Harness;Version=$_.Version;FoundAt=$_.FoundAt}})
        $s.Acked=@($j.Acked|Where-Object {$_})
    }
    return $s
}
function Hr-SaveState([string]$stateDir,$s){
    [IO.Directory]::CreateDirectory($stateDir)|Out-Null
    $p=Join-Path $stateDir 'harness-radar.json';$tmp=$p+'.'+[guid]::NewGuid().ToString('N')+'.tmp'
    [IO.File]::WriteAllText($tmp,($s|ConvertTo-Json -Depth 6),(New-Object Text.UTF8Encoding($false)))
    if([IO.File]::Exists($p)){[IO.File]::Replace($tmp,$p,[NullString]::Value)}else{[IO.File]::Move($tmp,$p)}
}

function Invoke-AgentOpsHarnessRadar {
    [CmdletBinding()]
    param([ValidateSet('Check','Notice','Ack')][string]$Action='Notice',[string]$ProjectPath=(Get-Location).Path,
          [string]$StateDir=(Join-Path $env:LOCALAPPDATA 'AgentOps'),[string]$Path=$script:defaultTable,
          [scriptblock]$Fetcher,[datetime]$Now=[datetime]::UtcNow,[string]$Harness='',[string]$Version='')
    $res=[ordered]@{Code=0;Status='QUIET';Novelties=@();Lines=@();Skipped=@();Failures=@();Issues=@()}
    # R-010: novelties are for whoever maintains the framework; consumer projects get nothing and cause no network traffic.
    if($Action -ne 'Ack' -and -not (Test-AgentOpsFrameworkRepository -ProjectPath $ProjectPath)){$res.Status='NOT_MAINTAINER';return [pscustomobject]$res}
    try{
        $t=Hr-ReadJson $Path;$s=Hr-State $StateDir;$now=$Now.ToUniversalTime()
        if(-not $Fetcher){$Fetcher={param([string]$url) Hr-Fetch $url}}
        $names=@{};foreach($h in (Hr-Harnesses $t)){$names[$h.Id]=$h.Spec.Name}
        if($Action -eq 'Check'){
            foreach($h in (Hr-Harnesses $t)){
                foreach($src in @($h.Spec.Sources)){
                    $prev=$s.Sources[$src.Id]
                    if($prev -and $prev.LastCheck -and ($now-(Hr-Date $prev.LastCheck)).TotalHours -lt 24){$res.Skipped+=@($src.Id);continue}
                    $known=$(if($prev -and $prev.Latest){$prev.Latest}else{Hr-Text $h.Spec 'Baseline'})
                    $entry=@{LastCheck=$now.ToString('o');Latest=$known}
                    try{
                        $latest=Hr-LatestVersion $src (& $Fetcher $src.Url)
                        $entry.Latest=$latest
                        $isNew=(-not $known) -or ([version]$latest -gt [version]$known)
                        $already=@($s.Novelties|Where-Object {$_.Harness -eq $h.Id -and $_.Version -eq $latest}).Count -or ("$($h.Id)@$latest" -in $s.Acked)
                        if($known -and $isNew -and -not $already){
                            $n=@{Harness=$h.Id;Version=$latest;FoundAt=$now.ToString('o')};$s.Novelties+=@($n);$res.Novelties+=@([pscustomobject]$n)
                        }
                    }catch{$res.Failures+=@([pscustomobject]@{Source=$src.Id;Message=$_.Exception.Message})}
                    $s.Sources[$src.Id]=$entry
                }
            }
            Hr-SaveState $StateDir $s
        }elseif($Action -eq 'Ack'){
            if(-not $names.ContainsKey($Harness) -or $Version -notmatch $script:versionPattern){throw 'Indica -Harness (claude-code, codex o antigravity) y -Version (X.Y.Z).'}
            $key="$Harness@$Version";if($key -notin $s.Acked){$s.Acked+=@($key)}
            Hr-SaveState $StateDir $s;$res.Status='ACKED'
        }
        foreach($n in @($s.Novelties|Where-Object {"$($_.Harness)@$($_.Version)" -notin $s.Acked})){
            $res.Lines+=@("Novedad de arnés: $($names[$n.Harness]) $($n.Version). Pide «evalúa $($n.Harness) $($n.Version)».")
        }
        if($Action -ne 'Ack' -and @($res.Lines).Count){$res.Status='NOTICE'}
    }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($_.Exception.Message)}
    return [pscustomobject]$res
}
Export-ModuleMember -Function Test-AgentOpsFrameworkRepository,Get-AgentOpsHarnessCapabilities,Test-AgentOpsHarnessCapabilities,Get-AgentOpsHarnessPresence,Invoke-AgentOpsHarnessRadar
