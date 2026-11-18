[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')]
param(
    [ValidateSet('Enable','Disable','Remove','Status')][string]$Action='Status',
    [string]$HubDir=(Join-Path $env:USERPROFILE '.agent-ops-hub'),
    [string[]]$Targets=@((Join-Path $env:USERPROFILE '.gemini/config/skills'),(Join-Path $env:USERPROFILE '.claude/skills'),(Join-Path $env:USERPROFILE '.agents/skills')),
    [string]$StateDir=(Join-Path $env:LOCALAPPDATA 'AgentOps'),
    [string]$FrameworkDir=(Split-Path -Parent $PSScriptRoot)
)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'SkillsSync.psm1') -Force
$configuration=Get-SkillSyncConfiguration -HubDir $HubDir -Targets $Targets -StateDir $StateDir -FrameworkDir $FrameworkDir
$configPath=Join-Path $configuration.StateDir 'watch-config.json'
$taskName='AgentOpsSkillsWatcher'
$watchPath=Join-Path $PSScriptRoot 'watch-skills.ps1'
if(-not $PSCmdlet.ShouldProcess($taskName,$Action)){return}
$existing=Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if($existing -and -not @($existing.Actions|Where-Object {$_.Arguments.Contains('"'+$watchPath+'"') -and $_.Arguments.Contains('"'+$configPath+'"')}).Count){throw 'Scheduled task name belongs to a different configuration; refusing to replace or stop it.'}
switch($Action) {
    'Enable' {
        Save-SkillSyncConfiguration -HubDir $configuration.HubDir -Targets $configuration.Targets -StateDir $configuration.StateDir -FrameworkDir $configuration.FrameworkDir|Out-Null
        $exe=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent().Name
        $taskAction=New-ScheduledTaskAction -Execute $exe -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$watchPath`" -ConfigPath `"$configPath`""
        $trigger=New-ScheduledTaskTrigger -AtLogOn -User $identity
        $principal=New-ScheduledTaskPrincipal -UserId $identity -LogonType Interactive -RunLevel Limited
        $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([timespan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        Register-ScheduledTask -TaskName $taskName -Action $taskAction -Trigger $trigger -Principal $principal -Settings $settings -Force|Out-Null
        if($existing){Stop-ScheduledTask -TaskName $taskName}
        Start-ScheduledTask -TaskName $taskName
    }
    'Disable' {if($existing){Stop-ScheduledTask -TaskName $taskName;Disable-ScheduledTask -TaskName $taskName|Out-Null}}
    'Remove' {if($existing){Stop-ScheduledTask -TaskName $taskName;Unregister-ScheduledTask -TaskName $taskName -Confirm:$false}}
    'Status' {$existing}
}
