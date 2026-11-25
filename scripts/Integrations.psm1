Set-StrictMode -Version 2
# Integrations (zero configuration). Updating the framework changes its code; this makes every update also reach the
# harnesses the user has: hooks, the Antigravity plugin and the Claude Code permission rules, with no script to run.
# What changes a tool's own configuration (today: the Codex permission profile in config.toml) waits for consent,
# asked once and remembered in consents.json. An outdated bootstrap is reported so the agent can offer to update it.
Import-Module (Join-Path $PSScriptRoot 'HookIO.psm1')
Import-Module (Join-Path $PSScriptRoot 'SecretGuard.psm1')
Import-Module (Join-Path $PSScriptRoot 'SessionStart.psm1')
Import-Module (Join-Path $PSScriptRoot 'AntigravityPlugin.psm1')
$script:utf8=New-Object Text.UTF8Encoding($false)
$script:bootCapability='(?m)^# capability: local-channel-v1\s*$'

function In-Read([string]$path){if([IO.File]::Exists($path)){try{return ([IO.File]::ReadAllText($path)|ConvertFrom-Json)}catch{}};return $null}
function Get-AgentOpsConsent([string]$StateDir,[string]$Name){
    $c=In-Read (Join-Path $StateDir 'consents.json')
    if($c -and $c.PSObject.Properties[$Name]){return [string]$c.$Name.Answer}
    return ''
}
function Set-AgentOpsConsent {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$StateDir,[Parameter(Mandatory=$true)][ValidateSet('codex-profile')][string]$Name,[Parameter(Mandatory=$true)][ValidateSet('yes','no')][string]$Answer)
    $path=Join-Path $StateDir 'consents.json';$c=Read-AgentOpsJsonFile $path
    $c[$Name]=[ordered]@{Answer=$Answer;At=[datetime]::UtcNow.ToString('o')}
    Write-AgentOpsJsonFile $path $c
}
function In-BootstrapState($state){
    try{$coord=Join-Path ([string]$state.Config.InstallRoot) 'scripts/UpdateCoordinator.psm1';if([IO.File]::Exists($coord) -and [IO.File]::ReadAllText($coord) -match $script:bootCapability){return 'OK'};return 'OUTDATED'}catch{return 'UNKNOWN'}
}

# Only the real installation adjusts the real user folder: any other state folder (tests, fixtures) must name its
# own user folder, or nothing is touched.
function Resolve-AgentOpsIntegrationHome {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$StateDir,[string]$HomeDir='',
          [string]$RealStateDir=(Join-Path $env:LOCALAPPDATA 'AgentOps'),[string]$RealHome=$HOME)
    if($HomeDir){return $HomeDir}
    $sep=[char[]]@([IO.Path]::DirectorySeparatorChar,[IO.Path]::AltDirectorySeparatorChar)
    try{if([IO.Path]::GetFullPath($StateDir).TrimEnd($sep) -ieq [IO.Path]::GetFullPath($RealStateDir).TrimEnd($sep)){return $RealHome}}catch{}
    return ''
}
function In-HomeFor([string]$StateDir,[string]$HomeDir){Resolve-AgentOpsIntegrationHome -StateDir $StateDir -HomeDir $HomeDir}

