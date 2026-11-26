# Session start hook adapter. Reads the harness's SessionStart event, builds the brief for a project governed
# by Agent Ops Core and answers in that harness's own format. Any error says nothing: the session starts as
# before and AGENTS.md still asks for MODO ENTRADA (the floor).
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('claude','codex','antigravity')][string]$Harness)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SessionStart.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'HookIO.psm1')
$brief=''
try{
    $event=Read-AgentOpsHookInput|ConvertFrom-Json
    if($Harness -eq 'antigravity'){$dir=[string](@($event.workspacePaths)[0]);$source='startup'}
    else{$dir=[string]$event.cwd;$source=$(if($event.PSObject.Properties['source'] -and @('startup','resume','clear','compact','fork') -contains [string]$event.source){[string]$event.source}else{'startup'})}
    if($dir -and [IO.Directory]::Exists($dir)){$brief=Get-AgentOpsSessionBrief -ProjectPath $dir -Source $source -Harness $Harness}
    # The skills watcher must not stay off unnoticed: repair it at every session start (silent unless something happened).
    try{Import-Module (Join-Path $PSScriptRoot 'WatcherGuard.psm1') -Force;$w=Repair-AgentOpsWatcher;if($w.Message -and $brief){$brief+="`n- $($w.Message)"}}catch{}
    # Every update also reaches the user's harnesses (hooks, plugin, permissions) with nothing to run by hand.
    try{
        Import-Module (Join-Path $PSScriptRoot 'Integrations.psm1');$i=Invoke-AgentOpsIntegrationsIfNeeded
        if($brief -and @($i.NeedsConsent) -contains 'codex-profile'){$brief+="`n- Pregunta UNA vez al usuario, con botones y en lenguaje llano: «Para proteger tus contraseñas también en Codex necesito ajustar su configuración (guardo una copia). ¿Lo hago?» y registra la respuesta con & `"`$ActivePath/scripts/integrations.ps1`" -Action Consent -Name codex-profile -Answer yes|no."}
        if($brief -and @($i.NeedsConsent) -contains 'antigravity-permissions'){$brief+="`n- Pregunta UNA vez al usuario, con botones y en lenguaje llano: «Para que Antigravity te pregunte antes de leer tus contraseñas necesito ajustar su configuración (guardo una copia). ¿Lo hago?» y registra la respuesta con & `"`$ActivePath/scripts/integrations.ps1`" -Action Consent -Name antigravity-permissions -Answer yes|no. Si su salida trae AntigravityRestart true, pide al usuario que reinicie Antigravity."}
        if($brief -and $i.PSObject.Properties['AntigravityRestart'] -and $i.AntigravityRestart){$brief+="`n- Dile al usuario que reinicie Antigravity para activar la protección de sus contraseñas."}
        if($brief -and $i.Bootstrap -eq 'OUTDATED'){$brief+="`n- El arranque del marco está desactualizado. Ofrece al usuario actualizarlo tú, sin pasos para él («¿Lo actualizo?»); con un sí: & `"`$ActivePath/scripts/integrations.ps1`" -Action UpdateBootstrap."}
    }catch{}
    # SecretGuard reloads HookIO with -Force, which unloads it here: load it again for the answer.
    Import-Module (Join-Path $PSScriptRoot 'HookIO.psm1') -Force
}catch{Write-AgentOpsHookNote "Agent Ops: el aviso de inicio de sesión no pudo prepararse ($($_.Exception.Message)); sigue AGENTS.md."}
Write-AgentOpsHookOutput (ConvertTo-AgentOpsSessionStartOutput $Harness $brief)
exit 0
