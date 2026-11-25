Set-StrictMode -Version 2
# Shared by the harness hook adapters. Harnesses exchange UTF-8 JSON: stdin and stdout are handled as raw
# UTF-8 bytes, never through the console code page (Windows PowerShell would garble accents and break JSON).
$script:utf8=New-Object Text.UTF8Encoding($false)

function Read-AgentOpsHookInput{
    # The launcher may already have read stdin to pre-filter it: it then passes the event in a temporary file.
    $file=$env:AGENT_OPS_HOOK_INPUT_FILE
    if($file -and [IO.File]::Exists($file)){return $script:utf8.GetString([IO.File]::ReadAllBytes($file)).TrimStart([char]0xFEFF)}
    $buffer=New-Object IO.MemoryStream;[Console]::OpenStandardInput().CopyTo($buffer)
    return $script:utf8.GetString($buffer.ToArray()).TrimStart([char]0xFEFF)
}
function Write-AgentOpsHookOutput([string]$Text){
    if(-not $Text){return}
    $bytes=$script:utf8.GetBytes($Text);$out=[Console]::OpenStandardOutput();$out.Write($bytes,0,$bytes.Length);$out.Flush()
}
function Write-AgentOpsHookNote([string]$Text){
    $bytes=$script:utf8.GetBytes($Text+"`n");$err=[Console]::OpenStandardError();$err.Write($bytes,0,$bytes.Length);$err.Flush()
}
# JSON settings files of the harnesses, read as ordered dictionaries so they can be merged and written back.
function ConvertTo-AgentOpsPlain($o){
    if($null -eq $o){return $null}
    if($o -is [Management.Automation.PSCustomObject]){$h=[ordered]@{};foreach($p in $o.PSObject.Properties){$h[$p.Name]=ConvertTo-AgentOpsPlain $p.Value};return $h}
    if($o -is [Collections.IDictionary]){$h=[ordered]@{};foreach($k in $o.Keys){$h[$k]=ConvertTo-AgentOpsPlain $o[$k]};return $h}
    if($o -is [Collections.IEnumerable] -and $o -isnot [string]){return ,@($o|ForEach-Object {ConvertTo-AgentOpsPlain $_})}
    return $o
}
function Read-AgentOpsJsonFile([string]$Path){if([IO.File]::Exists($Path)){ConvertTo-AgentOpsPlain ([IO.File]::ReadAllText($Path)|ConvertFrom-Json)}else{[ordered]@{}}}
function Write-AgentOpsJsonFile([string]$Path,$Value){[IO.Directory]::CreateDirectory((Split-Path $Path))|Out-Null;[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 12),$script:utf8)}
# --- Shared per-user hook launcher: every harness hook calls it; it runs the hook of the active, verified release.
$script:launcher=@'
# agent-ops hook launcher v2. Managed by Agent Ops: runs a hook of the active, verified release.
# secret-guard: ordinary actions are answered here, without loading any module, so they stay fast.
param([Parameter(Mandatory=$true)][string]$Hook,[Parameter(Mandatory=$true)][string]$Harness)
$utf8=New-Object Text.UTF8Encoding($false)
function Out-Hook([string]$t){if($t){$b=$utf8.GetBytes($t);$o=[Console]::OpenStandardOutput();$o.Write($b,0,$b.Length);$o.Flush()}}
$allow=$(if($Harness -eq 'antigravity'){'{"decision":"allow"}'}else{''})
$stateDir=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'})
$buffer=New-Object IO.MemoryStream;[Console]::OpenStandardInput().CopyTo($buffer);$bytes=$buffer.ToArray()
$suspicious='(?i)\.env|secret|credential|\.pem|\.key\b|\.pfx|\.p12|\.jks|keystore|id_(rsa|dsa|ecdsa|ed25519)|google-ads|\.npmrc|\.pypirc|\.netrc|token\.json'
if($Hook -eq 'secret-guard' -and $utf8.GetString($bytes) -notmatch $suspicious){Out-Hook $allow;exit 0}
$frame=$null
try{
    $s=[IO.File]::ReadAllText((Join-Path $stateDir 'update-state.json'))|ConvertFrom-Json
    if($s.Active -and $s.Active.Path){$frame=[string]$s.Active.Path}
    elseif($s.Mode -eq 'LOCAL_DEV' -and $s.Config -and $s.Config.InstallRoot){$frame=[string]$s.Config.InstallRoot}
}catch{}
$script=$(if($frame -and $Hook -match '^[a-z-]+$'){Join-Path $frame "scripts/$Hook-hook.ps1"}else{$null})
if(-not $script -or -not (Test-Path -LiteralPath $script -PathType Leaf)){Out-Hook $allow;exit 0}
# Minimal trace (time, hook, harness; never paths or content), capped at 256 KB.
try{
    $log=Join-Path $stateDir 'hooks/invocations.log'
    if([IO.File]::Exists($log) -and (New-Object IO.FileInfo $log).Length -gt 262144){[IO.File]::Copy($log,"$log.1",$true);[IO.File]::WriteAllText($log,'')}
    [IO.File]::AppendAllText($log,("{0}`t{1}`t{2}`n" -f [datetime]::UtcNow.ToString('o'),$Hook,$Harness))
}catch{}
# The hook reads the event from this temporary file because stdin was already consumed above.
$eventFile=[IO.Path]::GetTempFileName();[IO.File]::WriteAllBytes($eventFile,$bytes);$env:AGENT_OPS_HOOK_INPUT_FILE=$eventFile
$code=0
try{& $script -Harness $Harness;$code=$LASTEXITCODE}finally{[IO.File]::Delete($eventFile)}
exit $code
'@
function Install-AgentOpsHookLauncher([string]$StateDir=(Join-Path $env:LOCALAPPDATA 'AgentOps')){
    $path=Join-Path $StateDir 'hooks/agent-ops-hook.ps1';$text=($script:launcher -replace "`r",'')
    if([IO.File]::Exists($path) -and ([IO.File]::ReadAllText($path) -replace "`r",'').TrimStart([char]0xFEFF) -eq $text){return [pscustomobject]@{Path=$path;Changed=$false}}
    [IO.Directory]::CreateDirectory((Split-Path $path))|Out-Null;[IO.File]::WriteAllText($path,$text,(New-Object Text.UTF8Encoding($true)))
    return [pscustomobject]@{Path=$path;Changed=$true}
}
Export-ModuleMember -Function Read-AgentOpsHookInput,Write-AgentOpsHookOutput,Write-AgentOpsHookNote,ConvertTo-AgentOpsPlain,Read-AgentOpsJsonFile,Write-AgentOpsJsonFile,Install-AgentOpsHookLauncher
