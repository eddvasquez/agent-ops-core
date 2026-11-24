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

# Network access is kept minimal; decoding and redirects are separate pieces with their own tests.
# Windows PowerShell assumes ISO-8859-1 when the server declares no charset, and it does not follow 308:
# reading the bytes as UTF-8 and following redirects here gives the same text in both editions.
function Hr-DecodeBody([byte[]]$bytes){
    if(-not $bytes){return ''}
    return ([Text.Encoding]::UTF8.GetString($bytes)).TrimStart([char]0xFEFF)
}
function Hr-FollowRedirects([string]$url,[scriptblock]$get){
    for($i=0;$i -lt 5;$i++){
        $r=& $get $url
        if($r.Status -ge 200 -and $r.Status -lt 300){return Hr-DecodeBody $r.Bytes}
        if($r.Status -in 301,302,303,307,308 -and $r.Location){$url=(New-Object Uri ((New-Object Uri $url),[string]$r.Location)).AbsoluteUri;continue}
        throw "La fuente respondió HTTP $($r.Status)."
    }
    throw 'Demasiadas redirecciones; se ignora.'
}
function Hr-HttpGet([string]$url,[int]$timeoutSeconds){
    $req=[Net.HttpWebRequest]::Create($url)
    $req.AllowAutoRedirect=$false;$req.UserAgent='agent-ops-harness-radar';$req.Timeout=$timeoutSeconds*1000;$req.ReadWriteTimeout=$timeoutSeconds*1000
    $req.AutomaticDecompression=[Net.DecompressionMethods]'GZip,Deflate'
    if($url -like 'https://api.github.com/*'){$req.Accept='application/vnd.github+json'}
    try{$resp=$req.GetResponse()}catch [Net.WebException]{$resp=$_.Exception.Response;if(-not $resp){throw}}
    try{
        $buffer=New-Object IO.MemoryStream;$resp.GetResponseStream().CopyTo($buffer)
        return @{Status=[int]$resp.StatusCode;Location=$resp.Headers['Location'];Bytes=$buffer.ToArray()}
    }finally{$resp.Close()}
}
function Hr-Fetch([string]$url){
    # Documentation pages can weigh a few MB; GitHub sources are small.
    $timeout=$(if($url -like 'https://api.github.com/*' -or $url -like 'https://raw.githubusercontent.com/*'){5}else{10})
    # No GetNewClosure(): it would move the block out of this module and hide Hr-HttpGet; $timeout is read from this call.
    return Hr-FollowRedirects $url {param([string]$u) Hr-HttpGet $u $timeout}
}function Hr-LatestVersion($src,[string]$text){
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
# Fingerprint of the visible text only: scripts, styles and markup change on every deploy without meaning anything.
function Hr-PageFingerprint([string]$html){
    $text=[regex]::Replace($html,'(?is)<(script|style|noscript)\b.*?</\1>',' ')
    $text=[regex]::Replace($text,'(?s)<[^>]+>',' ')
    $text=([regex]::Replace([Net.WebUtility]::HtmlDecode($text),'\s+',' ')).Trim()
    if(-not $text){throw 'La página no tiene texto visible; se ignora.'}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text)))).Replace('-','').Substring(0,16).ToLowerInvariant()}finally{$sha.Dispose()}
}
# Installed version: first X.Y.Z printed by '<command> --version', with a 5 s limit; any failure means "unknown".
function Hr-InstalledVersion([string]$command){
    $app=Get-Command $command -CommandType Application -ErrorAction SilentlyContinue|Select-Object -First 1
    if(-not $app){return $null}
    $out=[IO.Path]::GetTempFileName()
    try{
        $proc=Start-Process -FilePath $app.Source -ArgumentList '--version' -NoNewWindow -PassThru -RedirectStandardOutput $out
        if(-not $proc.WaitForExit(5000)){try{$proc.Kill()}catch{};return $null}
        return [IO.File]::ReadAllText($out)
    }finally{Remove-Item -LiteralPath $out -Force -ErrorAction SilentlyContinue}
}
function Hr-Version([string]$text){
    $m=[regex]::Match([string]$text,'\b(\d+\.\d+\.\d+)\b')
    if($m.Success){return $m.Groups[1].Value};return $null
}
function Hr-State([string]$stateDir){
    $p=Join-Path $stateDir 'harness-radar.json'
    $s=@{SchemaVersion=1;Sources=@{};Installed=@{};Novelties=@();Acked=@()}
    if([IO.File]::Exists($p)){
        $j=Hr-ReadJson $p
        foreach($prop in @($j.Sources.PSObject.Properties)){$s.Sources[$prop.Name]=@{LastCheck=$prop.Value.LastCheck;Latest=$prop.Value.Latest}}
        if(Hr-Has $j 'Installed'){foreach($prop in @($j.Installed.PSObject.Properties)){$s.Installed[$prop.Name]=@{LastCheck=$prop.Value.LastCheck;Version=$prop.Value.Version}}}
        $s.Novelties=@($j.Novelties|Where-Object {$_}|ForEach-Object {
            # 3.9.x saved only Harness and Version: those were upstream versions.
            $kind=$(if(Hr-Has $_ 'Kind'){$_.Kind}else{'version'})
            $key=$(if(Hr-Has $_ 'Key'){$_.Key}else{"$($_.Harness)@$($_.Version)"})
            @{Key=$key;Kind=$kind;Harness=$_.Harness;Version=(Hr-Text $_ 'Version');Source=(Hr-Text $_ 'Source');From=(Hr-Text $_ 'From');FoundAt=$_.FoundAt}
        })
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
function Hr-Known($s,[string]$key){@($s.Novelties|Where-Object {$_.Key -eq $key}).Count -gt 0 -or $key -in $s.Acked}
function Hr-Add($s,$res,[hashtable]$n){if(-not (Hr-Known $s $n.Key)){$s.Novelties+=@($n);$res.Novelties+=@([pscustomobject]$n)}}
function Hr-Line($n,$names){
    $name=$names[$n.Harness]
    switch($n.Kind){
        'doc'{return "Novedad de arnés: cambió la documentación de $name ($($n.Source)). Pide «evalúa $($n.Harness) $($n.Source)»."}
        'installed'{return "Novedad de arnés: en este equipo $name pasó de $($n.From) a $($n.Version). Pide «evalúa $($n.Harness) $($n.Version)»."}
        default{return "Novedad de arnés: $name $($n.Version). Pide «evalúa $($n.Harness) $($n.Version)»."}
    }
}

function Invoke-AgentOpsHarnessRadar {
    [CmdletBinding()]
    param([ValidateSet('Check','Notice','Ack')][string]$Action='Notice',[string]$ProjectPath=(Get-Location).Path,
          [string]$StateDir=(Join-Path $env:LOCALAPPDATA 'AgentOps'),[string]$Path=$script:defaultTable,
          [scriptblock]$Fetcher,[scriptblock]$VersionResolver,[datetime]$Now=[datetime]::UtcNow,
          [string]$Harness='',[string]$Version='',[string]$Source='')
    $res=[ordered]@{Code=0;Status='QUIET';Novelties=@();Lines=@();Skipped=@();Failures=@();Issues=@()}
    # R-010: novelties are for whoever maintains the framework; consumer projects get nothing and cause no network traffic.
    if($Action -ne 'Ack' -and -not (Test-AgentOpsFrameworkRepository -ProjectPath $ProjectPath)){$res.Status='NOT_MAINTAINER';return [pscustomobject]$res}
    try{
        $t=Hr-ReadJson $Path;$s=Hr-State $StateDir;$now=$Now.ToUniversalTime();$stamp=$now.ToString('o')
        if(-not $Fetcher){$Fetcher={param([string]$url) Hr-Fetch $url}}
        if(-not $VersionResolver){$VersionResolver={param([string]$command) Hr-InstalledVersion $command}}
        $names=@{};foreach($h in (Hr-Harnesses $t)){$names[$h.Id]=$h.Spec.Name}
        $due={param($last) -not $last -or ($now-(Hr-Date $last)).TotalHours -ge 24}
        if($Action -eq 'Check'){
            foreach($h in (Hr-Harnesses $t)){
                foreach($src in @($h.Spec.Sources)){
                    $prev=$s.Sources[$src.Id]
                    if($prev -and -not (& $due $prev.LastCheck)){$res.Skipped+=@($src.Id);continue}
                    $known=$(if($prev -and $prev.Latest){$prev.Latest}elseif($src.Kind -ne 'doc-page'){Hr-Text $h.Spec 'Baseline'}else{''})
                    $entry=@{LastCheck=$stamp;Latest=$known}
                    try{
                        $text=& $Fetcher $src.Url
                        if($src.Kind -eq 'doc-page'){
                            $print=Hr-PageFingerprint $text;$entry.Latest=$print
                            if($known -and $print -ne $known){Hr-Add $s $res @{Key="$($h.Id)#$($src.Id)@$print";Kind='doc';Harness=$h.Id;Version='';Source=$src.Id;From=$known;FoundAt=$stamp}}
                        }else{
                            $latest=Hr-LatestVersion $src $text;$entry.Latest=$latest
                            if($known -and [version]$latest -gt [version]$known){Hr-Add $s $res @{Key="$($h.Id)@$latest";Kind='version';Harness=$h.Id;Version=$latest;Source=$src.Id;From=$known;FoundAt=$stamp}}
                        }
                    }catch{$res.Failures+=@([pscustomobject]@{Source=$src.Id;Message=$_.Exception.Message})}
                    $s.Sources[$src.Id]=$entry
                }
                $command=Hr-Text $h.Spec 'VersionCommand'
                $prev=$s.Installed[$h.Id]
                if($command -and (-not $prev -or (& $due $prev.LastCheck))){
                    $installed=$null;try{$installed=Hr-Version (& $VersionResolver $command)}catch{}
                    $before=$(if($prev){$prev.Version}else{''})
                    if($installed -and $before -and $installed -ne $before){Hr-Add $s $res @{Key="$($h.Id)@$installed";Kind='installed';Harness=$h.Id;Version=$installed;Source='';From=$before;FoundAt=$stamp}}
                    $s.Installed[$h.Id]=@{LastCheck=$stamp;Version=$(if($installed){$installed}else{$before})}
                }
            }
            Hr-SaveState $StateDir $s
        }elseif($Action -eq 'Ack'){
            if(-not $names.ContainsKey($Harness)){throw 'Indica -Harness (claude-code, codex o antigravity) y -Version (X.Y.Z) o -Source (página de documentación).'}
            if($Source){
                $keys=@($s.Novelties|Where-Object {$_.Harness -eq $Harness -and $_.Source -eq $Source -and $_.Kind -eq 'doc'}|ForEach-Object {$_.Key})
                if(-not $keys.Count){throw "No hay cambios pendientes de $Source."}
            }elseif($Version -match $script:versionPattern){$keys=@("$Harness@$Version")}
            else{throw 'Indica -Version (X.Y.Z) o -Source (página de documentación).'}
            foreach($k in $keys){if($k -notin $s.Acked){$s.Acked+=@($k)}}
            Hr-SaveState $StateDir $s;$res.Status='ACKED'
        }
        foreach($n in @($s.Novelties|Where-Object {$_.Key -notin $s.Acked})){$res.Lines+=@(Hr-Line $n $names)}
        if($Action -ne 'Ack' -and @($res.Lines).Count){$res.Status='NOTICE'}
    }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($_.Exception.Message)}
    return [pscustomobject]$res
}Export-ModuleMember -Function Test-AgentOpsFrameworkRepository,Get-AgentOpsHarnessCapabilities,Test-AgentOpsHarnessCapabilities,Get-AgentOpsHarnessPresence,Invoke-AgentOpsHarnessRadar
