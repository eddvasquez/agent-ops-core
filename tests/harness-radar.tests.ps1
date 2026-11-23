# Harness capabilities table, harness detector and novelty radar (phase 1 + R1). No real network: fetchers are fakes.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/HarnessRadar.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-radar-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
function NewDir([string]$name){$d=Join-Path $script:base ($name+'-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($d)|Out-Null;return $d}
$table=Join-Path $source 'scripts/harness-capabilities.json'
# Fake network: URL -> text. Anything else fails like a dead source.
function Fetcher([hashtable]$map){
    return {param([string]$url) if($map.ContainsKey($url)){return $map[$url]};throw "offline: $url"}.GetNewClosure()
}
$codexUrl='https://api.github.com/repos/openai/codex/releases/latest'
$claudeUrl='https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md'
function Net([string]$codex='0.171.0',[string]$claude='2.1.330'){
    Fetcher @{$codexUrl=('{"tag_name":"rust-v'+$codex+'","name":"'+$codex+'","prerelease":false}');$claudeUrl=("# Changelog`n`n## $claude`n`n- Algo nuevo.`n`n## 2.1.300`n")}
}
$now=[datetime]'2026-11-24T10:00:00Z'
# A copy of the framework repository (where the maintainer works) and an ordinary consumer project.
$fw=NewDir 'agent-ops-core';[IO.Directory]::CreateDirectory((Join-Path $fw 'scripts'))|Out-Null
[IO.File]::WriteAllText((Join-Path $fw 'release-contract.json'),'{}',$utf8);Copy-Item $table (Join-Path $fw 'scripts/harness-capabilities.json')
$consumer=NewDir 'proyecto-cliente'
$tripwire={param([string]$url) throw "La red no debe consultarse fuera del repositorio del marco: $url"}

Test 'in a consumer project the radar stays silent and never touches the network' {
    $s=NewDir 'estado'
    $r=Invoke-AgentOpsHarnessRadar -ProjectPath $consumer -Action Check -StateDir $s -Path $table -Fetcher $tripwire -Now $now
    Assert ($r.Code -eq 0 -and $r.Status -eq 'NOT_MAINTAINER' -and -not @($r.Failures).Count -and -not @($r.Lines).Count) ($r|ConvertTo-Json -Depth 5)
    Assert (-not (Test-Path (Join-Path $s 'harness-radar.json'))) 'State written for a consumer project'
}
Test 'a pending novelty is never shown in a consumer project' {
    $s=NewDir 'estado'
    Invoke-AgentOpsHarnessRadar -ProjectPath $fw -Action Check -StateDir $s -Path $table -Fetcher (Net -codex '0.172.0') -Now $now|Out-Null
    $n=Invoke-AgentOpsHarnessRadar -ProjectPath $consumer -Action Notice -StateDir $s -Path $table -Now $now
    Assert ($n.Status -eq 'NOT_MAINTAINER' -and -not @($n.Lines).Count) ($n|ConvertTo-Json -Depth 5)
    Assert (Test-AgentOpsFrameworkRepository -ProjectPath $fw) 'Framework copy not recognised'
    Assert (-not (Test-AgentOpsFrameworkRepository -ProjectPath $consumer)) 'Consumer project taken for the framework'
}

Test 'the shipped capabilities table is valid: statuses, documentation links, dates and fallbacks' {
    $v=Test-AgentOpsHarnessCapabilities -Path $table
    Assert ($v.Code -eq 0) ($v.Issues -join '; ')
    $t=Get-AgentOpsHarnessCapabilities -Path $table
    Assert (@($t.Harnesses.PSObject.Properties.Name|Sort-Object) -join ',' -eq 'antigravity,claude-code,codex') 'Expected the three harnesses'
}
Test 'a capability without documentation, with an unknown status or a discard without reason is rejected' {
    $bad=Join-Path (NewDir 'tabla') 'caps.json'
    $json='{"SchemaVersion":1,"Harnesses":{"x":{"Name":"X","Detect":{"Dirs":[".x"],"Commands":["x"]},"Sources":[],"Capabilities":[{"Id":"hook.A","Status":"quizas","Doc":"","VerifiedAt":"2026-11-23","Fallback":"y"},{"Id":"hook.B","Status":"descartada","Doc":"https://x.test/b","VerifiedAt":"2026-11-23","Fallback":"y"}]}}}'
    [IO.File]::WriteAllText($bad,$json,$utf8)
    $v=Test-AgentOpsHarnessCapabilities -Path $bad
    Assert ($v.Code -eq 1) 'Invalid table accepted'
    Assert (@($v.Issues|Where-Object {$_ -match 'hook\.A'}).Count -ge 2 -and @($v.Issues|Where-Object {$_ -match 'hook\.B'}).Count -eq 1) ($v.Issues -join '; ')
}
Test 'an exploited capability must declare its fallback (the floor never depends on one harness)' {
    $bad=Join-Path (NewDir 'tabla') 'caps.json'
    $json='{"SchemaVersion":1,"Harnesses":{"x":{"Name":"X","Detect":{"Dirs":[".x"],"Commands":["x"]},"Sources":[],"Capabilities":[{"Id":"hook.Stop","Status":"aprovechada","Doc":"https://x.test/stop","VerifiedAt":"2026-11-23","Fallback":""}]}}}'
    [IO.File]::WriteAllText($bad,$json,$utf8)
    $v=Test-AgentOpsHarnessCapabilities -Path $bad
    Assert ($v.Code -eq 1 -and @($v.Issues|Where-Object {$_ -match 'hook\.Stop' -and $_ -match 'respaldo'}).Count -eq 1) ($v.Issues -join '; ')
}
Test 'the detector reports harnesses used in the project and installed on the machine' {
    $p=NewDir 'proyecto';[IO.Directory]::CreateDirectory((Join-Path $p '.claude'))|Out-Null;[IO.Directory]::CreateDirectory((Join-Path $p '.agents'))|Out-Null
    $resolver={param([string]$name) $name -eq 'codex'}
    $d=Get-AgentOpsHarnessPresence -ProjectPath $p -Path $table -CommandResolver $resolver
    $byId=@{};foreach($h in $d){$byId[$h.Id]=$h}
    Assert ($byId['claude-code'].InProject -and -not $byId['claude-code'].Installed) ($d|ConvertTo-Json -Depth 4)
    Assert ($byId['antigravity'].InProject -and -not $byId['codex'].InProject -and $byId['codex'].Installed) ($d|ConvertTo-Json -Depth 4)
}
Test 'a new upstream version produces exactly one notice line with the request to evaluate it' {
    $s=NewDir 'estado'
    $r=Invoke-AgentOpsHarnessRadar -ProjectPath $fw -Action Check -StateDir $s -Path $table -Fetcher (Net -codex '0.172.0') -Now $now
    Assert ($r.Code -eq 0 -and @($r.Novelties).Count -eq 1) ($r|ConvertTo-Json -Depth 5)
    $n=Invoke-AgentOpsHarnessRadar -ProjectPath $fw -Action Notice -StateDir $s -Path $table -Now $now
    Assert (@($n.Lines).Count -eq 1 -and $n.Lines[0] -match 'Codex' -and $n.Lines[0] -match '0\.172\.0' -and $n.Lines[0] -match 'evalúa codex 0\.172\.0') ($n|ConvertTo-Json -Depth 5)
}
Test 'versions already known in the table produce no notice' {
    $s=NewDir 'estado'
    Invoke-AgentOpsHarnessRadar -ProjectPath $fw -Action Check -StateDir $s -Path $table -Fetcher (Net) -Now $now|Out-Null
    $n=Invoke-AgentOpsHarnessRadar -ProjectPath $fw -Action Notice -StateDir $s -Path $table -Now $now
    Assert (-not @($n.Lines).Count) ($n|ConvertTo-Json -Depth 5)
}
Test 'acknowledging a novelty silences it' {
    $s=NewDir 'estado'
    Invoke-AgentOpsHarnessRadar -ProjectPath $fw -Action Check -StateDir $s -Path $table -Fetcher (Net -claude '2.1.331') -Now $now|Out-Null
    $a=Invoke-AgentOpsHarnessRadar -ProjectPath $fw -Action Ack -StateDir $s -Path $table -Harness 'claude-code' -Version '2.1.331' -Now $now
    Assert ($a.Code -eq 0) ($a|ConvertTo-Json -Depth 5)
    $n=Invoke-AgentOpsHarnessRadar -ProjectPath $fw -Action Notice -StateDir $s -Path $table -Now $now
    Assert (-not @($n.Lines).Count) ($n|ConvertTo-Json -Depth 5)
}
Test 'each source is checked at most once a day' {
    $s=NewDir 'estado'
    Invoke-AgentOpsHarnessRadar -ProjectPath $fw -Action Check -StateDir $s -Path $table -Fetcher (Net) -Now $now|Out-Null
    $r=Invoke-AgentOpsHarnessRadar -ProjectPath $fw -Action Check -StateDir $s -Path $table -Fetcher (Fetcher @{}) -Now $now.AddHours(2)
    Assert ($r.Code -eq 0 -and -not @($r.Failures).Count -and @($r.Skipped).Count -eq 2) ($r|ConvertTo-Json -Depth 5)
    $later=Invoke-AgentOpsHarnessRadar -ProjectPath $fw -Action Check -StateDir $s -Path $table -Fetcher (Net -codex '0.173.0') -Now $now.AddHours(25)
    Assert (@($later.Novelties).Count -eq 1) ($later|ConvertTo-Json -Depth 5)
}
Test 'a dead source is reported but never blocks: code 0 and no notice' {
    $s=NewDir 'estado'
    $r=Invoke-AgentOpsHarnessRadar -ProjectPath $fw -Action Check -StateDir $s -Path $table -Fetcher (Fetcher @{}) -Now $now
    Assert ($r.Code -eq 0 -and @($r.Failures).Count -eq 2 -and -not @($r.Novelties).Count) ($r|ConvertTo-Json -Depth 5)
}
Test 'downloaded text is data: a hostile version string is rejected and nothing runs' {
    $s=NewDir 'estado';$flag=Join-Path $s 'ran.txt'
    $evil=Fetcher @{$codexUrl=('{"tag_name":"$(New-Item '+$flag+')","name":"x"}');$claudeUrl="# Changelog`n`n## 9.9.9; Remove-Item C:\`n"}
    $r=Invoke-AgentOpsHarnessRadar -ProjectPath $fw -Action Check -StateDir $s -Path $table -Fetcher $evil -Now $now
    Assert (-not (Test-Path $flag)) 'Downloaded text was executed'
    Assert (-not @($r.Novelties).Count -and @($r.Failures).Count -eq 2) ($r|ConvertTo-Json -Depth 5)
}
Test 'the entry script prints JSON and the notice lines' {
    $s=NewDir 'estado'
    $engine=(Get-Process -Id $PID).Path
    $json=& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/harness-radar.ps1') -Action Notice -StateDir $s -ProjectPath $fw|Out-String
    Assert ($LASTEXITCODE -eq 0 -and ($json|ConvertFrom-Json).Status) $json
}
Write-Host "Harness radar: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if($script:failed){exit 1}
