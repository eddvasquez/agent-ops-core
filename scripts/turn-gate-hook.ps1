# End-of-turn hook adapter. Reads the harness's Stop event from stdin, asks the turn gate, and answers in
# that harness's own format. Any error lets the turn end: the floor (pre-commit review and CI) still protects.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('claude','codex','antigravity')][string]$Harness)
$ErrorActionPreference='Stop'
$allow=$(if($Harness -eq 'antigravity'){'{}'}else{''})
try{
    $event=[Console]::In.ReadToEnd()|ConvertFrom-Json
    if($Harness -eq 'antigravity'){$dir=@($event.workspacePaths)[0];$session=[string]$event.conversationId}
    else{$dir=[string]$event.cwd;$session=[string]$event.session_id}
    if(-not $dir){if($allow){$allow};exit 0}
    Import-Module (Join-Path $PSScriptRoot 'TurnGate.psm1') -Force
    $top=(& git -C $dir rev-parse --show-toplevel 2>$null)
    $project=$(if($LASTEXITCODE -eq 0 -and $top){[IO.Path]::GetFullPath(($top|Select-Object -First 1).Trim())}else{$dir})
    $stateDir=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'})
    $gate=Test-AgentOpsTurnGate -ProjectPath $project -StateDir $stateDir -SessionId "$Harness/$session"
    if($gate.Decision -eq 'BLOCK'){
        $decision=$(if($Harness -eq 'antigravity'){'continue'}else{'block'})
        [ordered]@{decision=$decision;reason=$gate.Reason}|ConvertTo-Json -Compress
        exit 0
    }
    if($gate.Status -eq 'UNVERIFIED'){[Console]::Error.WriteLine($gate.Reason)}
}catch{[Console]::Error.WriteLine("Agent Ops: la comprobación al terminar no pudo ejecutarse ($($_.Exception.Message)); el turno puede terminar.")}
if($allow){$allow}
exit 0
