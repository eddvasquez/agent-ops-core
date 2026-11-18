# Windows installer. Also supports the documented irm | iex entry point.
[CmdletBinding(SupportsShouldProcess=$true)]
param(
    [string]$RepoUrl='https://github.com/eddvasquez/agent-ops-core.git',
    [string]$TargetDir=(Join-Path $env:USERPROFILE '.agent-ops'),
    [string]$HubDir=(Join-Path $env:USERPROFILE '.agent-ops-hub'),
    [string[]]$Targets=@((Join-Path $env:USERPROFILE '.gemini/config/skills'),(Join-Path $env:USERPROFILE '.claude/skills'),(Join-Path $env:USERPROFILE '.agents/skills')),
    [string]$StateDir=(Join-Path $env:LOCALAPPDATA 'AgentOps'),
    [switch]$SkipTask,[switch]$DisableWatcher
)
$ErrorActionPreference='Stop'
$installationMutex=$null;$ownsInstallationMutex=$false
try {
    $TargetDir=[IO.Path]::GetFullPath($TargetDir).TrimEnd('\','/')
    if(-not $PSCmdlet.ShouldProcess($TargetDir,'Install/update Agent Ops Core and verified skill distribution')){exit 0}
    $paths=@($TargetDir,$HubDir,$StateDir)+@($Targets)
    $paths=@($paths|ForEach-Object {[IO.Path]::GetFullPath($_).TrimEnd('\','/')})
    for($i=0;$i -lt $paths.Count;$i++) {
        if($paths[$i] -eq [IO.Path]::GetPathRoot($paths[$i]).TrimEnd('\','/')){throw 'A drive root cannot be used as an installation or skill directory.'}
        foreach($protected in @($env:USERPROFILE,$env:WINDIR,$env:ProgramFiles,${env:ProgramFiles(x86)})) {
            if($protected -and ($protected -eq $paths[$i] -or $protected.StartsWith($paths[$i]+'\',[StringComparison]::OrdinalIgnoreCase))){throw 'A protected root cannot be used as an installation or skill directory.'}
        }
        for($j=$i+1;$j -lt $paths.Count;$j++){if($paths[$i] -eq $paths[$j] -or $paths[$i].StartsWith($paths[$j]+'\',[StringComparison]::OrdinalIgnoreCase) -or $paths[$j].StartsWith($paths[$i]+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Installation, hub, replicas and state must be distinct and non-overlapping.'}}
    }
    $installationMutex=New-Object Threading.Mutex($false,('Local\AgentOpsSkillsSync-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
    try{$ownsInstallationMutex=$installationMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$ownsInstallationMutex=$true}
    if(-not $ownsInstallationMutex){Write-Host 'Another skills operation is running.';exit 3}
    # Validate ancestors before Git touches an existing or new installation.
    $parent=$TargetDir
    while($parent){if((Test-Path -LiteralPath $parent) -and ((Get-Item -LiteralPath $parent -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)){throw "Installation path contains a link: $parent"};$parent=[IO.Path]::GetDirectoryName($parent)}
    if(Test-Path -LiteralPath $TargetDir) {
        if(-not (Test-Path -LiteralPath (Join-Path $TargetDir '.git'))){throw 'Installation directory already exists and is not a Git checkout. Choose another -TargetDir.'}
        & git -C $TargetDir diff --quiet
        if($LASTEXITCODE -ne 0){throw 'Tracked local edits found. Commit/review them before updating.'}
        & git -C $TargetDir diff --cached --quiet
        if($LASTEXITCODE -ne 0){throw 'Staged edits found. Commit/review them before updating.'}
        $origin=& git -C $TargetDir remote get-url origin
        if($LASTEXITCODE -ne 0 -or ($origin.TrimEnd('/') -replace '\.git$','') -ne ($RepoUrl.TrimEnd('/') -replace '\.git$','')){throw 'Existing origin differs from -RepoUrl. Refusing to update another repository.'}
        & git -C $TargetDir pull --ff-only
        if($LASTEXITCODE -ne 0){throw 'Git pull failed; no skills were distributed.'}
    } else {
        & git clone -- $RepoUrl $TargetDir
        if($LASTEXITCODE -ne 0){throw 'Git clone failed; no skills were distributed.'}
    }
    $module=Join-Path $TargetDir 'scripts/SkillsSync.psm1'
    if(-not (Test-Path -LiteralPath $module)){throw 'The checkout does not contain the safe synchronization engine. Update/publish the framework code first.'}
    Import-Module $module -Force
    $invoke=@{HubDir=$HubDir;Targets=$Targets;StateDir=$StateDir;FrameworkDir=$TargetDir}
    Get-SkillSyncConfiguration @invoke|Out-Null
    $r=Invoke-SkillSync @invoke -Mode Apply
    if($r.Code -in @(1,3)){throw ("Synchronization code {0}: {1}" -f $r.Code,($r.Issues -join '; '))}
    $configPath=Save-SkillSyncConfiguration @invoke
    if(-not $SkipTask) {
        $manager=Join-Path $TargetDir 'scripts/manage-skills-watcher.ps1'
        if($DisableWatcher){& $manager @invoke -Action Disable}else{& $manager @invoke -Action Enable}
        $name='AgentOpsDailyUpdate';$update=Join-Path $TargetDir 'update.ps1'
        $existing=Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        if($existing -and -not @($existing.Actions|Where-Object {$_.Arguments.Contains('"'+$update+'"')}).Count){throw 'Daily task name belongs to another installation.'}
        $exe=Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'
        $action=New-ScheduledTaskAction -Execute $exe -Argument "-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$update`" -ConfigPath `"$configPath`""
        $trigger=New-ScheduledTaskTrigger -Daily -At 9am
        $principal=New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType Interactive -RunLevel Limited
        $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew
        Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force|Out-Null
    }
    if($r.Code -eq 0){[IO.File]::WriteAllText((Join-Path $TargetDir '.last_update_check'),[datetime]::UtcNow.ToString('o'))}
    Write-Host ("Installation: code={0}; copies={1}; conflicts={2}; pending deletions={3}. Config: {4}" -f $r.Code,$r.Copied,$r.Conflicts.Count,$r.Deletions.Count,$configPath)
    exit $r.Code
} catch {Write-Host ('Installation failed: '+$_.Exception.Message) -ForegroundColor Red;exit 1}
finally{if($ownsInstallationMutex){$installationMutex.ReleaseMutex()};if($installationMutex){$installationMutex.Dispose()}}
