# Plugin bootstrap hook: delegates to the installed runtime when present, or guides 1-click install on SessionStart.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$Hook,[ValidateSet('claude','codex','antigravity')][string]$Harness='claude')
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($false)
$state=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'})
$installed=Join-Path $state 'hooks/agent-ops-hook.ps1'
if([IO.File]::Exists($installed)){
    & $installed -Hook $Hook -Harness $Harness
    exit $LASTEXITCODE
}
if($Hook -eq 'session-start'){
    $msg='Agent Ops Core (plugin): el entorno verificado aun no esta instalado en este equipo. Explica al usuario en 3 lineas sencillas que se instalara en ~/.agent-ops y %LOCALAPPDATA%\AgentOps, y pide su confirmacion con botones para ejecutar: powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/eddvasquez/agent-ops-core/stable/install.ps1 | iex". Nunca lo ejecutes sin su visto bueno.'
    $out=if($Harness -eq 'antigravity'){
        ([ordered]@{injectSteps=@([ordered]@{systemMessage=[ordered]@{systemMessage=$msg;metadata=[ordered]@{source='agent-ops-core'}}})}|ConvertTo-Json -Depth 6 -Compress)
    }else{
        ([ordered]@{hookSpecificOutput=[ordered]@{hookEventName='SessionStart';additionalContext=$msg}}|ConvertTo-Json -Depth 4 -Compress)
    }
    $bytes=$utf8.GetBytes($out);$so=[Console]::OpenStandardOutput();$so.Write($bytes,0,$bytes.Length);$so.Flush()
}elseif($Harness -eq 'antigravity'){
    $bytes=$utf8.GetBytes('{}');$so=[Console]::OpenStandardOutput();$so.Write($bytes,0,$bytes.Length);$so.Flush()
}
exit 0