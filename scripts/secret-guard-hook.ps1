# Credential guard adapter (before each tool action). Claude Code: ask; Codex: deny with explanation;
# Antigravity: ask / allow. Any error lets the action through: the pre-commit review still scans for keys.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('claude','codex','antigravity')][string]$Harness)
$ErrorActionPreference='Stop'
# SecretGuard imports HookIO with -Force inside its own scope: load it first, then HookIO for this script.
Import-Module (Join-Path $PSScriptRoot 'SecretGuard.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'HookIO.psm1') -Force
$allow=$(if($Harness -eq 'antigravity'){'{"decision":"allow"}'}else{''})
try{
    $event=Read-AgentOpsHookInput|ConvertFrom-Json
    $d=Get-AgentOpsSecretDecision -Harness $Harness -Event $event
    if($d.Decision -eq 'ALLOW'){Write-AgentOpsHookOutput $allow;exit 0}
    if($Harness -eq 'antigravity'){$out=[ordered]@{decision='ask';reason=$d.Reason}}
    else{$out=[ordered]@{hookSpecificOutput=[ordered]@{hookEventName='PreToolUse';permissionDecision=$(if($d.Decision -eq 'DENY'){'deny'}else{'ask'});permissionDecisionReason=$d.Reason}}}
    Write-AgentOpsHookOutput ($out|ConvertTo-Json -Depth 5 -Compress)
    exit 0
}catch{
    try{Write-AgentOpsHookNote "Agent Ops: la protección de credenciales no pudo ejecutarse ($($_.Exception.Message)); la acción continúa."}catch{}
}
Write-AgentOpsHookOutput $allow
exit 0