function Sync-AgentOpsIntegrations {
    [CmdletBinding()]
    param([string]$StateDir=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'}),
          [string]$HomeDir='',[scriptblock]$AntigravityValidator)
    $res=[ordered]@{Code=0;Status='UP_TO_DATE';Harnesses=@();Files=@();NeedsConsent=@();Bootstrap='UNKNOWN';Issues=@()}
    $state=In-Read (Join-Path $StateDir 'update-state.json')
    if(-not $state){$res.Status='NOT_INSTALLED';return [pscustomobject]$res}
    $res.Bootstrap=In-BootstrapState $state
    $HomeDir=In-HomeFor $StateDir $HomeDir
    if(-not $HomeDir){$res.Status='ISOLATED';return [pscustomobject]$res}
    $present=@{claude=[IO.Directory]::Exists((Join-Path $HomeDir '.claude'));codex=[IO.Directory]::Exists((Join-Path $HomeDir '.codex'));antigravity=[IO.Directory]::Exists((Join-Path $HomeDir '.gemini/config'))}
    $res.Harnesses=@('claude','codex','antigravity'|Where-Object {$present[$_]})
    $scratch=Join-Path ([IO.Path]::GetTempPath()) ('aoc-integrations-scratch-'+[guid]::NewGuid().ToString('N').Substring(0,10))
    try{
        [IO.Directory]::CreateDirectory($scratch)|Out-Null
        # Absent harnesses get throwaway files: nothing is created for tools the user does not have.
        $codexHome=$(if($env:CODEX_HOME -and $HomeDir -ieq $HOME){$env:CODEX_HOME}else{Join-Path $HomeDir '.codex'})
        $p=@{StateDir=$StateDir
            ClaudeSettingsPath=$(if($present.claude){Join-Path $HomeDir '.claude/settings.json'}else{Join-Path $scratch 'claude.json'})
            CodexHooksPath=$(if($present.codex){Join-Path $codexHome 'hooks.json'}else{Join-Path $scratch 'codex/hooks.json'})
            AntigravityHooksPath=$(if($present.antigravity){Join-Path $HomeDir '.gemini/config/hooks.json'}else{Join-Path $scratch 'agy/hooks.json'})}
        $consent=Get-AgentOpsConsent $StateDir 'codex-profile'
        if($present.codex -and -not $consent){$res.NeedsConsent=@('codex-profile')}
        $changed=@()
        $g=Install-AgentOpsSecretGuard @p -SkipCodexProfile:($consent -ne 'yes');if($g.Code -ne 0){throw ('Credential guard: '+(@($g.Issues) -join '; '))};$changed+=@($g.Files)
        $s=Install-AgentOpsSessionStart @p;if($s.Code -ne 0){throw ('Session hooks: '+(@($s.Issues) -join '; '))};$changed+=@($s.Files)
        if($present.antigravity){
            $a=Install-AgentOpsAntigravityPlugin -StateDir $StateDir -ConfigDir (Join-Path $HomeDir '.gemini/config') -Validator $AntigravityValidator
            if($a.Code -ne 0){$res.Issues=@($res.Issues)+@('Antigravity: '+(@($a.Issues) -join '; '))}elseif($a.Status -ne 'UP_TO_DATE'){$changed+=@($a.Plugin)}
        }
        $res.Files=@($changed|Where-Object {$_ -and -not $_.StartsWith($scratch,[StringComparison]::OrdinalIgnoreCase)}|Select-Object -Unique)
        if($res.Files.Count){$res.Status='SYNCED'}
        $sha=$(if($state.Active -and $state.Active.PSObject.Properties['Sha']){[string]$state.Active.Sha}else{''})
        Write-AgentOpsJsonFile (Join-Path $StateDir 'integrations.json') ([ordered]@{Sha=$sha;At=[datetime]::UtcNow.ToString('o');Status=$res.Status;Harnesses=$res.Harnesses})
    }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($res.Issues)+@($_.Exception.Message)}
    finally{if([IO.Directory]::Exists($scratch)){Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue}}
    return [pscustomobject]$res
}

# Session start: cheap unless the active version changed since the last adjustment.
function Invoke-AgentOpsIntegrationsIfNeeded {
    [CmdletBinding()]
    param([string]$StateDir=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'}),
          [string]$HomeDir='',[scriptblock]$AntigravityValidator)
    $state=In-Read (Join-Path $StateDir 'update-state.json')
    if(-not $state){return [pscustomobject]@{Status='NOT_INSTALLED';NeedsConsent=@();Bootstrap='UNKNOWN';Issues=@()}}
    $HomeDir=In-HomeFor $StateDir $HomeDir
    if(-not $HomeDir){return [pscustomobject]@{Status='ISOLATED';NeedsConsent=@();Bootstrap='UNKNOWN';Issues=@()}}
    $last=In-Read (Join-Path $StateDir 'integrations.json')
    $sha=$(if($state.Active -and $state.Active.PSObject.Properties['Sha']){[string]$state.Active.Sha}else{''})
    if($last -and [string]$last.Sha -eq $sha){
        $codexPending=([IO.Directory]::Exists((Join-Path $HomeDir '.codex')) -and -not (Get-AgentOpsConsent $StateDir 'codex-profile'))
        return [pscustomobject]@{Status='SKIPPED';NeedsConsent=@($(if($codexPending){'codex-profile'}));Bootstrap=(In-BootstrapState $state);Issues=@()}
    }
    return (Sync-AgentOpsIntegrations -StateDir $StateDir -HomeDir $HomeDir -AntigravityValidator $AntigravityValidator)
}

# Updating the bootstrap: always from stable (root of trust), with this installation's real hub and targets and
# without touching the scheduled task; the agent runs it after the user says yes.
function Update-AgentOpsBootstrap {
    [CmdletBinding()]
    param([string]$StateDir=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'}),[scriptblock]$Runner)
    $res=[ordered]@{Code=1;Status='FAILED';Issues=@()}
    $state=In-Read (Join-Path $StateDir 'update-state.json');$watch=In-Read (Join-Path $StateDir 'watch-config.json')
    if(-not $state -or -not $watch){$res.Status='NOT_INSTALLED';return [pscustomobject]$res}
    $installer=Join-Path ([string]$state.Active.Path) 'install.ps1'
    if(-not $Runner){$Runner={param($i,$h,$t) & $i -HubDir $h -Targets $t -SkipTask|Out-Null;$LASTEXITCODE}}
    try{$code=& $Runner $installer ([string]$watch.HubDir) @($watch.Targets);if($code -eq 0 -or $null -eq $code){$res.Code=0;$res.Status='UPDATED'}else{$res.Issues=@("install.ps1 exited with code $code")}}catch{$res.Issues=@($_.Exception.Message)}
    return [pscustomobject]$res
}
Export-ModuleMember -Function Resolve-AgentOpsIntegrationHome,Sync-AgentOpsIntegrations,Invoke-AgentOpsIntegrationsIfNeeded,Update-AgentOpsBootstrap,Get-AgentOpsConsent,Set-AgentOpsConsent
