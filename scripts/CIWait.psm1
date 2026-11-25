Set-StrictMode -Version 2
# Waiting for GitHub without blocking (R-013): one call reports how the tests of a commit ended. The agent starts
# it in the background and keeps working; when it reports green, R-005 applies (offer to install). Read-only: it
# only queries the GitHub API. Error texts are never repeated, so a token can never end up in the output.
$script:workflow='windows-tests.yml'

function ConvertTo-AgentOpsGitHubRepository([string]$Remote){
    if($Remote -match '^https://github\.com/([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(\.git)?/?$'){return "$($Matches[1])/$($Matches[2])"}
    if($Remote -match '^git@github\.com:([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+?)(\.git)?$'){return "$($Matches[1])/$($Matches[2])"}
    return ''
}
function Ci-Time($v){if(-not $v){return $null};try{return [datetime]::Parse([string]$v,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)}catch{return $null}}
function Ci-Seconds($from,$to){$a=Ci-Time $from;$b=Ci-Time $to;if($a -and $b){[int][math]::Round(($b-$a).TotalSeconds)}else{$null}}

function Wait-AgentOpsCI {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Repository,[Parameter(Mandatory=$true)][string]$Sha,
          [int]$TimeoutMinutes=15,[int]$IntervalSeconds=60,[string]$Workflow=$script:workflow,
          [scriptblock]$Fetch,[scriptblock]$Sleep={param($s) Start-Sleep -Seconds $s})
    $res=[ordered]@{Code=4;Status='INVALID';Sha=$Sha;Repository=$Repository;Conclusion=$null;Url=$null;Seconds=$null;Promoted=$null;Failed=@();Jobs=@();Polls=0}
    if($Sha -notmatch '^[0-9a-f]{40}$' -or $Repository -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'){return [pscustomobject]$res}
    if(-not $Fetch){$Fetch=${function:Ci-DefaultFetch}}
    $polls=[math]::Max(1,[math]::Floor(($TimeoutMinutes*60)/[math]::Max(1,$IntervalSeconds))+1)
    $answered=$false
    for($i=1;$i -le $polls;$i++){
        $res.Polls=$i
        try{
            $page=& $Fetch "https://api.github.com/repos/$Repository/actions/runs?head_sha=$Sha&per_page=20"
            $answered=$true
            $run=@(@($page.workflow_runs)|Where-Object {$_ -and $_.head_sha -eq $Sha -and ([string]$_.path).EndsWith("/$Workflow")}|Sort-Object id -Descending)|Select-Object -First 1
            if($run -and $run.status -eq 'completed'){
                $res.Status='COMPLETED';$res.Conclusion=[string]$run.conclusion;$res.Url=[string]$run.html_url
                $res.Seconds=Ci-Seconds $run.run_started_at $run.updated_at
                $jobs=@((& $Fetch "https://api.github.com/repos/$Repository/actions/runs/$($run.id)/jobs?per_page=50").jobs)
                $res.Jobs=@($jobs|Where-Object {$_}|ForEach-Object {[pscustomobject]@{Name=[string]$_.name;Conclusion=[string]$_.conclusion;Seconds=(Ci-Seconds $_.started_at $_.completed_at)}})
                $res.Failed=@($res.Jobs|Where-Object {$_.Conclusion -in @('failure','cancelled','timed_out')}|ForEach-Object {$_.Name})
                $promote=@($res.Jobs|Where-Object {$_.Name -eq 'promote'})
                $res.Promoted=$(if($promote.Count){$promote[0].Conclusion -eq 'success'}else{$null})
                $res.Code=$(if($res.Conclusion -eq 'success'){0}else{1})
                return [pscustomobject]$res
            }
        }catch{}
        if($i -lt $polls){& $Sleep $IntervalSeconds}
    }
    if($answered){$res.Status='TIMEOUT';$res.Code=2}else{$res.Status='OFFLINE';$res.Code=3}
    return [pscustomobject]$res
}

# Real API call (public data; GITHUB_TOKEN only raises the rate limit and is never printed).
function Ci-DefaultFetch([string]$url){
    Add-Type -AssemblyName System.Net.Http
    $client=New-Object Net.Http.HttpClient
    try{
        $client.Timeout=[timespan]::FromSeconds(20)
        [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('User-Agent','AgentOps-WaitCI/1')
        [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('Accept','application/vnd.github+json')
        [void]$client.DefaultRequestHeaders.TryAddWithoutValidation('X-GitHub-Api-Version','2022-11-28')
        if($env:GITHUB_TOKEN){$client.DefaultRequestHeaders.Authorization=New-Object Net.Http.Headers.AuthenticationHeaderValue('Bearer',$env:GITHUB_TOKEN)}
        $response=$client.GetAsync($url).GetAwaiter().GetResult()
        try{
            if(-not $response.IsSuccessStatusCode){throw 'GitHub API unavailable.'}
            return ($response.Content.ReadAsStringAsync().GetAwaiter().GetResult()|ConvertFrom-Json)
        }finally{$response.Dispose()}
    }finally{$client.Dispose()}
}
Export-ModuleMember -Function Wait-AgentOpsCI,ConvertTo-AgentOpsGitHubRepository
