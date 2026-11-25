Set-StrictMode -Version 2
# Skills watcher guard. The watcher task (AgentOpsSkillsWatcher) keeps skills synchronised; on this PC it stayed
# disabled from 2026-11-20 to 2026-11-25 without anyone noticing. At session start, if the installation wants it on
# (update-state Config.WatcherEnabled) and nobody switched it off on purpose (watcher-intent.json, written by
# manage-skills-watcher.ps1), a disabled task is re-enabled and started. Never during an activation, which suspends
# it on purpose, and never a task that belongs to another installation.
$script:task='AgentOpsSkillsWatcher'

function Wg-RealScheduler([string]$action,$config){
    if($action -eq 'Get'){
        $t=Get-ScheduledTask -TaskName $script:task -ErrorAction SilentlyContinue
        if(-not $t){return [pscustomobject]@{Present=$false;Enabled=$false;Owned=$false}}
        $entry='"'+(Join-Path $config.InstallRoot 'scripts\watch-entry.ps1')+'"'
        $cfg='"'+(Join-Path $config.StateDir 'watch-config.json')+'"'
        $owned=[bool]@($t.Actions|Where-Object {$_.Arguments -and $_.Arguments.Contains($entry) -and $_.Arguments.Contains($cfg)}).Count
        return [pscustomobject]@{Present=$true;Enabled=($t.State -ne 'Disabled');Owned=$owned}
    }
    if($action -eq 'Enable'){Enable-ScheduledTask -TaskName $script:task|Out-Null;Start-ScheduledTask -TaskName $script:task;return $true}
}

function Repair-AgentOpsWatcher {
    [CmdletBinding()]
    param([string]$StateDir=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'}),[scriptblock]$Scheduler)
    $res=[ordered]@{Status='NOT_INSTALLED';Message=''}
    try{
        $statePath=Join-Path $StateDir 'update-state.json'
        if(-not [IO.File]::Exists($statePath)){return [pscustomobject]$res}
        $s=[IO.File]::ReadAllText($statePath)|ConvertFrom-Json
        $config=$s.Config
        if(-not ($config.PSObject.Properties['WatcherEnabled'] -and $config.WatcherEnabled -eq $true)){$res.Status='OFF_ON_PURPOSE';return [pscustomobject]$res}
        $intent=Join-Path $StateDir 'watcher-intent.json'
        if([IO.File]::Exists($intent)){try{if((([IO.File]::ReadAllText($intent)|ConvertFrom-Json).Enabled) -eq $false){$res.Status='OFF_ON_PURPOSE';return [pscustomobject]$res}}catch{}}
        if([IO.File]::Exists((Join-Path $StateDir 'activation-pending.json'))){$res.Status='ACTIVATION_IN_PROGRESS';return [pscustomobject]$res}
        $cfg=[pscustomobject]@{InstallRoot=[string]$config.InstallRoot;StateDir=$StateDir}
        $call=$(if($Scheduler){$Scheduler}else{{param($a) Wg-RealScheduler $a $cfg}})
        $t=& $call 'Get'
        if(-not $t.Present){$res.Status='MISSING';$res.Message='El vigilante de skills no está instalado como tarea programada: vuelve a ejecutar install.ps1 para registrarlo.';return [pscustomobject]$res}
        if(-not $t.Owned){$res.Status='FOREIGN_TASK';return [pscustomobject]$res}
        if($t.Enabled){$res.Status='OK';return [pscustomobject]$res}
        & $call 'Enable'|Out-Null
        $res.Status='REPAIRED';$res.Message='El vigilante de skills estaba desactivado y se reactivó (sincroniza las skills con el hub). Para apagarlo a propósito: manage-skills-watcher.ps1 -Action Disable.'
    }catch{$res.Status='FAILED';$res.Message="El vigilante de skills está desactivado y no se pudo reactivar ($($_.Exception.Message))."}
    return [pscustomobject]$res
}
Export-ModuleMember -Function Repair-AgentOpsWatcher
