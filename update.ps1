[CmdletBinding(SupportsShouldProcess=$true)]
param([switch]$Force,[string]$ConfigPath=(Join-Path $env:LOCALAPPDATA 'AgentOps/watch-config.json'))
$ErrorActionPreference='Stop'
$updateMutex=$null;$ownsUpdateMutex=$false
try {
    $cfg=Get-Content -LiteralPath $ConfigPath -Raw|ConvertFrom-Json
    $repoDir=[IO.Path]::GetFullPath([string]$cfg.FrameworkDir)
    if(-not $PSCmdlet.ShouldProcess($repoDir,'Update framework and reconcile skills')){exit 0}
    Import-Module (Join-Path $repoDir 'scripts/SkillsSync.psm1') -Force
    $invoke=@{HubDir=[string]$cfg.HubDir;Targets=[string[]]$cfg.Targets;StateDir=[string]$cfg.StateDir;FrameworkDir=$repoDir}
    Get-SkillSyncConfiguration @invoke|Out-Null
    $updateMutex=New-Object Threading.Mutex($false,('Local\AgentOpsSkillsSync-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value))
    try{$ownsUpdateMutex=$updateMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$ownsUpdateMutex=$true}
    if(-not $ownsUpdateMutex){Write-Host 'Another skills operation is running.';exit 3}
    $timestamp=Join-Path $repoDir '.last_update_check';$checkGit=$true
    if(-not $Force -and (Test-Path -LiteralPath $timestamp)) {
        $last=[datetime]::Parse([IO.File]::ReadAllText($timestamp),[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)
        $checkGit=([datetime]::UtcNow-$last.ToUniversalTime()).TotalHours -ge 24
    }
    if($checkGit) {
        & git -C $repoDir diff --quiet
        if($LASTEXITCODE -ne 0){throw 'Tracked local edits found. Refusing automatic Git update.'}
        & git -C $repoDir diff --cached --quiet
        if($LASTEXITCODE -ne 0){throw 'Staged local edits found. Refusing automatic Git update.'}
        & git -C $repoDir pull --ff-only
        if($LASTEXITCODE -ne 0){throw 'Git pull failed; update not marked successful.'}
        Import-Module (Join-Path $repoDir 'scripts/SkillsSync.psm1') -Force
    }
    # Always reconcile local edits, even if the Git interval has not elapsed.
    $r=Invoke-SkillSync @invoke -Mode Apply
    if($r.Code -eq 0 -and $checkGit){[IO.File]::WriteAllText($timestamp,[datetime]::UtcNow.ToString('o'))}
    Write-Host ("Update: code={0}; copies={1}; conflicts={2}; pending deletions={3}" -f $r.Code,$r.Copied,$r.Conflicts.Count,$r.Deletions.Count)
    foreach($issue in $r.Issues){Write-Host $issue -ForegroundColor Red}
    exit $r.Code
}catch{Write-Host ('Update failed: '+$_.Exception.Message) -ForegroundColor Red;exit 1}
finally{if($ownsUpdateMutex){$updateMutex.ReleaseMutex()};if($updateMutex){$updateMutex.Dispose()}}
