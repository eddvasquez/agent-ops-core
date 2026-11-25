# Codex permission request hook: runs only when Codex is about to ask for approval (for example to run outside the
# sandbox). A request that names a credentials file is denied with the same explanation as before each action, so an
# escalation can never bypass the native profile that denies reading private keys. Anything else: no decision, the
# user's normal approval goes on. Never allows on the user's behalf. Any error: no decision.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('codex')][string]$Harness)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SecretGuard.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'HookIO.psm1') -Force
try{
    $event=Read-AgentOpsHookInput|ConvertFrom-Json
    $d=Get-AgentOpsSecretDecision -Harness codex -Event $event
    if($d.Decision -eq 'DENY'){
        Write-AgentOpsHookOutput ([ordered]@{hookSpecificOutput=[ordered]@{hookEventName='PermissionRequest';decision=[ordered]@{behavior='deny';message=$d.Reason}}}|ConvertTo-Json -Depth 5 -Compress)
    }
}catch{try{Write-AgentOpsHookNote "Agent Ops: la comprobación de la petición de permiso no pudo ejecutarse ($($_.Exception.Message)); decide el usuario."}catch{}}
exit 0
