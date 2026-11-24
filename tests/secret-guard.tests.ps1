# Credential guard: before an agent touches a credentials file, Claude Code and Antigravity ask the user;
# Codex (no "ask" before tools) blocks and explains. Only paths and commands count, never written content.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/SecretGuard.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-secretguard-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
function NewDir([string]$n){$d=Join-Path $script:base ($n+'-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($d)|Out-Null;return $d}
# Launches the hook like a harness: no console, stdin piped, stdout read as UTF-8.
function Hook([string]$harness,$event){
    $psi=New-Object Diagnostics.ProcessStartInfo
    $psi.FileName=(Get-Process -Id $PID).Path
    $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $source 'scripts/secret-guard-hook.ps1')+'" -Harness '+$harness
    $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true
    $psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
    $psi.StandardOutputEncoding=New-Object Text.UTF8Encoding($false)
    $p=[Diagnostics.Process]::Start($psi)
    $json=$(if($event -is [string]){$event}else{$event|ConvertTo-Json -Depth 6 -Compress})
    $bytes=$utf8.GetBytes($json);$p.StandardInput.BaseStream.Write($bytes,0,$bytes.Length);$p.StandardInput.Close()
    $out=$p.StandardOutput.ReadToEnd();$null=$p.StandardError.ReadToEnd();$p.WaitForExit()
    return @{Exit=$p.ExitCode;Out=$out.Trim()}
}

Test 'credential files are recognised; examples, code and documentation are not' {
    foreach($p in '.env','C:\p\.env.production','config/credentials.json','client_secret_123.apps.json','secrets.yaml','server.pem','tls.key','cert.pfx','id_rsa','id_ed25519.pub','google-ads.yaml','.npmrc','.git-credentials','service-account-credentials.json'){
        Assert (Test-AgentOpsSecretPath $p) "Not recognised as credential: $p"
    }
    foreach($p in '.env.example','.env.sample','.env.template','scripts/SecretScan.psm1','docs/secrets.md','app.py','credentials_helper.py','README.md','environment.yml'){
        Assert (-not (Test-AgentOpsSecretPath $p)) "Wrongly taken for a credential: $p"
    }
}
Test 'commands that name a credential file are caught; ordinary commands are not' {
    foreach($c in 'cat .env','Get-Content .\config\secrets.yaml','type "C:\x y\.env"','python -c "open(''google-ads.yaml'').read()"','copy id_rsa backup'){
        Assert (@(Find-AgentOpsSecretInCommand $c).Count) "Not caught: $c"
    }
    foreach($c in 'echo hola','git add .env.example','npm test','Get-ChildItem','python credentials_helper.py'){
        Assert (-not @(Find-AgentOpsSecretInCommand $c).Count) "Wrongly caught: $c"
    }
}
Test 'Claude Code: reading or editing a credential asks the user; writing text that mentions it does not' {
    $ask=Get-AgentOpsSecretDecision -Harness claude -Event ([pscustomobject]@{tool_name='Read';tool_input=[pscustomobject]@{file_path='C:\proj\.env'}})
    Assert ($ask.Decision -eq 'ASK' -and $ask.Reason -match '\.env') ($ask|ConvertTo-Json -Depth 5)
    $bash=Get-AgentOpsSecretDecision -Harness claude -Event ([pscustomobject]@{tool_name='Bash';tool_input=[pscustomobject]@{command='cat config/credentials.json'}})
    Assert ($bash.Decision -eq 'ASK') ($bash|ConvertTo-Json -Depth 5)
    $doc=Get-AgentOpsSecretDecision -Harness claude -Event ([pscustomobject]@{tool_name='Write';tool_input=[pscustomobject]@{file_path='C:\proj\README.md';content='Copia .env.example a .env y pon tu token'}})
    Assert ($doc.Decision -eq 'ALLOW') ($doc|ConvertTo-Json -Depth 5)
}
Test 'Codex: a credential is blocked with an explanation; apply_patch is judged by the files it touches, not its text' {
    $d=Get-AgentOpsSecretDecision -Harness codex -Event ([pscustomobject]@{tool_name='apply_patch';tool_input=[pscustomobject]@{command="*** Begin Patch`n*** Update File: .env`n+TOKEN=x`n*** End Patch"}})
    Assert ($d.Decision -eq 'DENY' -and $d.Reason -match 'usuario') ($d|ConvertTo-Json -Depth 5)
    $ok=Get-AgentOpsSecretDecision -Harness codex -Event ([pscustomobject]@{tool_name='apply_patch';tool_input=[pscustomobject]@{command="*** Begin Patch`n*** Update File: README.md`n+Copia .env.example a .env`n*** End Patch"}})
    Assert ($ok.Decision -eq 'ALLOW') ($ok|ConvertTo-Json -Depth 5)
}
Test 'Antigravity: view_file and run_command on a credential ask; write_to_file content does not count' {
    $v=Get-AgentOpsSecretDecision -Harness antigravity -Event ([pscustomobject]@{toolCall=[pscustomobject]@{name='view_file';args=[pscustomobject]@{AbsolutePath='C:\proj\secrets.json'}}})
    Assert ($v.Decision -eq 'ASK') ($v|ConvertTo-Json -Depth 5)
    $r=Get-AgentOpsSecretDecision -Harness antigravity -Event ([pscustomobject]@{toolCall=[pscustomobject]@{name='run_command';args=[pscustomobject]@{CommandLine='type .env';Cwd='C:\proj'}}})
    Assert ($r.Decision -eq 'ASK') ($r|ConvertTo-Json -Depth 5)
    $w=Get-AgentOpsSecretDecision -Harness antigravity -Event ([pscustomobject]@{toolCall=[pscustomobject]@{name='write_to_file';args=[pscustomobject]@{TargetFile='C:\proj\notas.md';CodeContent='usa .env'}}})
    Assert ($w.Decision -eq 'ALLOW') ($w|ConvertTo-Json -Depth 5)
}
Test 'Claude adapter output: ask through hookSpecificOutput; nothing when allowed' {
    $o=Hook 'claude' @{hook_event_name='PreToolUse';tool_name='Read';tool_input=@{file_path='C:\proj\.env'}}
    $j=($o.Out|ConvertFrom-Json).hookSpecificOutput
    Assert ($o.Exit -eq 0 -and $j.hookEventName -eq 'PreToolUse' -and $j.permissionDecision -eq 'ask' -and $j.permissionDecisionReason -match 'credenciales') ($o|ConvertTo-Json)
    $o=Hook 'claude' @{hook_event_name='PreToolUse';tool_name='Read';tool_input=@{file_path='C:\proj\app.py'}}
    Assert ($o.Exit -eq 0 -and -not $o.Out) ($o|ConvertTo-Json)
}
Test 'Codex adapter output: deny through hookSpecificOutput' {
    $o=Hook 'codex' @{hook_event_name='PreToolUse';tool_name='Bash';tool_input=@{command='cat .env'}}
    $j=($o.Out|ConvertFrom-Json).hookSpecificOutput
    Assert ($o.Exit -eq 0 -and $j.permissionDecision -eq 'deny' -and $j.permissionDecisionReason) ($o|ConvertTo-Json)
}
Test 'Antigravity adapter output: {decision:ask} or {decision:allow}' {
    $o=Hook 'antigravity' @{toolCall=@{name='view_file';args=@{AbsolutePath='C:\proj\.env'}}}
    Assert ($o.Exit -eq 0 -and ($o.Out|ConvertFrom-Json).decision -eq 'ask') ($o|ConvertTo-Json)
    $o=Hook 'antigravity' @{toolCall=@{name='view_file';args=@{AbsolutePath='C:\proj\app.py'}}}
    Assert ($o.Exit -eq 0 -and ($o.Out|ConvertFrom-Json).decision -eq 'allow') ($o|ConvertTo-Json)
}
Test 'an unreadable event never blocks the agent' {
    $o=Hook 'claude' 'no es json'
    Assert ($o.Exit -eq 0 -and $o.Out -notmatch 'deny|ask') ($o|ConvertTo-Json)
    $o=Hook 'antigravity' 'no es json'
    Assert ($o.Exit -eq 0 -and ($o.Out|ConvertFrom-Json).decision -eq 'allow') ($o|ConvertTo-Json)
}
Test 'install registers the guard per user in the three harnesses, keeps existing hooks and is idempotent; uninstall removes only it' {
    $home2=NewDir 'home';$state=NewDir 'state'
    $claude=Join-Path $home2 '.claude/settings.json';[IO.Directory]::CreateDirectory((Split-Path $claude))|Out-Null
    [IO.File]::WriteAllText($claude,'{"hooks":{"SessionStart":[{"hooks":[{"type":"command","command":"uv run watch check","timeout":60}]}]},"model":"opus"}',$utf8)
    $paths=@{StateDir=$state;ClaudeSettingsPath=$claude;CodexHooksPath=(Join-Path $home2 '.codex/hooks.json');AntigravityHooksPath=(Join-Path $home2 '.gemini/config/hooks.json')}
    $i=Install-AgentOpsSecretGuard @paths
    Assert ($i.Code -eq 0 -and $i.Status -eq 'INSTALLED') ($i|ConvertTo-Json -Depth 5)
    $c=[IO.File]::ReadAllText($claude)|ConvertFrom-Json
    Assert ($c.model -eq 'opus' -and @($c.hooks.SessionStart).Count -eq 1 -and @($c.hooks.PreToolUse).Count -eq 1) 'Claude settings lost or hook missing'
    Assert (($c.hooks.PreToolUse[0].hooks[0].args -join ' ') -match 'agent-ops-hook\.ps1.*-Hook secret-guard -Harness claude') ($c|ConvertTo-Json -Depth 8)
    $x=[IO.File]::ReadAllText($paths.CodexHooksPath)|ConvertFrom-Json
    Assert ($x.hooks.PreToolUse[0].hooks[0].commandWindows -match '-Harness codex') 'Codex hook missing'
    $a=[IO.File]::ReadAllText($paths.AntigravityHooksPath)|ConvertFrom-Json
    Assert ($a.'agent-ops-secret-guard'.PreToolUse[0].hooks[0].command -match '-Harness antigravity') 'Antigravity hook missing'
    Assert ([IO.File]::Exists((Join-Path $state 'hooks/agent-ops-hook.ps1'))) 'Launcher missing'
    Assert ((Install-AgentOpsSecretGuard @paths).Status -eq 'UP_TO_DATE') 'Second install was not idempotent'
    $u=Install-AgentOpsSecretGuard @paths -Uninstall
    $c=[IO.File]::ReadAllText($claude)|ConvertFrom-Json
    Assert ($u.Status -eq 'REMOVED' -and @($c.hooks.SessionStart).Count -eq 1 -and -not ($c.hooks.PSObject.Properties.Name -contains 'PreToolUse' -and @($c.hooks.PreToolUse).Count)) ($c|ConvertTo-Json -Depth 8)
}
Test 'the launcher runs the guard of the active release and lets the action through when no installation is found' {
    $state=NewDir 'state';[IO.File]::WriteAllText((Join-Path $state 'update-state.json'),(@{Mode='MANAGED';Active=@{Sha=('a'*40);Path=$source}}|ConvertTo-Json),$utf8)
    $paths=@{StateDir=$state;ClaudeSettingsPath=(Join-Path $state 'c.json');CodexHooksPath=(Join-Path $state 'x.json');AntigravityHooksPath=(Join-Path $state 'a.json')}
    Install-AgentOpsSecretGuard @paths|Out-Null
    $launcher=Join-Path $state 'hooks/agent-ops-hook.ps1'
    $run={param($stateDir,$json)
        $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=(Get-Process -Id $PID).Path
        $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$launcher+'" -Hook secret-guard -Harness claude'
        $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
        $psi.StandardOutputEncoding=New-Object Text.UTF8Encoding($false);$psi.EnvironmentVariables['AGENT_OPS_STATE_DIR']=$stateDir
        $p=[Diagnostics.Process]::Start($psi);$p.StandardInput.Write($json);$p.StandardInput.Close();$o=$p.StandardOutput.ReadToEnd();$null=$p.StandardError.ReadToEnd();$p.WaitForExit();$o.Trim()}
    $ev='{"hook_event_name":"PreToolUse","tool_name":"Read","tool_input":{"file_path":"C:\\p\\.env"}}'
    Assert ((& $run $state $ev) -match '"ask"') 'Launcher did not reach the active guard'
    $empty=NewDir 'vacio'
    Assert (-not (& $run $empty $ev)) 'Without an installation the launcher must let the action through'
}
Write-Host "Secret guard: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
