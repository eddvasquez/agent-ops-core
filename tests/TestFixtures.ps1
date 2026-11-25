# Shared by the test suites (dot-sourced). Deletes a suite's fixtures folder once the suite has passed.
# Safety: only an aoc-* folder directly under %TEMP% is ever removed; anything else is left untouched.
function Remove-TestFixtures([string]$Path){
    if(-not $Path){return}
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    if((Split-Path -Parent $full) -ne $temp -or (Split-Path -Leaf $full) -notlike 'aoc-*' -or -not [IO.Directory]::Exists($full)){return}
    # Git marks pack files read-only; clear that so the folder can go.
    Get-ChildItem -LiteralPath $full -Recurse -Force -File -ErrorAction SilentlyContinue|ForEach-Object {if($_.IsReadOnly){$_.IsReadOnly=$false}}
    Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
}

# Leftovers kept by failed runs are useful only while the failure is being investigated: after 48 h they go.
# Runs in progress are recent, so they are never touched; nothing without the aoc- prefix is touched either.
function Clear-StaleTestFixtures([int]$OlderThanHours=48){
    $limit=(Get-Date).AddHours(-$OlderThanHours)
    foreach($d in @(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'aoc-*' -ErrorAction SilentlyContinue)){
        if($d.CreationTime -lt $limit -and $d.LastWriteTime -lt $limit){Remove-TestFixtures $d.FullName}
    }
}
Clear-StaleTestFixtures
# Locks: every suite gets its own namespace, so it never waits on (or blocks) this computer's real installation.
# Real processes never set AGENT_OPS_LOCK_NAMESPACE, so their lock names stay exactly as before.
$env:AGENT_OPS_LOCK_NAMESPACE='tests-'+[guid]::NewGuid().ToString('N').Substring(0,12)

# Holds a lock with its real installation name from another process (in the same thread Windows would let the
# suite take it again), returning once it is held. Stop it with Stop-HeldRealLock.
function Start-HeldRealLock([string]$Name){
    $ready=Join-Path ([IO.Path]::GetTempPath()) ('aoc-lock-'+[guid]::NewGuid().ToString('N')+'.ready')
    $real='Local\AgentOps'+$Name+'-'+[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $job=Start-Job -ArgumentList $real,$ready -ScriptBlock {
        param($name,$ready)
        $m=New-Object Threading.Mutex($false,$name);$null=$m.WaitOne()
        [IO.File]::WriteAllText($ready,'held')
        Start-Sleep -Seconds 120
        $m.ReleaseMutex()
    }
    for($i=0;$i -lt 300 -and -not [IO.File]::Exists($ready);$i++){Start-Sleep -Milliseconds 100}
    if(-not [IO.File]::Exists($ready)){Stop-Job $job;Remove-Job $job -Force;throw "Could not hold the real $Name lock."}
    Remove-Item -LiteralPath $ready -Force
    return $job
}
function Stop-HeldRealLock($Job){if($Job){Stop-Job $Job -ErrorAction SilentlyContinue;Remove-Job $Job -Force -ErrorAction SilentlyContinue}}
# Shards: -Shard 'k/n' runs only the k-th of n parts of a suite (tests are dealt round-robin by declaration order),
# so a slow suite can run as n processes at once. No shard: every test runs.
function Test-InTestShard([int]$Index,[string]$Shard){
    if(-not $Shard){return $true}
    if($Shard -notmatch '^([1-9][0-9]*)/([1-9][0-9]*)$' -or [int]$Matches[1] -gt [int]$Matches[2]){throw "Invalid shard '$Shard': use k/n with 1 <= k <= n."}
    return ((($Index-1) % [int]$Matches[2]) -eq ([int]$Matches[1]-1))
}
