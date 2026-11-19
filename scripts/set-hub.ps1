# Switches the skills hub of an existing installation and restarts its watcher.
[CmdletBinding(SupportsShouldProcess=$true)]
param([Parameter(Mandatory=$true)][string]$HubDir,
      [string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'),
      [switch]$NoRestart)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'UpdateCoordinator.psm1') -Force
$result=Set-AgentOpsHubDir -ConfigPath $ConfigPath -HubDir $HubDir -WhatIf:$WhatIfPreference
$restarted=$false
if($result.Status -eq 'RECONFIGURED' -and -not $NoRestart){
    # Only the watcher bound to this exact configuration is restarted; others are left alone.
    $task=Get-ScheduledTask -TaskName 'AgentOpsSkillsWatcher' -ErrorAction SilentlyContinue
    $full=[IO.Path]::GetFullPath($ConfigPath)
    if($task -and @($task.Actions|Where-Object {$_.Arguments -and $_.Arguments.Contains('"'+$full+'"')}).Count){
        Stop-ScheduledTask -TaskName 'AgentOpsSkillsWatcher'
        Start-ScheduledTask -TaskName 'AgentOpsSkillsWatcher'
        $restarted=$true
    }
}
$result|Add-Member -NotePropertyName WatcherRestarted -NotePropertyValue $restarted
$result|ConvertTo-Json -Depth 8
exit $result.Code
