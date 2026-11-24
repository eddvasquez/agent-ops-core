# End-of-turn hook adapter. Reads the harness's Stop event from stdin, asks the turn gate, and answers in
# that harness's own format. Any error lets the turn end: the floor (pre-commit review and CI) still protects.
# Harnesses exchange UTF-8: stdin and stdout are handled as raw UTF-8 bytes, never through the console code
# page (Windows PowerShell would otherwise garble accents and break the JSON).
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('claude','codex','antigravity')][string]$Harness)
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($false)
function Read-HookInput{
    $buffer=New-Object IO.MemoryStream;[Console]::OpenStandardInput().CopyTo($buffer)
    return $utf8.GetString($buffer.ToArray()).TrimStart([char]0xFEFF)
}
function Write-HookOutput([string]$text){
    if(-not $text){return}
    $bytes=$utf8.GetBytes($text);$out=[Console]::OpenStandardOutput();$out.Write($bytes,0,$bytes.Length);$out.Flush()
}
function Write-HookNote([string]$text){
    $bytes=$utf8.GetBytes($text+"`n");$err=[Console]::OpenStandardError();$err.Write($bytes,0,$bytes.Length);$err.Flush()
}
$allow=$(if($Harness -eq 'antigravity'){'{}'}else{''})
try{
    $event=Read-HookInput|ConvertFrom-Json
    if($Harness -eq 'antigravity'){$dir=@($event.workspacePaths)[0];$session=[string]$event.conversationId}
    else{$dir=[string]$event.cwd;$session=[string]$event.session_id}
    if(-not $dir){Write-HookOutput $allow;exit 0}
    Import-Module (Join-Path $PSScriptRoot 'TurnGate.psm1') -Force
    $top=(& git -C $dir rev-parse --show-toplevel 2>$null)
    $project=$(if($LASTEXITCODE -eq 0 -and $top){[IO.Path]::GetFullPath(($top|Select-Object -First 1).Trim())}else{$dir})
    $stateDir=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'})
    $gate=Test-AgentOpsTurnGate -ProjectPath $project -StateDir $stateDir -SessionId "$Harness/$session"
    if($gate.Decision -eq 'BLOCK'){
        $decision=$(if($Harness -eq 'antigravity'){'continue'}else{'block'})
        Write-HookOutput ([ordered]@{decision=$decision;reason=$gate.Reason}|ConvertTo-Json -Compress)
        exit 0
    }
    if($gate.Status -eq 'UNVERIFIED'){Write-HookNote $gate.Reason}
}catch{Write-HookNote "Agent Ops: la comprobación al terminar no pudo ejecutarse ($($_.Exception.Message)); el turno puede terminar."}
Write-HookOutput $allow
exit 0