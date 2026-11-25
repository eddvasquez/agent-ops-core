# Waiting for GitHub without blocking: one call reports how the tests of a commit ended (green, red, timeout or
# offline). The agent starts it in the background and keeps working. The GitHub API and the pause are injected,
# so these tests use no network and do not really wait.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/CIWait.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-waitci-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
$sha='a'*40
function Run($id,$status,$conclusion){[pscustomobject]@{id=$id;head_sha=$sha;path='.github/workflows/windows-tests.yml';status=$status;conclusion=$conclusion;html_url="https://github.com/o/r/actions/runs/$id";run_started_at='2026-11-25T10:00:00Z';updated_at='2026-11-25T10:03:10Z'}}
function Job($name,$conclusion,$s){[pscustomobject]@{name=$name;conclusion=$conclusion;started_at='2026-11-25T10:00:00Z';completed_at=('2026-11-25T10:{0:00}:{1:00}Z' -f [math]::Floor($s/60),($s%60))}}
# A fake API: each call to the runs URL returns the next state; the jobs URL returns the jobs.
function Fake($states,$jobs){
    $script:calls=New-Object Collections.Generic.List[string];$script:queue=New-Object Collections.Queue;foreach($x in $states){$script:queue.Enqueue($x)}
    $script:jobs=$jobs
    return {param($url) $script:calls.Add($url)
        if($url -match '/jobs'){return [pscustomobject]@{jobs=@($script:jobs)}}
        $next=$(if($script:queue.Count -gt 1){$script:queue.Dequeue()}else{$script:queue.Peek()})
        if($next -is [string] -and $next -eq 'throw'){throw 'boom ghp_FAKESECRET123'}
        return [pscustomobject]@{workflow_runs=@($next|Where-Object {$_})}}
}
$noSleep={param($s) $script:slept+=$s}

Test 'waits while the run is in progress and reports a green run with each job' {
    $script:slept=0
    $f=Fake @((Run 1 'in_progress' $null),(Run 1 'completed' 'success')) @((Job 'integration (pwsh)' 'success' 117),(Job 'test (pwsh)' 'success' 3),(Job 'promote' 'success' 5))
    $r=Wait-AgentOpsCI -Repository 'o/r' -Sha $sha -Fetch $f -Sleep $noSleep -IntervalSeconds 30 -TimeoutMinutes 5
    Assert ($r.Code -eq 0 -and $r.Status -eq 'COMPLETED' -and $r.Conclusion -eq 'success') ($r|ConvertTo-Json -Depth 5)
    Assert (@($r.Jobs).Count -eq 3 -and @($r.Jobs|Where-Object {$_.Name -eq 'integration (pwsh)'})[0].Seconds -eq 117) ($r.Jobs|ConvertTo-Json)
    Assert ($r.Promoted -eq $true -and $r.Url -match '/actions/runs/1$') 'Promotion or link missing'
    Assert ($script:slept -eq 30) "Expected one pause of 30 s, got $script:slept"
    Assert ($script:calls[0] -match '^https://api\.github\.com/repos/o/r/actions/runs\?head_sha=a{40}') $script:calls[0]
}
Test 'a red run says which jobs failed' {
    $f=Fake @((Run 2 'completed' 'failure')) @((Job 'governance (powershell)' 'failure' 162),(Job 'coordinator-1 (pwsh)' 'success' 113),(Job 'promote' 'skipped' 0))
    $r=Wait-AgentOpsCI -Repository 'o/r' -Sha $sha -Fetch $f -Sleep $noSleep
    Assert ($r.Code -eq 1 -and $r.Conclusion -eq 'failure' -and (@($r.Failed) -join ',') -eq 'governance (powershell)' -and $r.Promoted -eq $false) ($r|ConvertTo-Json -Depth 5)
}
Test 'a run that is not created yet is waited for' {
    $script:slept=0
    $f=Fake @($null,(Run 3 'completed' 'success')) @((Job 'promote' 'success' 5))
    $r=Wait-AgentOpsCI -Repository 'o/r' -Sha $sha -Fetch $f -Sleep $noSleep -IntervalSeconds 20
    Assert ($r.Code -eq 0 -and $script:slept -eq 20) ($r|ConvertTo-Json -Depth 5)
}
Test 'a run that never ends gives up at the deadline with code 2' {
    $f=Fake @((Run 4 'in_progress' $null)) @()
    $r=Wait-AgentOpsCI -Repository 'o/r' -Sha $sha -Fetch $f -Sleep $noSleep -IntervalSeconds 30 -TimeoutMinutes 1
    Assert ($r.Code -eq 2 -and $r.Status -eq 'TIMEOUT' -and $script:calls.Count -eq 3) ("calls=$($script:calls.Count) "+($r|ConvertTo-Json -Depth 5))
}
Test 'without network it reports offline and never repeats error text (a token could be in it)' {
    $env:GITHUB_TOKEN='ghp_FAKESECRET123'
    try{
        $f=Fake @('throw') @()
        $r=Wait-AgentOpsCI -Repository 'o/r' -Sha $sha -Fetch $f -Sleep $noSleep -IntervalSeconds 30 -TimeoutMinutes 1
        $json=$r|ConvertTo-Json -Depth 5
        Assert ($r.Code -eq 3 -and $r.Status -eq 'OFFLINE') $json
        Assert ($json -notmatch 'FAKESECRET') 'Error text leaked into the result'
    }finally{Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue}
}
Test 'repository and commit are validated before any call' {
    $f=Fake @((Run 5 'completed' 'success')) @()
    foreach($bad in @(@{Repository='o/r';Sha='abc'},@{Repository='not a repo';Sha=$sha},@{Repository='o/r/x';Sha=$sha})){
        $r=Wait-AgentOpsCI @bad -Fetch $f -Sleep $noSleep
        Assert ($r.Code -eq 4 -and $script:calls.Count -eq 0) ("Accepted "+($bad|ConvertTo-Json -Compress))
    }
}
Test 'the GitHub repository is read from the origin remote' {
    foreach($u in 'https://github.com/eddvasquez/agent-ops-core.git','https://github.com/eddvasquez/agent-ops-core','git@github.com:eddvasquez/agent-ops-core.git'){
        Assert ((ConvertTo-AgentOpsGitHubRepository $u) -eq 'eddvasquez/agent-ops-core') "Not parsed: $u"
    }
    Assert (-not (ConvertTo-AgentOpsGitHubRepository 'https://gitlab.com/a/b.git')) 'Non-GitHub remote accepted'
    Assert (-not (ConvertTo-AgentOpsGitHubRepository 'https://user:token@github.com/a/b.git')) 'Remote with credentials accepted'
}
Write-Host "Wait for CI: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
