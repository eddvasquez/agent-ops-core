# Integrations of the framework in the user's harnesses (JSON for the assistant).
#   -Action Status            what is installed, pending consents and bootstrap state (adjusts if the version changed)
#   -Action Sync              adjust now (idempotent)
#   -Action Consent -Name codex-profile -Answer yes|no   record the user's decision (asked once)
#   -Action UpdateBootstrap   update the bootstrap from stable with this installation's hub and targets (after a yes)
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('Status','Sync','Consent','UpdateBootstrap')][string]$Action,
      [ValidateSet('codex-profile','antigravity-permissions')][string]$Name='codex-profile',[ValidateSet('yes','no')][string]$Answer='')
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Integrations.psm1') -Force
$state=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'})
switch($Action){
    'Status'{$r=Invoke-AgentOpsIntegrationsIfNeeded -StateDir $state}
    'Sync'{$r=Sync-AgentOpsIntegrations -StateDir $state}
    'Consent'{
        if(-not $Answer){throw 'Pass -Answer yes or no.'}
        Set-AgentOpsConsent -StateDir $state -Name $Name -Answer $Answer
        $r=Sync-AgentOpsIntegrations -StateDir $state
    }
    'UpdateBootstrap'{$r=Update-AgentOpsBootstrap -StateDir $state}
}
$r|ConvertTo-Json -Depth 5
exit $(if($r.PSObject.Properties['Code']){$r.Code}else{0})
