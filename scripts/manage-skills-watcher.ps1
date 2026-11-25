[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')]
param(
    [ValidateSet('Enable','Disable','Remove','Status')][string]$Action='Status',
    [string]$HubDir=(Join-Path $env:USERPROFILE '.agent-ops-hub'),
    [string[]]$Targets=@((Join-Path $env:USERPROFILE '.gemini/config/skills'),(Join-Path $env:USERPROFILE '.claude/skills'),(Join-Path $env:USERPROFILE '.agents/skills')),
    [string]$StateDir=(Join-Path $env:LOCALAPPDATA 'AgentOps'),
    [string]$FrameworkDir='',[switch]$NoStart
)
$ErrorActionPreference='Stop'
if(-not $PSBoundParameters.ContainsKey('FrameworkDir')){$FrameworkDir=Split-Path -Parent $PSScriptRoot}
$configFile=Join-Path $StateDir 'watch-config.json'
if(-not $PSBoundParameters.ContainsKey('FrameworkDir') -and [IO.File]::Exists((Join-Path $StateDir 'update-state.json')) -and -not $NoStart){
    $stored=Get-Content -LiteralPath $configFile -Raw|ConvertFrom-Json
    if(-not $PSBoundParameters.ContainsKey('HubDir')){$HubDir=[string]$stored.HubDir}
    if(-not $PSBoundParameters.ContainsKey('Targets')){$Targets=[string[]]$stored.Targets}
    Import-Module (Join-Path $PSScriptRoot 'UpdateCoordinator.psm1') -Force
    $FrameworkDir=(Get-AgentOpsActiveRelease -ConfigPath $configFile).Path
}
$managementEngine=Import-Module (Join-Path $PSScriptRoot 'SkillsSync.psm1') -Force -PassThru
$configuration=& $managementEngine {param($h,$t,$d,$f) Get-SkillSyncConfiguration -HubDir $h -Targets $t -StateDir $d -FrameworkDir $f} $HubDir $Targets $StateDir $FrameworkDir
$configPath=Join-Path $configuration.StateDir 'watch-config.json'
$taskName='AgentOpsSkillsWatcher'
$watchPath=Join-Path $PSScriptRoot 'watch-entry.ps1'
$legacyWatchPath=Join-Path $PSScriptRoot 'watch-skills.ps1'
if(-not $PSCmdlet.ShouldProcess($taskName,$Action)){return}
$existing=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if($existing -and -not @($existing.Actions|Where-Object {($_.Arguments.Contains('"'+$watchPath+'"') -or $_.Arguments.Contains('"'+$legacyWatchPath+'"')) -and $_.Arguments.Contains('"'+$configPath+'"')}).Count){throw 'Scheduled task name belongs to a different configuration; refusing to replace or stop it.'}
switch($Action) {
    'Enable' {
        [IO.Directory]::CreateDirectory($StateDir)|Out-Null;[IO.File]::WriteAllText((Join-Path $StateDir 'watcher-intent.json'),(@{Enabled=$true;By='manage-skills-watcher';At=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json))
        & $managementEngine {param($c) Save-SkillSyncConfiguration -HubDir $c.HubDir -Targets $c.Targets -StateDir $c.StateDir -FrameworkDir $c.FrameworkDir} $configuration|Out-Null
        $exe=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
        $taskAction=New-ScheduledTaskAction -Execute $exe -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watchPath`" -ConfigPath `"$configPath`""
        $trigger=New-ScheduledTaskTrigger -AtLogOn -User $identity
        $principal=New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
        $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([timespan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Force|Out-Null
        if($existing){Stop-ScheduledTask -TaskName $taskName}
        if(-not $NoStart){Start-ScheduledTask -TaskName $taskName}
    }
    # The intent is recorded so the session-start guard keeps a watcher switched off on purpose off (WatcherGuard.psm1).
    'Disable' {if($existing){Stop-ScheduledTask -TaskName $taskName;Disable-ScheduledTask -TaskName $taskName|Out-Null};[IO.Directory]::CreateDirectory($StateDir)|Out-Null;[IO.File]::WriteAllText((Join-Path $StateDir 'watcher-intent.json'),(@{Enabled=$false;By='manage-skills-watcher';At=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json))}
    'Remove' {if($existing){Stop-ScheduledTask -TaskName $taskName;Unregister-ScheduledTask -TaskName $taskName -Confirm:$false}}
    'Status' {$existing}
}
