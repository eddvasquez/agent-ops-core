# Skills watcher guard: the watcher must not stay off without anyone noticing. At session start, if the installation
# wants it on and nobody switched it off on purpose (watcher-intent.json), a disabled task is re-enabled and the
# agent is told. Never during an activation (which suspends it on purpose) and never a task of another installation.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/WatcherGuard.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-watcherguard-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
function State([bool]$wanted=$true){
    $s=Join-Path $script:base ('s-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($s)|Out-Null
    [IO.File]::WriteAllText((Join-Path $s 'update-state.json'),(@{SchemaVersion=1;Mode='MANAGED';Config=@{WatcherEnabled=$wanted;InstallRoot='C:\boot'}}|ConvertTo-Json -Depth 4),$utf8)
    return $s
}
# Fake scheduler: records what was asked.
function Fake([bool]$present=$true,[bool]$enabled=$false,[bool]$owned=$true){
    $script:calls=New-Object Collections.Generic.List[string]
    $script:fake=@{Present=$present;Enabled=$enabled;Owned=$owned}
    return {param($action) $script:calls.Add($action)
        if($action -eq 'Get'){return [pscustomobject]$script:fake}
        if($action -eq 'Enable'){$script:fake.Enabled=$true;return $true}}
}

Test 'a disabled watcher that the installation wants on is re-enabled and reported' {
    $s=State;$f=Fake -enabled $false
    $r=Repair-AgentOpsWatcher -StateDir $s -Scheduler $f
    Assert ($r.Status -eq 'REPAIRED' -and $script:calls -contains 'Enable' -and $r.Message -match 'reactiv') ($r|ConvertTo-Json)
}
Test 'an enabled watcher is left alone' {
    $s=State;$f=Fake -enabled $true
    $r=Repair-AgentOpsWatcher -StateDir $s -Scheduler $f
    Assert ($r.Status -eq 'OK' -and $script:calls -notcontains 'Enable') ($r|ConvertTo-Json)
}
Test 'a watcher switched off on purpose stays off' {
    $s=State;[IO.File]::WriteAllText((Join-Path $s 'watcher-intent.json'),'{"Enabled":false,"By":"manage-skills-watcher"}',$utf8)
    $f=Fake -enabled $false
    $r=Repair-AgentOpsWatcher -StateDir $s -Scheduler $f
    Assert ($r.Status -eq 'OFF_ON_PURPOSE' -and $script:calls -notcontains 'Enable') ($r|ConvertTo-Json)
    $s2=State -wanted $false;$f=Fake -enabled $false
    Assert ((Repair-AgentOpsWatcher -StateDir $s2 -Scheduler $f).Status -eq 'OFF_ON_PURPOSE' -and $script:calls -notcontains 'Enable') 'WatcherEnabled=false must be respected'
}
Test 'never during an activation, never a task of another installation' {
    $s=State;[IO.File]::WriteAllText((Join-Path $s 'activation-pending.json'),'{}',$utf8);$f=Fake -enabled $false
    Assert ((Repair-AgentOpsWatcher -StateDir $s -Scheduler $f).Status -eq 'ACTIVATION_IN_PROGRESS' -and $script:calls -notcontains 'Enable') 'Repaired during an activation'
    $s=State;$f=Fake -enabled $false -owned $false
    Assert ((Repair-AgentOpsWatcher -StateDir $s -Scheduler $f).Status -eq 'FOREIGN_TASK' -and $script:calls -notcontains 'Enable') 'Touched a task of another installation'
    $s=State;$f=Fake -present $false
    Assert ((Repair-AgentOpsWatcher -StateDir $s -Scheduler $f).Status -eq 'MISSING' -and $script:calls -notcontains 'Enable') 'Missing task must be reported, not invented'
}
Test 'without an installation or on a broken scheduler it says nothing harmful' {
    $none=Join-Path $script:base 'none';[IO.Directory]::CreateDirectory($none)|Out-Null
    Assert ((Repair-AgentOpsWatcher -StateDir $none -Scheduler (Fake)).Status -eq 'NOT_INSTALLED') 'No installation'
    $s=State;$broken={param($a) throw 'scheduler down'}
    $r=Repair-AgentOpsWatcher -StateDir $s -Scheduler $broken
    Assert ($r.Status -eq 'FAILED' -and $r.Message -match 'no se pudo') ($r|ConvertTo-Json)
}
Test 'the watcher manager records the intent when it disables or enables the task' {
    $t=[IO.File]::ReadAllText((Join-Path $source 'scripts/manage-skills-watcher.ps1'))
    Assert ($t -match "watcher-intent\.json" -and $t -match "Enabled=\`$false" -and $t -match "Enabled=\`$true") 'manage-skills-watcher must write watcher-intent.json on Disable and Enable'
}
Write-Host "Watcher guard: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
