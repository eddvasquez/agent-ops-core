# Installs a stable bootstrap, then an immutable, CI-verified runtime.
# Supports the documented irm | iex entry point (no local files needed first).
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$RepoUrl='https://github.com/eddvasquez/agent-ops-core.git',
    [string]$TargetDir=(Join-Path $env:USERPROFILE '.agent-ops'),
    [string]$HubDir=(Join-Path $env:USERPROFILE '.agent-ops-hub'),
    [string[]]$Targets=@((Join-Path $env:USERPROFILE '.gemini/config/skills'),(Join-Path $env:USERPROFILE '.claude/skills'),(Join-Path $env:USERPROFILE '.agents/skills')),
    [string]$StateDir=(Join-Path $env:LOCALAPPDATA 'AgentOps'),[string]$RuntimeDir='',
    [switch]$SkipTask,[switch]$DisableWatcher,[switch]$LocalDevelopment
)
$ErrorActionPreference='Stop';$updateLock=$null;$syncLock=$null;$updateOwned=$false;$syncOwned=$false
try{
    if(-not $RuntimeDir){$RuntimeDir=$StateDir+'-runtime'}
    $TargetDir=[IO.Path]::GetFullPath($TargetDir).TrimEnd('\','/')
    # Invoke-Expression does not bind an advanced-script cmdlet context.
    if($PSCmdlet){
        if(-not $PSCmdlet.ShouldProcess($TargetDir,'Install stable bootstrap and verified runtime')){exit 0}
    }elseif($WhatIfPreference){Write-Host ('What if: install verified runtime at '+$TargetDir);exit 0}
    if($RepoUrl -match '^https://'){$uri=[uri]$RepoUrl;if($uri.UserInfo -or $uri.Query -or $uri.Fragment){throw 'Do not embed credentials in repository URLs.'}}
    elseif(-not $LocalDevelopment -or -not [IO.Path]::IsPathRooted($RepoUrl)){throw 'Managed installs require HTTPS; local sources require explicit -LocalDevelopment.'}
    $paths=@($TargetDir,$StateDir,$RuntimeDir,$HubDir)+@($Targets)
    $paths=@($paths|ForEach-Object {[IO.Path]::GetFullPath($_).TrimEnd('\','/')})
    for($i=0;$i -lt $paths.Count;$i++){
        if($paths[$i] -eq [IO.Path]::GetPathRoot($paths[$i]).TrimEnd('\','/')){throw 'Drive roots cannot be installation/data directories.'}
        foreach($protected in @($env:USERPROFILE,$env:WINDIR,$env:ProgramFiles,${env:ProgramFiles(x86)})){
            if($protected -and ($protected -eq $paths[$i] -or $protected.StartsWith($paths[$i]+'\',[StringComparison]::OrdinalIgnoreCase))){throw 'Protected root selected.'}
        }
        $parent=$paths[$i]
        while($parent){
            if((Test-Path -LiteralPath $parent) -and ((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Installation/data path contains a link.'}
            $parent=[IO.Path]::GetDirectoryName($parent)
        }
        for($j=$i+1;$j -lt $paths.Count;$j++){if($paths[$i] -eq $paths[$j] -or $paths[$i].StartsWith($paths[$j]+'\',[StringComparison]::OrdinalIgnoreCase) -or $paths[$j].StartsWith($paths[$i]+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Bootstrap, runtime, state, hub and replicas must not overlap.'}}
    }
    $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $updateLock=New-Object Threading.Mutex($false,('Local\AgentOpsUpdate-'+$sid))
    try{$updateOwned=$updateLock.WaitOne(0)}catch [Threading.AbandonedMutexException]{$updateOwned=$true}
    if(-not $updateOwned){Write-Host 'Another update is running.';exit 3}
    $syncLock=New-Object Threading.Mutex($false,('Local\AgentOpsSkillsSync-'+$sid))
    try{$syncOwned=$syncLock.WaitOne(0)}catch [Threading.AbandonedMutexException]{$syncOwned=$true}
    if(-not $syncOwned){Write-Host 'Another synchronization is running.';exit 3}
    if(Test-Path -LiteralPath $TargetDir){
        if(-not [IO.Directory]::Exists((Join-Path $TargetDir '.git'))){throw 'Existing target is not a standalone Git checkout; it is never deleted or replaced.'}
        & git -C $TargetDir diff --quiet;if($LASTEXITCODE -ne 0){throw 'Tracked local edits found; review before installing.'}
        & git -C $TargetDir diff --cached --quiet;if($LASTEXITCODE -ne 0){throw 'Staged local edits found; review before installing.'}
        $origin=& git -C $TargetDir remote get-url origin
        if($LASTEXITCODE -ne 0 -or ($origin.TrimEnd('/') -replace '\.git$','') -ne ($RepoUrl.TrimEnd('/') -replace '\.git$','')){throw 'Existing origin differs from the requested source.'}
        if($LocalDevelopment){& git -C $TargetDir pull --ff-only;if($LASTEXITCODE -ne 0){throw 'Explicit development update failed.'}}
        else{
            & git -C $TargetDir fetch origin refs/heads/stable:refs/remotes/origin/stable
            if($LASTEXITCODE -ne 0){throw 'Stable channel unavailable; bootstrap preserved.'}
            & git -C $TargetDir merge-base --is-ancestor HEAD origin/stable
            if($LASTEXITCODE -ne 0){throw 'Installed bootstrap is ahead/diverged; review instead of downgrading or forcing it.'}
            & git -C $TargetDir checkout --detach origin/stable
            if($LASTEXITCODE -ne 0){throw 'Stable checkout failed; no forced checkout was attempted.'}
        }
    }else{
        if($LocalDevelopment){& git clone -- $RepoUrl $TargetDir}else{& git clone --branch stable --single-branch -- $RepoUrl $TargetDir}
        if($LASTEXITCODE -ne 0){throw 'Clone failed; no skills were deployed.'}
    }
    $module=Join-Path $TargetDir 'scripts/UpdateCoordinator.psm1'
    if(-not [IO.File]::Exists($module)){throw 'Stable bootstrap is not available yet. Wait for the verified release; no skills were changed.'}
    Import-Module $module -Force
    Import-Module (Join-Path $TargetDir 'scripts/SkillsSync.psm1') -Force
    $configPath=Join-Path $StateDir 'watch-config.json'
    $frame=$TargetDir
    if([IO.File]::Exists($configPath)){$frame=(Get-Content -LiteralPath $configPath -Raw|ConvertFrom-Json).FrameworkDir}
    $watcherEnabled=-not $SkipTask -and -not $DisableWatcher
    $settingsPath=Join-Path $StateDir 'update-state.json'
    if($SkipTask -and [IO.File]::Exists($settingsPath)){
        $saved=(Get-Content -LiteralPath $settingsPath -Raw|ConvertFrom-Json).Config.WatcherEnabled
        if($saved -isnot [bool]){throw 'Invalid saved watcher preference; review the installation state.'}
        $watcherEnabled=$saved
    }
    if(-not $SkipTask){
        & (Join-Path $TargetDir 'scripts/manage-skills-watcher.ps1') -HubDir $HubDir -Targets $Targets -StateDir $StateDir -FrameworkDir $frame -Action Enable -NoStart
        if($DisableWatcher){& (Join-Path $TargetDir 'scripts/manage-skills-watcher.ps1') -HubDir $HubDir -Targets $Targets -StateDir $StateDir -FrameworkDir $frame -Action Disable}
    }
    $r=Initialize-AgentOpsUpdate -InstallRoot $TargetDir -RepoUrl $RepoUrl -StateDir $StateDir -RuntimeDir $RuntimeDir -HubDir $HubDir -Targets $Targets -WatcherEnabled $watcherEnabled -LocalDevelopment:$LocalDevelopment
    if($LocalDevelopment -and $r.Code -eq 0){
        $sync=Invoke-SkillSync -HubDir $HubDir -Targets $Targets -StateDir $StateDir -FrameworkDir $TargetDir -Mode Apply
        if($sync.Code -ne 0){$r.Code=$sync.Code;$r.Issues=@($sync.Issues)}
    }elseif($r.Code -eq 0 -and $r.CandidateSha -and $r.Status -in @('UPDATE_AVAILABLE','READY_NEXT_SESSION')){
        # Running the installer explicitly is an installation decision, not a session check.
        $r=Invoke-AgentOpsUpdate -ConfigPath $configPath -Action Apply -CandidateSha $r.CandidateSha -SessionId ('install-'+[guid]::NewGuid().ToString('N'))
    }
    if(-not $SkipTask){
        if($watcherEnabled -and ($r.ActivePath -or $LocalDevelopment)){
            & (Join-Path $TargetDir 'scripts/manage-skills-watcher.ps1') -HubDir $HubDir -Targets $Targets -StateDir $StateDir -Action Enable
        }elseif(-not $r.ActivePath -and -not $LocalDevelopment){
            & (Join-Path $TargetDir 'scripts/manage-skills-watcher.ps1') -HubDir $HubDir -Targets $Targets -StateDir $StateDir -FrameworkDir $frame -Action Disable
        }
        $name='AgentOpsDailyUpdate';$update=Join-Path $TargetDir 'update.ps1'
        $existing=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        if($existing -and -not @($existing.Actions|Where-Object {$_.Arguments.Contains('"'+$update+'"')}).Count){throw 'Daily task belongs to another installation.'}
        $exe=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $action=New-ScheduledTaskAction -Execute $exe -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$update`" -Action Check -ConfigPath `"$configPath`""
        $trigger=New-ScheduledTaskTrigger -Daily -At 9am
        $principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
        $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force|Out-Null
    }
    # Zero configuration: the new installation also reaches the harnesses present (hooks, plugin, permissions),
    # from the active release; never blocks the installation.
    if($r.Code -eq 0 -and $r.PSObject.Properties['ActivePath'] -and $r.ActivePath){
        $integrations=Join-Path $r.ActivePath 'scripts/Integrations.psm1'
        if([IO.File]::Exists($integrations)){
            try{Import-Module $integrations -Force;$i=Sync-AgentOpsIntegrations -StateDir $StateDir;$r|Add-Member -NotePropertyName Integrations -NotePropertyValue $i -Force}
            catch{$r|Add-Member -NotePropertyName Integrations -NotePropertyValue ([pscustomobject]@{Status='FAILED';Issues=@($_.Exception.Message)}) -Force}
        }
    }
    $r|ConvertTo-Json -Depth 20
    exit $r.Code
}catch{Write-Host ('Installation failed: '+$_.Exception.Message) -ForegroundColor Red;exit 1}
finally{if($syncOwned){$syncLock.ReleaseMutex()};if($syncLock){$syncLock.Dispose()};if($updateOwned){$updateLock.ReleaseMutex()};if($updateLock){$updateLock.Dispose()}}
