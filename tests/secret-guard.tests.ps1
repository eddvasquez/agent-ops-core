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
Test 'Claude only spawns the guard for suspicious paths or commands: every handler has an if filter' {
    $home2=NewDir 'home';$state=NewDir 'state'
    $paths=@{StateDir=$state;ClaudeSettingsPath=(Join-Path $home2 '.claude/settings.json');CodexHooksPath=(Join-Path $home2 '.codex/hooks.json');AntigravityHooksPath=(Join-Path $home2 '.gemini/config/hooks.json')}
    Install-AgentOpsSecretGuard @paths|Out-Null
    $c=[IO.File]::ReadAllText($paths.ClaudeSettingsPath)|ConvertFrom-Json
    $handlers=@($c.hooks.PreToolUse|ForEach-Object {@($_.hooks)})
    Assert ($handlers.Count -ge 8 -and -not @($handlers|Where-Object {-not $_.if}).Count) 'Every Claude handler needs an if filter'
    $ifs=@($handlers|ForEach-Object {$_.if})
    foreach($rule in 'Read(//**/.env*)','Edit(//**/.env*)','Read(//**/*secret*)','Bash(*.env*)','PowerShell(*.env*)','Read(//**/*.pem)'){Assert ($ifs -contains $rule) "Missing filter $rule"}
    $x=[IO.File]::ReadAllText($paths.CodexHooksPath)|ConvertFrom-Json
    Assert ($x.hooks.PreToolUse[0].matcher -eq 'Bash|apply_patch|mcp__.*') 'Codex must only run for shell, patches and MCP tools'
}
Test 'an older installation without filters is upgraded in place, without duplicates' {
    $home2=NewDir 'home';$state=NewDir 'state'
    $claude=Join-Path $home2 '.claude/settings.json';[IO.Directory]::CreateDirectory((Split-Path $claude))|Out-Null
    $old='{"hooks":{"PreToolUse":[{"matcher":"Read|Edit","hooks":[{"type":"command","command":"powershell.exe","args":["-File","'+((Join-Path $state 'hooks/agent-ops-hook.ps1') -replace '\\','\\')+'","-Hook","secret-guard","-Harness","claude"],"timeout":15}]}]}}'
    [IO.File]::WriteAllText($claude,$old,$utf8)
    $paths=@{StateDir=$state;ClaudeSettingsPath=$claude;CodexHooksPath=(Join-Path $home2 'x.json');AntigravityHooksPath=(Join-Path $home2 'a.json')}
    $i=Install-AgentOpsSecretGuard @paths
    $c=[IO.File]::ReadAllText($claude)|ConvertFrom-Json
    $handlers=@($c.hooks.PreToolUse|ForEach-Object {@($_.hooks)})
    Assert ($i.Status -eq 'INSTALLED' -and -not @($handlers|Where-Object {-not $_.if}).Count) ($c|ConvertTo-Json -Depth 8)
}
Test 'the launcher answers ordinary actions itself and only runs the guard, and logs it, when something looks like a credential' {
    $state=NewDir 'state';$frame=NewDir 'frame';[IO.Directory]::CreateDirectory((Join-Path $frame 'scripts'))|Out-Null
    $marker=Join-Path $frame 'ran.txt'
    [IO.File]::WriteAllText((Join-Path $frame 'scripts/secret-guard-hook.ps1'),"param([string]`$Harness)`n[IO.File]::WriteAllText('$marker',[IO.File]::ReadAllText(`$env:AGENT_OPS_HOOK_INPUT_FILE))`n'{""decision"":""ask""}'",$utf8)
    [IO.File]::WriteAllText((Join-Path $state 'update-state.json'),(@{Mode='MANAGED';Active=@{Sha=('a'*40);Path=$frame}}|ConvertTo-Json),$utf8)
    Install-AgentOpsSecretGuard -StateDir $state -ClaudeSettingsPath (Join-Path $state 'c.json') -CodexHooksPath (Join-Path $state 'x.json') -AntigravityHooksPath (Join-Path $state 'a.json')|Out-Null
    $launcher=Join-Path $state 'hooks/agent-ops-hook.ps1'
    $run={param($json)
        $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=(Get-Process -Id $PID).Path
        $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+$launcher+'" -Hook secret-guard -Harness antigravity'
        $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true
        $psi.StandardOutputEncoding=New-Object Text.UTF8Encoding($false);$psi.EnvironmentVariables['AGENT_OPS_STATE_DIR']=$state
        $p=[Diagnostics.Process]::Start($psi);$p.StandardInput.Write($json);$p.StandardInput.Close();$o=$p.StandardOutput.ReadToEnd();$null=$p.StandardError.ReadToEnd();$p.WaitForExit();$o.Trim()}
    $plain=& $run '{"toolCall":{"name":"view_file","args":{"AbsolutePath":"C:\\p\\README.md"}}}'
    Assert ($plain -eq '{"decision":"allow"}' -and -not (Test-Path $marker)) "Ordinary action reached the guard: $plain"
    $secret=& $run '{"toolCall":{"name":"view_file","args":{"AbsolutePath":"C:\\p\\.env"}}}'
    Assert ($secret -match 'ask' -and (Test-Path $marker) -and ([IO.File]::ReadAllText($marker) -match '\.env')) "Credential action did not reach the guard with its input: $secret"
    $log=Join-Path $state 'hooks/invocations.log'
    Assert ((Test-Path $log) -and @([IO.File]::ReadAllLines($log)).Count -eq 1 -and ([IO.File]::ReadAllText($log) -match 'secret-guard') -and ([IO.File]::ReadAllText($log) -notmatch 'README|\.env')) 'The log must record one invocation, without paths'
}
Test 'Claude Code also gets native ask rules for credential files; the user''s own rules stay and nothing duplicates' {
    $home2=NewDir 'home';$state=NewDir 'state'
    $claude=Join-Path $home2 '.claude/settings.json';[IO.Directory]::CreateDirectory((Split-Path $claude))|Out-Null
    [IO.File]::WriteAllText($claude,'{"permissions":{"allow":["Bash(npm run test *)"],"ask":["Bash(git push *)"],"deny":["Read(./privado/**)"]}}',$utf8)
    $paths=@{StateDir=$state;ClaudeSettingsPath=$claude;CodexHooksPath=(Join-Path $home2 '.codex/hooks.json');AntigravityHooksPath=(Join-Path $home2 '.gemini/config/hooks.json')}
    Install-AgentOpsSecretGuard @paths|Out-Null
    $c=[IO.File]::ReadAllText($claude)|ConvertFrom-Json
    $ask=@($c.permissions.ask)
    foreach($r in 'Read(//**/.env)','Edit(//**/.env)','Read(//**/.env.production)','Read(//**/*.pem)','Read(//**/id_rsa)','Read(//**/google-ads.yaml)'){Assert ($ask -contains $r) "Missing native rule $r"}
    Assert ($ask -notcontains 'Read(//**/.env.example)' -and @($ask|Where-Object {$_ -match 'example|sample|template'}).Count -eq 0) 'Examples must not be asked'
    Assert ($ask -contains 'Bash(git push *)' -and @($c.permissions.allow) -contains 'Bash(npm run test *)' -and @($c.permissions.deny) -contains 'Read(./privado/**)') 'User rules lost'
    Install-AgentOpsSecretGuard @paths|Out-Null
    $again=@(([IO.File]::ReadAllText($claude)|ConvertFrom-Json).permissions.ask)
    Assert ($again.Count -eq $ask.Count) 'Reinstall duplicated rules'
    Install-AgentOpsSecretGuard @paths -Uninstall|Out-Null
    $c=[IO.File]::ReadAllText($claude)|ConvertFrom-Json
    Assert ((@($c.permissions.ask) -join ',') -eq 'Bash(git push *)' -and @($c.permissions.allow) -contains 'Bash(npm run test *)') ($c|ConvertTo-Json -Depth 5)
}
Test 'Codex gets a permission profile that extends :workspace and denies only private keys, with a backup; uninstall restores the file exactly' {
    $home2=NewDir 'home';$state=NewDir 'state';$codexDir=Join-Path $home2 '.codex';[IO.Directory]::CreateDirectory($codexDir)|Out-Null
    $toml=Join-Path $codexDir 'config.toml'
    $original="model = `"gpt-5`"`n`n[features]`nprefer_mxc = true`n`n[mcp_servers.demo]`ncommand = `"demo`"`n"
    [IO.File]::WriteAllText($toml,$original,$utf8)
    $paths=@{StateDir=$state;ClaudeSettingsPath=(Join-Path $home2 '.claude/settings.json');CodexHooksPath=(Join-Path $codexDir 'hooks.json');AntigravityHooksPath=(Join-Path $home2 '.gemini/config/hooks.json')}
    $i=Install-AgentOpsSecretGuard @paths
    Assert ($i.Code -eq 0) ($i|ConvertTo-Json -Depth 5)
    $t=[IO.File]::ReadAllText($toml)
    $top=$t.Substring(0,$t.IndexOf('[features]'))
    Assert ($top -match '(?m)^default_permissions = "agent-ops"(\s+#[^\r\n]*)?\r?$')"default_permissions must be a top-level key before the first table:`n$t"
    Assert ($t -match '(?m)^\[permissions\.agent-ops\]$' -and $t -match '(?m)^extends = ":workspace"$') $t
    foreach($g in '**/id_rsa','**/*.pfx','**/*.p12','**/*.kdbx','**/*.jks'){Assert ($t.Contains("`"$g`" = `"deny`"")) "Missing deny $g"}
    Assert ($t -notmatch '\.env|google-ads|\.npmrc|\*\.pem') 'Files that programs need were denied'
    Assert ($t.Contains('[mcp_servers.demo]') -and $t.Contains('prefer_mxc = true')) 'User configuration lost'
    Assert (@(Get-ChildItem (Join-Path $state 'backups') -Filter 'codex-config-*.toml').Count -eq 1) 'No backup of config.toml'
    Assert ((Install-AgentOpsSecretGuard @paths).Status -eq 'UP_TO_DATE') 'Second install was not idempotent'
    Install-AgentOpsSecretGuard @paths -Uninstall|Out-Null
    Assert (([IO.File]::ReadAllText($toml) -replace "`r",'') -eq $original) "Uninstall did not restore the original:`n$([IO.File]::ReadAllText($toml))"
}
Test 'Codex configuration with its own sandbox settings is never changed' {
    foreach($own in "sandbox_mode = `"workspace-write`"`n","default_permissions = `"mio`"`n`n[permissions.mio]`nextends = `":workspace`"`n"){
        $home2=NewDir 'home';$state=NewDir 'state';$codexDir=Join-Path $home2 '.codex';[IO.Directory]::CreateDirectory($codexDir)|Out-Null
        $toml=Join-Path $codexDir 'config.toml';[IO.File]::WriteAllText($toml,$own,$utf8)
        $paths=@{StateDir=$state;ClaudeSettingsPath=(Join-Path $home2 '.claude/settings.json');CodexHooksPath=(Join-Path $codexDir 'hooks.json');AntigravityHooksPath=(Join-Path $home2 '.gemini/config/hooks.json')}
        $i=Install-AgentOpsSecretGuard @paths
        Assert ([IO.File]::ReadAllText($toml) -eq $own) 'User sandbox settings were changed'
        Assert ($i.Code -eq 0 -and (@($i.Warnings) -join ' ') -match 'Codex') ('Expected a warning and the rest installed: '+($i|ConvertTo-Json -Depth 5))
        Assert ([IO.File]::Exists($paths.CodexHooksPath)) 'The Codex hook must still be installed'
    }
}
Test 'Codex: a permission request that names a credential is denied with an explanation; anything else is left to the user, never allowed' {
    $run={param($json)
        $psi=New-Object Diagnostics.ProcessStartInfo;$psi.FileName=(Get-Process -Id $PID).Path
        $psi.Arguments='-NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $source 'scripts/permission-request-hook.ps1')+'" -Harness codex'
        $psi.UseShellExecute=$false;$psi.CreateNoWindow=$true;$psi.RedirectStandardInput=$true;$psi.RedirectStandardOutput=$true;$psi.RedirectStandardError=$true;$psi.StandardOutputEncoding=$utf8
        $p=[Diagnostics.Process]::Start($psi);$b=$utf8.GetBytes($json);$p.StandardInput.BaseStream.Write($b,0,$b.Length);$p.StandardInput.Close()
        $o=$p.StandardOutput.ReadToEnd();$null=$p.StandardError.ReadToEnd();$p.WaitForExit();@{Exit=$p.ExitCode;Out=$o.Trim()}}
    $r=& $run '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"cat ~/.ssh/id_rsa","description":"needs to run outside the sandbox"}}'
    $j=$r.Out|ConvertFrom-Json
    Assert ($r.Exit -eq 0 -and $j.hookSpecificOutput.hookEventName -eq 'PermissionRequest' -and $j.hookSpecificOutput.decision.behavior -eq 'deny' -and $j.hookSpecificOutput.decision.message -match 'credenciales') "deny: $($r.Out)"
    $r=& $run '{"hook_event_name":"PermissionRequest","tool_name":"apply_patch","tool_input":{"command":"*** Begin Patch\n*** Update File: .env\n+X=1\n*** End Patch"}}'
    Assert (($r.Out|ConvertFrom-Json).hookSpecificOutput.decision.behavior -eq 'deny') "patch on .env: $($r.Out)"
    $r=& $run '{"hook_event_name":"PermissionRequest","tool_name":"Bash","tool_input":{"command":"npm test"}}'
    Assert ($r.Exit -eq 0 -and -not $r.Out) "ordinary request must be left to the user: $($r.Out)"
    $r=& $run '{roto'
    Assert ($r.Exit -eq 0 -and -not $r.Out) "must not decide on a broken event: $($r.Out)"
    Assert ((Get-Content (Join-Path $source 'scripts/permission-request-hook.ps1') -Raw) -notmatch "behavior='allow'") 'The hook must never allow on the user''s behalf'
}
Test 'install registers the Codex permission request hook, idempotently, and uninstall removes it' {
    $home2=NewDir 'home';$state=NewDir 'state'
    $paths=@{StateDir=$state;ClaudeSettingsPath=(Join-Path $home2 '.claude/settings.json');CodexHooksPath=(Join-Path $home2 '.codex/hooks.json');AntigravityHooksPath=(Join-Path $home2 '.gemini/config/hooks.json')}
    Install-AgentOpsSecretGuard @paths|Out-Null
    $x=[IO.File]::ReadAllText($paths.CodexHooksPath)|ConvertFrom-Json
    $pr=@($x.hooks.PermissionRequest)
    Assert ($pr.Count -eq 1 -and $pr[0].matcher -match 'Bash' -and $pr[0].hooks[0].commandWindows -match '-Hook permission-request -Harness codex') ($x|ConvertTo-Json -Depth 8)
    Assert ((Install-AgentOpsSecretGuard @paths).Status -eq 'UP_TO_DATE') 'Not idempotent'
    Install-AgentOpsSecretGuard @paths -Uninstall|Out-Null
    $x=[IO.File]::ReadAllText($paths.CodexHooksPath)|ConvertFrom-Json
    Assert (-not ($x.PSObject.Properties['hooks'] -and $x.hooks.PSObject.Properties['PermissionRequest'])) 'Uninstall left the hook'
}
Write-Host "Secret guard: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
