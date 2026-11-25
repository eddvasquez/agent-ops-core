# Turn gate: an agent may only finish its turn when the code it changed has green tests recorded by the framework.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/TurnGate.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-turngate-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
function Put($r,$k,$t){$p=Join-Path $r $k;[IO.Directory]::CreateDirectory((Split-Path -Parent $p))|Out-Null;[IO.File]::WriteAllText($p,$t,$utf8)}
# A small copy of the framework repository: the pilot only runs where the framework is maintained.
function Framework{
    $r=Join-Path $script:base ('fw-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    [IO.Directory]::CreateDirectory($r)|Out-Null
    & git init -q -b main $r
    & git -C $r config user.name Tests;& git -C $r config user.email tests@localhost;& git -C $r config core.autocrlf false
    Put $r 'release-contract.json' '{}'
    Put $r 'scripts/harness-capabilities.json' '{}'
    Put $r 'scripts/tool.ps1' "'v1'"
    Put $r 'tests/ok.tests.ps1' "Write-Host 'ok: 1 passed, 0 failed.'`nexit 0"
    Put $r 'tests/bad.tests.ps1' "Write-Host 'bad: 0 passed, 1 failed.'`nexit 1"
    Put $r 'README.md' 'docs'
    & git -C $r add -A;& git -C $r commit -q --no-verify -m base
    return $r
}
function State{$s=Join-Path $script:base ('state-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($s)|Out-Null;return $s}
# Launches the hook the way a harness does: no console of its own, stdin piped, stdout read as UTF-8 bytes.
function Hook([string]$harness,[string]$json,[string]$stateDir){
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=(Get-Process -Id $PID).Path
    $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $source 'scripts/turn-gate-hook.ps1')+'" -Harness '+$harness
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    $psi.StandardOutputEncoding=New-Object Text.UTF8Encoding($false)
    $psi.EnvironmentVariables['AGENT_OPS_STATE_DIR']=$stateDir
    $p=[Diagnostics.Process]::Start($psi)
    $p.StandardInput.Write($json);$p.StandardInput.Close()
    $out=$p.StandardOutput.ReadToEnd();$null=$p.StandardError.ReadToEnd();$p.WaitForExit()
    return @{Exit=$p.ExitCode;Out=$out.Trim()}
}
Test 'without code changes the turn may end' {
    $r=Framework;$g=Test-AgentOpsTurnGate -ProjectPath $r -StateDir (State) -SessionId 's1'
    Assert ($g.Decision -eq 'ALLOW') ($g|ConvertTo-Json -Depth 5)
}
Test 'a change only in documentation does not require tests' {
    $r=Framework;Put $r 'README.md' 'más docs'
    $g=Test-AgentOpsTurnGate -ProjectPath $r -StateDir (State) -SessionId 's1'
    Assert ($g.Decision -eq 'ALLOW') ($g|ConvertTo-Json -Depth 5)
}
Test 'a code change without green tests sends the agent back, naming the file and how to verify' {
    $r=Framework;Put $r 'scripts/tool.ps1' "'v2'"
    $g=Test-AgentOpsTurnGate -ProjectPath $r -StateDir (State) -SessionId 's1'
    Assert ($g.Decision -eq 'BLOCK' -and $g.Reason -match 'scripts/tool\.ps1' -and $g.Reason -match 'run-tests\.ps1') ($g|ConvertTo-Json -Depth 5)
}
Test 'an untracked new script counts as a code change' {
    $r=Framework;Put $r 'scripts/new.psm1' '1'
    $g=Test-AgentOpsTurnGate -ProjectPath $r -StateDir (State) -SessionId 's1'
    Assert ($g.Decision -eq 'BLOCK' -and $g.Reason -match 'scripts/new\.psm1') ($g|ConvertTo-Json -Depth 5)
}
Test 'green tests recorded by run-tests for this exact state let the turn end' {
    $r=Framework;Put $r 'scripts/tool.ps1' "'v2'"
    $run=Invoke-AgentOpsTestRun -ProjectPath $r -Suites @('ok')
    Assert ($run.Code -eq 0 -and $run.Status -eq 'GREEN') ($run|ConvertTo-Json -Depth 5)
    $g=Test-AgentOpsTurnGate -ProjectPath $r -StateDir (State) -SessionId 's1'
    Assert ($g.Decision -eq 'ALLOW') ($g|ConvertTo-Json -Depth 5)
}
Test 'a red suite records no evidence' {
    $r=Framework;Put $r 'scripts/tool.ps1' "'v2'"
    $run=Invoke-AgentOpsTestRun -ProjectPath $r -Suites @('ok','bad')
    Assert ($run.Code -eq 1 -and $run.Status -eq 'RED') ($run|ConvertTo-Json -Depth 5)
    $g=Test-AgentOpsTurnGate -ProjectPath $r -StateDir (State) -SessionId 's1'
    Assert ($g.Decision -eq 'BLOCK') ($g|ConvertTo-Json -Depth 5)
}
Test 'evidence stops counting as soon as the code changes again' {
    $r=Framework;Put $r 'scripts/tool.ps1' "'v2'"
    Invoke-AgentOpsTestRun -ProjectPath $r -Suites @('ok')|Out-Null
    Put $r 'scripts/tool.ps1' "'v3'"
    $g=Test-AgentOpsTurnGate -ProjectPath $r -StateDir (State) -SessionId 's1'
    Assert ($g.Decision -eq 'BLOCK') ($g|ConvertTo-Json -Depth 5)
}
Test 'outside the framework repository the pilot never blocks' {
    $p=Join-Path $script:base ('cliente-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($p)|Out-Null
    & git init -q -b main $p;Put $p 'app.ps1' '1'
    $g=Test-AgentOpsTurnGate -ProjectPath $p -StateDir (State) -SessionId 's1'
    Assert ($g.Decision -eq 'ALLOW' -and $g.Status -eq 'NOT_PILOT') ($g|ConvertTo-Json -Depth 5)
}
Test 'after two consecutive returns in a session the third lets the turn end, flagged as unverified' {
    $r=Framework;Put $r 'scripts/tool.ps1' "'v2'";$s=State
    $a=Test-AgentOpsTurnGate -ProjectPath $r -StateDir $s -SessionId 'loop'
    $b=Test-AgentOpsTurnGate -ProjectPath $r -StateDir $s -SessionId 'loop'
    $c=Test-AgentOpsTurnGate -ProjectPath $r -StateDir $s -SessionId 'loop'
    Assert ($a.Decision -eq 'BLOCK' -and $b.Decision -eq 'BLOCK' -and $c.Decision -eq 'ALLOW' -and $c.Status -eq 'UNVERIFIED') (@($a,$b,$c)|ConvertTo-Json -Depth 5)
    $other=Test-AgentOpsTurnGate -ProjectPath $r -StateDir $s -SessionId 'otra'
    Assert ($other.Decision -eq 'BLOCK') 'The counter of one session must not affect another'
}
Test 'Claude Code adapter: block is {decision:block,reason} and allow prints nothing' {
    $r=Framework;Put $r 'scripts/tool.ps1' "'v2'";$s=State
    $in=(@{session_id='c1';cwd=$r;hook_event_name='Stop';stop_hook_active=$false}|ConvertTo-Json -Compress)
    $o=Hook 'claude' $in $s
    $j=$o.Out|ConvertFrom-Json
    Assert ($o.Exit -eq 0 -and $j.decision -eq 'block' -and $j.reason -match 'tool\.ps1') ($o|ConvertTo-Json)
    Assert ($j.reason -match 'cambios de código' -and $j.reason -match 'explícaselo') "Accents garbled: $($j.reason)"
    Invoke-AgentOpsTestRun -ProjectPath $r -Suites @('ok')|Out-Null
    $o=Hook 'claude' $in $s
    Assert ($o.Exit -eq 0 -and -not $o.Out) ($o|ConvertTo-Json)
}
Test 'Codex adapter: block is {decision:block,reason}' {
    $r=Framework;Put $r 'scripts/tool.ps1' "'v2'"
    $in=(@{session_id='x1';cwd=$r;hook_event_name='Stop';stop_hook_active=$false;turn_id='t'}|ConvertTo-Json -Compress)
    $o=Hook 'codex' $in (State)
    $j=$o.Out|ConvertFrom-Json
    Assert ($o.Exit -eq 0 -and $j.decision -eq 'block' -and $j.reason) ($o|ConvertTo-Json)
}
Test 'Antigravity adapter: block is {decision:continue,reason} and allow is {}' {
    $r=Framework;Put $r 'scripts/tool.ps1' "'v2'";$s=State
    $in=(@{conversationId='a1';workspacePaths=@($r);executionNum=1;terminationReason='model_stop';fullyIdle=$true}|ConvertTo-Json -Compress)
    $o=Hook 'antigravity' $in $s
    $j=$o.Out|ConvertFrom-Json
    Assert ($o.Exit -eq 0 -and $j.decision -eq 'continue' -and $j.reason) ($o|ConvertTo-Json)
    Invoke-AgentOpsTestRun -ProjectPath $r -Suites @('ok')|Out-Null
    $o=Hook 'antigravity' $in $s
    Assert ($o.Exit -eq 0 -and $o.Out -eq '{}') ($o|ConvertTo-Json)
}
Test 'an unreadable hook input never blocks the turn' {
    $o=Hook 'claude' 'esto no es json' (State)
    Assert ($o.Exit -eq 0 -and -not ($o.Out -match '"block"')) ($o|ConvertTo-Json)
}
Test 'the installer writes the three harness configurations, keeps existing settings and is idempotent' {
    $r=Framework;Put $r '.claude/settings.local.json' '{"permissions":{"allow":["Bash(git status)"]}}'
    $i=Install-AgentOpsTurnGate -ProjectPath $r
    Assert ($i.Code -eq 0 -and $i.Status -eq 'INSTALLED') ($i|ConvertTo-Json -Depth 5)
    $claude=[IO.File]::ReadAllText((Join-Path $r '.claude/settings.local.json'))|ConvertFrom-Json
    Assert ($claude.permissions.allow -contains 'Bash(git status)') 'Existing Claude settings were lost'
    Assert (@($claude.hooks.Stop).Count -eq 1 -and ($claude.hooks.Stop[0].hooks[0].args -join ' ') -match 'turn-gate-hook\.ps1') 'Claude Stop hook missing'
    $codex=[IO.File]::ReadAllText((Join-Path $r '.codex/hooks.json'))|ConvertFrom-Json
    Assert ($codex.hooks.Stop[0].hooks[0].commandWindows -match 'turn-gate-hook\.ps1.*-Harness codex') 'Codex Stop hook missing'
    $ag=[IO.File]::ReadAllText((Join-Path $r '.agents/hooks.json'))|ConvertFrom-Json
    Assert ($ag.'agent-ops-turn-gate'.Stop[0].command -match 'turn-gate-hook\.ps1.*-Harness antigravity') 'Antigravity Stop hook missing'
    $again=Install-AgentOpsTurnGate -ProjectPath $r
    Assert ($again.Status -eq 'UP_TO_DATE') ($again|ConvertTo-Json -Depth 5)
    $claude=[IO.File]::ReadAllText((Join-Path $r '.claude/settings.local.json'))|ConvertFrom-Json
    Assert (@($claude.hooks.Stop).Count -eq 1) 'Installing twice duplicated the hook'
}
Test 'the installer refuses projects other than the framework repository during the pilot' {
    $p=Join-Path $script:base ('cliente-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($p)|Out-Null
    $i=Install-AgentOpsTurnGate -ProjectPath $p
    Assert ($i.Status -eq 'NOT_PILOT' -and -not (Test-Path (Join-Path $p '.claude'))) ($i|ConvertTo-Json -Depth 5)
}
Test 'while tests of this exact state are already running, the turn may end (no bounce) and the agent is told to offer waiting or advancing' {
    $r=Framework;$s=State;Put $r 'scripts/tool.ps1' "'v2'"
    $fp=(Get-AgentOpsCodeFingerprint -ProjectPath $r).Fingerprint
    $me=Get-Process -Id $PID
    Put $r ".context/test-runs/$PID.json" (@{Fingerprint=$fp;Pid=$PID;ProcessStart=$me.StartTime.ToUniversalTime().Ticks;StartedUtc=[datetime]::UtcNow.ToString('o');Edition='Desktop'}|ConvertTo-Json)
    $g=Test-AgentOpsTurnGate -ProjectPath $r -StateDir $s -SessionId 'run'
    Assert ($g.Decision -eq 'ALLOW' -and $g.Status -eq 'RUNNING' -and $g.Reason -match 'esperar' -and $g.Reason -match 'adelantar') ($g|ConvertTo-Json)
}
Test 'a run that died or belongs to another state does not count' {
    $r=Framework;$s=State;Put $r 'scripts/tool.ps1' "'v3'"
    $fp=(Get-AgentOpsCodeFingerprint -ProjectPath $r).Fingerprint
    $dead=Start-Process -FilePath (Get-Process -Id $PID).Path -ArgumentList '-NoProfile','-Command','exit 0' -PassThru -WindowStyle Hidden;$dead.WaitForExit()
    Put $r ".context/test-runs/$($dead.Id).json" (@{Fingerprint=$fp;Pid=$dead.Id;ProcessStart=$dead.StartTime.ToUniversalTime().Ticks;StartedUtc=[datetime]::UtcNow.ToString('o');Edition='Desktop'}|ConvertTo-Json)
    $me=Get-Process -Id $PID
    Put $r ".context/test-runs/$PID.json" (@{Fingerprint=('0'*64);Pid=$PID;ProcessStart=$me.StartTime.ToUniversalTime().Ticks;StartedUtc=[datetime]::UtcNow.ToString('o');Edition='Desktop'}|ConvertTo-Json)
    $g=Test-AgentOpsTurnGate -ProjectPath $r -StateDir $s -SessionId 'dead'
    Assert ($g.Decision -eq 'BLOCK' -and $g.Status -eq 'UNTESTED') ($g|ConvertTo-Json)
    Assert (-not (Test-Path (Join-Path $r ".context/test-runs/$($dead.Id).json"))) 'Dead run marker not cleaned up'
}
Test 'an acceptance review that is not passed sends the agent back; an accepted one, or none, lets the turn end' {
    Import-Module (Join-Path $source 'scripts/Acceptance.psm1') -Force
    $r=Framework;$s=State
    $c=New-AgentOpsAcceptance -ProjectPath $r -Request 'Pide algo concreto' -Criteria @('Dice hola')
    Put $r 'docs/entrega.md' 'hola mundo'
    $rev=New-AgentOpsAcceptanceReview -ProjectPath $r -Id $c.Id -Deliverable @((Join-Path $r 'docs/entrega.md'))
    $g=Test-AgentOpsTurnGate -ProjectPath $r -StateDir $s -SessionId 'acc'
    Assert ($g.Decision -eq 'BLOCK' -and $g.Status -eq 'ACCEPTANCE_PENDING' -and $g.Reason -match 'aceptación' -and $g.Reason -match [regex]::Escape($c.Id)) ($g|ConvertTo-Json)
    $t=[IO.File]::ReadAllText($rev.Sheet) -replace '(?m)^- C1: PENDIENTE$','- C1: PASA - "hola mundo"';[IO.File]::WriteAllText($rev.Sheet,$t,$utf8)
    $g=Test-AgentOpsTurnGate -ProjectPath $r -StateDir $s -SessionId 'acc2'
    Assert ($g.Decision -eq 'ALLOW') ('Accepted review still blocks: '+($g|ConvertTo-Json))
    $plain=Framework
    Assert ((Test-AgentOpsTurnGate -ProjectPath $plain -StateDir $s -SessionId 'none').Decision -eq 'ALLOW') 'No contract must not block'
}
Write-Host "Turn gate: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
