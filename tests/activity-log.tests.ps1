# Activity log (after each action): in a project governed by Agent Ops Core, every action that writes or runs is
# recorded outside the repository (tool, relative paths, whether it ran tests), never command text or content, so a
# cut session can be resumed from facts. Claude Code and Codex run it in the background; Antigravity answers at once.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/ActivityLog.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-activity-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
function NewDir([string]$n){$d=Join-Path $script:base ($n+'-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($d)|Out-Null;return $d}
function Governed{$p=NewDir 'proyecto';[IO.File]::WriteAllText((Join-Path $p 'AGENTS.md'),"### Protocolo 1 (MODO ENTRADA)`n",$utf8);return $p}
function Lines($state,$project){$f=Get-AgentOpsActivityPath -StateDir $state -ProjectPath $project;if(-not [IO.File]::Exists($f)){return @()};@([IO.File]::ReadAllLines($f)|Where-Object {$_}|ForEach-Object {$_|ConvertFrom-Json})}

Test 'edits are recorded with relative paths; reads are not' {
    $p=Governed;$s=NewDir 'state'
    Add-AgentOpsActivity -StateDir $s -Harness claude -Event (@{cwd=$p;tool_name='Edit';tool_input=@{file_path=(Join-Path $p 'scripts\a.ps1')}}|ConvertTo-Json -Compress)
    Add-AgentOpsActivity -StateDir $s -Harness claude -Event (@{cwd=$p;tool_name='Read';tool_input=@{file_path=(Join-Path $p 'README.md')}}|ConvertTo-Json -Compress)
    Add-AgentOpsActivity -StateDir $s -Harness antigravity -Event (@{workspacePaths=@($p);toolCall=@{name='write_to_file';args=@{TargetFile=(Join-Path $p 'docs/b.md')}}}|ConvertTo-Json -Compress -Depth 5)
    $l=Lines $s $p
    Assert ($l.Count -eq 2 -and $l[0].Tool -eq 'Edit' -and (@($l[0].Files) -join ',') -eq 'scripts/a.ps1' -and $l[1].Harness -eq 'antigravity' -and (@($l[1].Files) -join ',') -eq 'docs/b.md') ($l|ConvertTo-Json -Depth 4)
}
Test 'a command is recorded only as whether it ran tests and its exit code, never its text' {
    $p=Governed;$s=NewDir 'state'
    Add-AgentOpsActivity -StateDir $s -Harness claude -Event (@{cwd=$p;tool_name='PowerShell';tool_input=@{command='& ./scripts/run-tests.ps1 -Changed'};tool_response=@{exitCode=0}}|ConvertTo-Json -Compress)
    Add-AgentOpsActivity -StateDir $s -Harness codex -Event (@{cwd=$p;tool_name='Bash';tool_input=@{command='curl -H "Authorization: Bearer ghp_FAKESECRET" https://x'}}|ConvertTo-Json -Compress)
    $raw=[IO.File]::ReadAllText((Get-AgentOpsActivityPath -StateDir $s -ProjectPath $p))
    Assert ($raw -notmatch 'FAKESECRET|curl|Authorization|run-tests\.ps1 -Changed') "Command text leaked: $raw"
    $l=Lines $s $p
    Assert ($l.Count -eq 2 -and $l[0].Tests -eq $true -and $l[0].Exit -eq 0 -and $l[1].Tests -eq $false) ($l|ConvertTo-Json -Depth 4)
}
Test 'outside a governed project nothing is recorded' {
    $p=NewDir 'otro';$s=NewDir 'state'
    Add-AgentOpsActivity -StateDir $s -Harness claude -Event (@{cwd=$p;tool_name='Write';tool_input=@{file_path=(Join-Path $p 'x.txt')}}|ConvertTo-Json -Compress)
    Assert (-not [IO.Directory]::Exists((Join-Path $s 'activity'))) 'Recorded outside a governed project'
}
Test 'the log is capped and rotates' {
    $p=Governed;$s=NewDir 'state';$f=Get-AgentOpsActivityPath -StateDir $s -ProjectPath $p
    [IO.Directory]::CreateDirectory((Split-Path $f))|Out-Null;[IO.File]::WriteAllText($f,('x'*270000))
    Add-AgentOpsActivity -StateDir $s -Harness claude -Event (@{cwd=$p;tool_name='Write';tool_input=@{file_path=(Join-Path $p 'y.txt')}}|ConvertTo-Json -Compress)
    Assert ([IO.File]::Exists("$f.1") -and (New-Object IO.FileInfo $f).Length -lt 1000) 'Log was not rotated'
}
Test 'activity since a moment summarises files, commands and test runs' {
    $p=Governed;$s=NewDir 'state'
    Add-AgentOpsActivity -StateDir $s -Harness claude -Event (@{cwd=$p;tool_name='Edit';tool_input=@{file_path=(Join-Path $p 'a.ps1')}}|ConvertTo-Json -Compress)
    # Some machines (CI) tick the clock every ~15.6 ms: wait on both sides so the first edit is strictly before the mark.
    Start-Sleep -Milliseconds 50;$mark=[datetime]::UtcNow;Start-Sleep -Milliseconds 50
    Add-AgentOpsActivity -StateDir $s -Harness claude -Event (@{cwd=$p;tool_name='Edit';tool_input=@{file_path=(Join-Path $p 'b.ps1')}}|ConvertTo-Json -Compress)
    Add-AgentOpsActivity -StateDir $s -Harness claude -Event (@{cwd=$p;tool_name='Bash';tool_input=@{command='pwsh -File tests/x.tests.ps1'};tool_response=@{exitCode=1}}|ConvertTo-Json -Compress)
    $a=Get-AgentOpsActivitySummary -StateDir $s -ProjectPath $p -Since $mark
    Assert ((@($a.Files) -join ',') -eq 'b.ps1' -and $a.Commands -eq 1 -and $a.TestRuns -eq 1 -and $a.TestFailures -eq 1) ($a|ConvertTo-Json -Depth 4)
}
Test 'a Codex patch is recorded by the files it touches, never by its content' {
    $p=Governed;$s=NewDir 'state'
    $patch="*** Begin Patch`n*** Update File: scripts/c.ps1`n@@`n-old`n+new ghp_FAKESECRET`n*** Add File: docs/nuevo.md`n+hola`n*** End Patch"
    Add-AgentOpsActivity -StateDir $s -Harness codex -Event (@{cwd=$p;tool_name='apply_patch';tool_input=@{command=$patch}}|ConvertTo-Json -Compress)
    $raw=[IO.File]::ReadAllText((Get-AgentOpsActivityPath -StateDir $s -ProjectPath $p))
    $l=Lines $s $p
    Assert ((@($l[0].Files) -join ',') -eq 'scripts/c.ps1,docs/nuevo.md' -and $raw -notmatch 'FAKESECRET|hola') $raw
}
Test 'the hook answers Antigravity at once with {} and never fails the action' {
    $p=Governed;$s=NewDir 'state'
    $run={param($h,$json)
        $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=(Get-Process -Id $PID).Path
        $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $source 'scripts/post-tool-hook.ps1')+'" -Harness '+$h
        $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
        $psi.StandardOutputEncoding=$utf8;$psi.EnvironmentVariables['AGENT_OPS_STATE_DIR']=$s
        $pr=[Diagnostics.Process]::Start($psi);$b=$utf8.GetBytes($json);$pr.StandardInput.BaseStream.Write($b,0,$b.Length);$pr.StandardInput.Close()
        $o=$pr.StandardOutput.ReadToEnd();$null=$pr.StandardError.ReadToEnd();$pr.WaitForExit();@{Exit=$pr.ExitCode;Out=$o.Trim()}}
    $r=& $run 'antigravity' (@{workspacePaths=@($p);toolCall=@{name='write_to_file';args=@{TargetFile=(Join-Path $p 'x.md')}}}|ConvertTo-Json -Compress -Depth 5)
    Assert ($r.Exit -eq 0 -and $r.Out -eq '{}') "antigravity: $($r.Out)"
    $r=& $run 'claude' '{roto';Assert ($r.Exit -eq 0 -and -not $r.Out) "claude broken event: $($r.Out)"
    Assert (@(Lines $s $p).Count -eq 1) 'The Antigravity action was not recorded'
}
Test 'install adds the after-action hook in the three harnesses, in the background where they allow it' {
    Import-Module (Join-Path $source 'scripts/SessionStart.psm1') -Force
    $s=NewDir 'state';$paths=@{StateDir=$s;ClaudeSettingsPath=(Join-Path $s 'c.json');CodexHooksPath=(Join-Path $s 'x.json');AntigravityHooksPath=(Join-Path $s 'a.json')}
    Install-AgentOpsSessionStart @paths|Out-Null
    $c=[IO.File]::ReadAllText($paths.ClaudeSettingsPath)|ConvertFrom-Json
    $post=@($c.hooks.PostToolUse|Where-Object {($_|ConvertTo-Json -Depth 8) -match 'post-tool'})
    Assert ($post.Count -eq 1 -and $post[0].hooks[0].async -eq $true -and $post[0].matcher -match 'Edit' -and $post[0].matcher -match 'Bash') ($c|ConvertTo-Json -Depth 8)
    $x=[IO.File]::ReadAllText($paths.CodexHooksPath)|ConvertFrom-Json
    Assert ($x.hooks.PostToolUse[0].hooks[0].async -eq $true -and $x.hooks.PostToolUse[0].matcher -match 'apply_patch') ($x|ConvertTo-Json -Depth 8)
    $a=[IO.File]::ReadAllText($paths.AntigravityHooksPath)|ConvertFrom-Json
    Assert (@($a.'agent-ops-activity'.PostToolUse)[0].hooks[0].command -match '-Hook post-tool -Harness antigravity') ($a|ConvertTo-Json -Depth 8)
    $sub=@($c.hooks.SubagentStop|Where-Object {($_|ConvertTo-Json -Depth 8) -match 'subagent-stop'})
    Assert ($sub.Count -eq 1) 'SubagentStop (Claude Code) missing'
    Assert ((Install-AgentOpsSessionStart @paths).Status -eq 'UP_TO_DATE') 'Not idempotent'
    Install-AgentOpsSessionStart @paths -Uninstall|Out-Null
    $c=[IO.File]::ReadAllText($paths.ClaudeSettingsPath)|ConvertFrom-Json
    Assert (-not ($c.PSObject.Properties['hooks'] -and ($c.hooks.PSObject.Properties['PostToolUse'] -or $c.hooks.PSObject.Properties['SubagentStop']))) 'Uninstall left the hooks'
}
Test 'after a cut session the start notice says what it did since its last checkpoint' {
    Import-Module (Join-Path $source 'scripts/SessionStart.psm1') -Force
    $p=Governed;$s=NewDir 'state'
    & git init -q -b main $p;& git -C $p config user.name T;& git -C $p config user.email t@localhost;& git -C $p add -A;& git -C $p commit -q --no-verify -m base
    [IO.Directory]::CreateDirectory((Join-Path $p '.context'))|Out-Null
    [IO.File]::WriteAllText((Join-Path $p '.context/checkpoint.json'),(@{State='OPEN';StartedAt=[datetime]::UtcNow.AddMinutes(-5).ToString('o')}|ConvertTo-Json),$utf8)
    Add-AgentOpsActivity -StateDir $s -Harness claude -Event (@{cwd=$p;tool_name='Edit';tool_input=@{file_path=(Join-Path $p 'scripts/a.ps1')}}|ConvertTo-Json -Compress)
    Add-AgentOpsActivity -StateDir $s -Harness claude -Event (@{cwd=$p;tool_name='Bash';tool_input=@{command='pwsh -File tests/a.tests.ps1'};tool_response=@{exitCode=1}}|ConvertTo-Json -Compress)
    $b=Get-AgentOpsSessionBrief -ProjectPath $p -StateDir $s
    Assert ($b -match 'tocó 1 archivo' -and $b -match 'scripts/a\.ps1' -and $b -match '1 ejecución de pruebas' -and $b -match '1 en rojo') $b
}
Test 'concurrent writers from another harness within the window are detected and reported at session start' {
    Import-Module (Join-Path $source 'scripts/SessionStart.psm1') -Force
    $p=Governed;$s=NewDir 'state'
    & git init -q -b main $p;& git -C $p config user.name T;& git -C $p config user.email t@localhost;& git -C $p add -A;& git -C $p commit -q --no-verify -m base
    Add-AgentOpsActivity -StateDir $s -Harness claude -Event (@{cwd=$p;tool_name='Edit';tool_input=@{file_path=(Join-Path $p 'scripts/a.ps1')}}|ConvertTo-Json -Compress)
    $cw=Get-AgentOpsConcurrentWriters -StateDir $s -ProjectPath $p -CurrentHarness 'antigravity' -WindowMinutes 15
    Assert ($cw.Detected -and (@($cw.Harnesses) -contains 'claude') -and (@($cw.Files) -contains 'scripts/a.ps1')) ($cw|ConvertTo-Json -Depth 4)
    $same=Get-AgentOpsConcurrentWriters -StateDir $s -ProjectPath $p -CurrentHarness 'claude' -WindowMinutes 15
    Assert (-not $same.Detected) 'Same harness must not trigger concurrent writer warning'
    $b=Get-AgentOpsSessionBrief -ProjectPath $p -StateDir $s -Harness 'antigravity'
    Assert ($b -match 'escritor' -and $b -match 'claude' -and $b -match 'scripts/a\.ps1') $b
}
Test 'post-tool-hook injects R-018 additionalContext for Antigravity when a test run is active' {
    Import-Module (Join-Path $source 'scripts/TurnGate.psm1') -Force
    $p=Governed;$s=NewDir 'state'
    $run={param($h,$json)
        $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=(Get-Process -Id $PID).Path
        $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $source 'scripts/post-tool-hook.ps1')+'" -Harness '+$h
        $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
        $psi.StandardOutputEncoding=$utf8;$psi.EnvironmentVariables['AGENT_OPS_STATE_DIR']=$s
        $pr=[Diagnostics.Process]::Start($psi);$b=$utf8.GetBytes($json);$pr.StandardInput.BaseStream.Write($b,0,$b.Length);$pr.StandardInput.Close()
        $o=$pr.StandardOutput.ReadToEnd();$null=$pr.StandardError.ReadToEnd();$pr.WaitForExit();@{Exit=$pr.ExitCode;Out=$o.Trim()}}
    $me=Get-Process -Id $PID
    [IO.Directory]::CreateDirectory((Join-Path $p '.context/test-runs'))|Out-Null
    [IO.File]::WriteAllText((Join-Path $p ".context/test-runs/$PID.json"),(@{Fingerprint='abc';Pid=$PID;ProcessStart=$me.StartTime.ToUniversalTime().Ticks;StartedUtc=[datetime]::UtcNow.ToString('o');Edition='Desktop'}|ConvertTo-Json),$utf8)
    $r=& $run 'antigravity' (@{workspacePaths=@($p);toolCall=@{name='run_command';args=@{CommandLine='powershell -File scripts/run-tests.ps1'}}}|ConvertTo-Json -Compress -Depth 5)
    $j=$r.Out|ConvertFrom-Json
    Assert ($r.Exit -eq 0 -and $j.hookSpecificOutput.hookEventName -eq 'PostToolUse' -and $j.hookSpecificOutput.additionalContext -match 'R-018') ($r|ConvertTo-Json)
}
Test 'Skill tool in Claude is matched in SessionStart and post-tool-hook logs usage without polluting activity log' {
    Import-Module (Join-Path $source 'scripts/SessionStart.psm1') -Force
    $s=NewDir 'state';$p=Governed;$hub=NewDir 'hub'
    [IO.Directory]::CreateDirectory((Join-Path $hub 'dev-tdd'))|Out-Null
    [IO.File]::WriteAllText((Join-Path $hub 'dev-tdd/SKILL.md'),"---`nname: dev-tdd`nversion: 1.0.0`ndescription: tdd`n---`n",$utf8)
    $paths=@{StateDir=$s;ClaudeSettingsPath=(Join-Path $s 'c.json');CodexHooksPath=(Join-Path $s 'x.json');AntigravityHooksPath=(Join-Path $s 'a.json')}
    Install-AgentOpsSessionStart @paths|Out-Null
    $c=[IO.File]::ReadAllText($paths.ClaudeSettingsPath)|ConvertFrom-Json
    $post=@($c.hooks.PostToolUse|Where-Object {($_|ConvertTo-Json -Depth 8) -match 'post-tool'})
    Assert ($post[0].matcher -match 'Skill') ($post|ConvertTo-Json -Depth 6)
    $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=(Get-Process -Id $PID).Path
    $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $source 'scripts/post-tool-hook.ps1')+'" -Harness claude'
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    $psi.EnvironmentVariables['AGENT_OPS_STATE_DIR']=$s;$psi.EnvironmentVariables['AGENT_OPS_HUB_DIR']=$hub
    $pr=[Diagnostics.Process]::Start($psi)
    $ev=(@{cwd=$p;session_id='s-skill';tool_name='Skill';tool_input=@{skill='dev-tdd'}}|ConvertTo-Json -Compress)
    $b=$utf8.GetBytes($ev);$pr.StandardInput.BaseStream.Write($b,0,$b.Length);$pr.StandardInput.Close();$pr.WaitForExit()
    Assert ($pr.ExitCode -eq 0 -and @(Lines $s $p).Count -eq 0) 'Skill call polluted activity log'
    Assert (Test-Path (Join-Path $hub 'proposals/usage.jsonl')) 'Skill usage was not logged to hub usage.jsonl'
}
Write-Host "Activity log: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
