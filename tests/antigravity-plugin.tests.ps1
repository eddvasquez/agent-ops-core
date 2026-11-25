# Antigravity plugin: the framework's hooks and rules for Antigravity as one versioned unit in
# ~/.gemini/config/plugins/agent-ops-core (plugin.json, hooks.json, rules/). It replaces the loose entries in
# ~/.gemini/config/hooks.json only after the plugin validated, so Antigravity is never left uncovered or duplicated.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/AntigravityPlugin.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-agplugin-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
function Env{
    $d=Join-Path $script:base ('e-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    $cfg=Join-Path $d '.gemini/config';[IO.Directory]::CreateDirectory((Join-Path $cfg 'plugins'))|Out-Null
    $state=Join-Path $d 'state';[IO.Directory]::CreateDirectory($state)|Out-Null
    # The user's own hook stays; the framework's loose entries are what the plugin replaces.
    $hooks=[ordered]@{'mi-hook'=@{SessionStart=@(@{type='command';command='mi-script'})};'agent-ops-secret-guard'=@{PreToolUse=@()};'agent-ops-session-start'=@{SessionStart=@()};'agent-ops-activity'=@{PostToolUse=@()}}
    [IO.File]::WriteAllText((Join-Path $cfg 'hooks.json'),($hooks|ConvertTo-Json -Depth 8),$utf8)
    return @{Config=$cfg;State=$state}
}
$ok={param($dir) $script:validated=$dir;$true}
$bad={param($dir) $false}

Test 'the plugin bundles the three hooks through the stable launcher and the framework rules' {
    $e=Env
    $r=Install-AgentOpsAntigravityPlugin -StateDir $e.State -ConfigDir $e.Config -Version '9.9.9' -Validator $ok
    Assert ($r.Code -eq 0 -and $r.Status -eq 'INSTALLED') ($r|ConvertTo-Json -Depth 4)
    $root=Join-Path $e.Config 'plugins/agent-ops-core'
    $m=[IO.File]::ReadAllText((Join-Path $root 'plugin.json'))|ConvertFrom-Json
    Assert ($m.name -eq 'agent-ops-core' -and $m.version -eq '9.9.9' -and $m.'$schema' -match 'antigravity') ($m|ConvertTo-Json)
    $h=[IO.File]::ReadAllText((Join-Path $root 'hooks.json'))
    foreach($hook in 'secret-guard','session-start','post-tool'){Assert ($h -match "agent-ops-hook\.ps1.{0,40}-Hook $hook -Harness antigravity") "Missing hook $hook"}
    Assert ($h -notmatch 'Harness claude|Harness codex') 'Only Antigravity entries belong in its plugin'
    $rules=[IO.File]::ReadAllText((Join-Path $root 'rules/AGENTS.md'))
    Assert ($rules -match 'MODO ENTRADA' -and $rules -match 'R-016' -and $rules -match 'R-017') 'Always-on rule missing framework essentials'
    $cred=[IO.File]::ReadAllText((Join-Path $root 'rules/credenciales.md'))
    Assert ($cred -match '(?m)^trigger: glob$' -and $cred -match '\*\*/\.env' -and $cred -notmatch 'example') 'Credential rule must be a glob rule without examples'
    Assert ($script:validated -and $script:validated -like '*aoc-agplugin-*\agent-ops-core') 'The staged plugin must be validated before it is installed'
}
Test 'the loose entries are replaced by the plugin; the user''s own hooks stay' {
    $e=Env
    Install-AgentOpsAntigravityPlugin -StateDir $e.State -ConfigDir $e.Config -Version '9.9.9' -Validator $ok|Out-Null
    $h=[IO.File]::ReadAllText((Join-Path $e.Config 'hooks.json'))|ConvertFrom-Json
    Assert ($h.PSObject.Properties['mi-hook'] -and -not $h.PSObject.Properties['agent-ops-secret-guard'] -and -not $h.PSObject.Properties['agent-ops-session-start'] -and -not $h.PSObject.Properties['agent-ops-activity']) ($h|ConvertTo-Json -Depth 6)
}
Test 'a plugin that fails validation changes nothing' {
    $e=Env;$before=[IO.File]::ReadAllText((Join-Path $e.Config 'hooks.json'))
    $r=Install-AgentOpsAntigravityPlugin -StateDir $e.State -ConfigDir $e.Config -Version '9.9.9' -Validator $bad
    Assert ($r.Code -ne 0 -and $r.Status -eq 'INVALID') ($r|ConvertTo-Json -Depth 4)
    Assert (-not (Test-Path (Join-Path $e.Config 'plugins/agent-ops-core'))) 'An invalid plugin was installed'
    Assert ([IO.File]::ReadAllText((Join-Path $e.Config 'hooks.json')) -eq $before) 'Loose entries were removed without a valid plugin'
}
Test 'installing again is idempotent; a new version updates it; uninstall removes only the plugin' {
    $e=Env
    Install-AgentOpsAntigravityPlugin -StateDir $e.State -ConfigDir $e.Config -Version '9.9.9' -Validator $ok|Out-Null
    Assert ((Install-AgentOpsAntigravityPlugin -StateDir $e.State -ConfigDir $e.Config -Version '9.9.9' -Validator $ok).Status -eq 'UP_TO_DATE') 'Not idempotent'
    $r=Install-AgentOpsAntigravityPlugin -StateDir $e.State -ConfigDir $e.Config -Version '9.10.0' -Validator $ok
    $m=[IO.File]::ReadAllText((Join-Path $e.Config 'plugins/agent-ops-core/plugin.json'))|ConvertFrom-Json
    Assert ($r.Status -eq 'INSTALLED' -and $m.version -eq '9.10.0') 'New version not applied'
    $u=Install-AgentOpsAntigravityPlugin -StateDir $e.State -ConfigDir $e.Config -Uninstall
    Assert ($u.Status -eq 'REMOVED' -and -not (Test-Path (Join-Path $e.Config 'plugins/agent-ops-core'))) ($u|ConvertTo-Json)
    Assert ((([IO.File]::ReadAllText((Join-Path $e.Config 'hooks.json'))|ConvertFrom-Json).PSObject.Properties['mi-hook'])) 'User hook lost on uninstall'
}
Test 'with the plugin present, the other installers no longer add loose Antigravity entries' {
    Import-Module (Join-Path $source 'scripts/SecretGuard.psm1') -Force
    Import-Module (Join-Path $source 'scripts/SessionStart.psm1') -Force
    $e=Env;Install-AgentOpsAntigravityPlugin -StateDir $e.State -ConfigDir $e.Config -Version '9.9.9' -Validator $ok|Out-Null
    $t=Join-Path $script:base ('t-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($t)|Out-Null
    $paths=@{StateDir=$e.State;ClaudeSettingsPath=(Join-Path $t 'c.json');CodexHooksPath=(Join-Path $t 'codex/hooks.json');AntigravityHooksPath=(Join-Path $e.Config 'hooks.json')}
    Install-AgentOpsSecretGuard @paths|Out-Null;Install-AgentOpsSessionStart @paths|Out-Null
    $h=[IO.File]::ReadAllText((Join-Path $e.Config 'hooks.json'))|ConvertFrom-Json
    Assert (-not ($h.PSObject.Properties.Name|Where-Object {$_ -like 'agent-ops-*'})) ('Loose entries came back: '+($h.PSObject.Properties.Name -join ','))
}
if(Get-Command agy -ErrorAction SilentlyContinue){
    Test 'the generated plugin passes agy plugin validate --strict' {
        $e=Env
        $r=Install-AgentOpsAntigravityPlugin -StateDir $e.State -ConfigDir $e.Config -Version '9.9.9'
        Assert ($r.Code -eq 0 -and $r.Status -eq 'INSTALLED') ('agy validation: '+($r|ConvertTo-Json -Depth 4))
    }
}
Write-Host "Antigravity plugin: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
