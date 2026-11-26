# Claude Code plugin: the framework's hooks for Claude Code as one versioned unit in
# StateDir\claude-plugin\agent-ops-core (.claude-plugin/plugin.json, hooks/hooks.json) with a local marketplace
# (.claude-plugin/marketplace.json). It replaces the loose hook entries in ~/.claude/settings.json only after
# validation, marketplace registration and installation succeed, while keeping permissions.ask and user hooks intact.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/ClaudePlugin.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-clplugin-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}

function Env([bool]$enabled=$false){
    $d=Join-Path $script:base ('e-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    $claude=Join-Path $d '.claude';[IO.Directory]::CreateDirectory($claude)|Out-Null
    $state=Join-Path $d 'state';[IO.Directory]::CreateDirectory($state)|Out-Null
    $launcher=Join-Path $state 'hooks/agent-ops-hook.ps1'
    $settings=[ordered]@{
        permissions=[ordered]@{ask=@('Read(//**/.env)')}
        hooks=[ordered]@{
            SessionStart=@(
                [ordered]@{matcher='startup|resume';hooks=@([ordered]@{type='command';command='powershell.exe';args=@('-NoProfile','-File','C:\user\watch notice.ps1')})},
                [ordered]@{matcher='startup|resume|clear|compact';hooks=@([ordered]@{type='command';command='powershell.exe';args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,'-Hook','session-start','-Harness','claude')})}
            )
            PreCompact=@([ordered]@{matcher='manual|auto';hooks=@([ordered]@{type='command';command='powershell.exe';args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,'-Hook','pre-compact','-Harness','claude')})})
            PostToolUse=@([ordered]@{matcher='Edit|Write';hooks=@([ordered]@{type='command';command='powershell.exe';args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,'-Hook','post-tool','-Harness','claude')})})
            SubagentStop=@([ordered]@{hooks=@([ordered]@{type='command';command='powershell.exe';args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,'-Hook','subagent-stop','-Harness','claude')})})
            PreToolUse=@([ordered]@{matcher='Read|Edit';hooks=@([ordered]@{type='command';if='Read(//**/.env)';command='powershell.exe';args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,'-Hook','secret-guard','-Harness','claude')})})
        }
    }
    if($enabled){$settings['enabledPlugins']=[ordered]@{'agent-ops-core@agent-ops'=$true}}
    $sp=Join-Path $claude 'settings.json'
    [IO.File]::WriteAllText($sp,($settings|ConvertTo-Json -Depth 12),$utf8)
    return @{State=$state;Settings=$sp}
}

$script:calls=[System.Collections.ArrayList]::new()
function FakeRunner([string]$mode='ok'){
    $script:calls.Clear()
    $log=$script:calls
    return {
        param([string[]]$a)
        [void]$log.Add(($a -join ' '))
        if($mode -eq 'bad-validate' -and $a[1] -eq 'validate'){return @{Code=1;Output='invalid manifest'}}
        if($mode -eq 'bad-install' -and $a[1] -eq 'install'){return @{Code=1;Output='install failed'}}
        if($a[1] -eq 'validate'){return @{Code=0;Output='Validation passed'}}
        return @{Code=0;Output='OK'}
    }.GetNewClosure()
}

Test 'generates plugin.json, hooks.json and marketplace.json under StateDir\claude-plugin' {
    $e=Env
    $r=Install-AgentOpsClaudePlugin -StateDir $e.State -SettingsPath $e.Settings -Version '9.9.9' -Runner (FakeRunner)
    Assert ($r.Code -eq 0 -and $r.Status -eq 'INSTALLED') ($r|ConvertTo-Json -Depth 4)
    $root=Join-Path $e.State 'claude-plugin/agent-ops-core'
    $m=[IO.File]::ReadAllText((Join-Path $root '.claude-plugin/plugin.json'))|ConvertFrom-Json
    Assert ($m.name -eq 'agent-ops-core' -and $m.version -eq '9.9.9' -and $m.description) ($m|ConvertTo-Json)
    $mp=[IO.File]::ReadAllText((Join-Path $e.State 'claude-plugin/.claude-plugin/marketplace.json'))|ConvertFrom-Json
    Assert ($mp.name -eq 'agent-ops' -and $mp.owner -and (@($mp.plugins|Where-Object {$_.name -eq 'agent-ops-core'}).Count -eq 1)) ($mp|ConvertTo-Json -Depth 4)
    $h=[IO.File]::ReadAllText((Join-Path $root 'hooks/hooks.json'))|ConvertFrom-Json
    foreach($ev in 'SessionStart','PreCompact','PostToolUse','SubagentStop','PreToolUse'){
        Assert ($h.hooks.PSObject.Properties[$ev]) "Missing hook event $ev"
    }
    $hRaw=[IO.File]::ReadAllText((Join-Path $root 'hooks/hooks.json'))
    Assert ($hRaw -notmatch 'Harness codex|Harness antigravity') 'Only Claude Code entries belong in its plugin'
}

Test 'validation failure leaves settings.json untouched and returns FAILED' {
    $e=Env;$before=[IO.File]::ReadAllText($e.Settings)
    $r=Install-AgentOpsClaudePlugin -StateDir $e.State -SettingsPath $e.Settings -Version '9.9.9' -Runner (FakeRunner 'bad-validate')
    Assert ($r.Code -ne 0 -and $r.Status -eq 'FAILED') ($r|ConvertTo-Json -Depth 4)
    Assert ([IO.File]::ReadAllText($e.Settings) -eq $before) 'settings.json changed after failed validation'
}

Test 'removes loose framework hooks while keeping user hooks and permissions.ask' {
    $e=Env;$runner=FakeRunner
    $r=Install-AgentOpsClaudePlugin -StateDir $e.State -SettingsPath $e.Settings -Version '9.9.9' -Runner $runner
    Assert ($r.Code -eq 0) ($r|ConvertTo-Json -Depth 4)
    $sRaw=[IO.File]::ReadAllText($e.Settings)
    Assert ($sRaw -notmatch 'agent-ops-hook\.ps1') 'Loose framework hook entries remained in settings.json'
    $s=$sRaw|ConvertFrom-Json
    Assert (@($s.permissions.ask) -contains 'Read(//**/.env)') 'permissions.ask was lost'
    $ssJson=$s.hooks.SessionStart|ConvertTo-Json -Depth 8
    Assert ($ssJson -match 'watch notice\.ps1') 'User SessionStart hook was removed'
    Assert (($script:calls -join "`n") -match 'plugin validate' -and ($script:calls -join "`n") -match 'plugin marketplace add' -and ($script:calls -join "`n") -match 'plugin install agent-ops-core@agent-ops') ('Unexpected calls: '+($script:calls -join '; '))
}

Test 'second run without changes returns UP_TO_DATE and skips install/update' {
    $e=Env
    Install-AgentOpsClaudePlugin -StateDir $e.State -SettingsPath $e.Settings -Version '9.9.9' -Runner (FakeRunner)|Out-Null
    # Simulate Claude Code enabling the plugin in settings.json on install
    $s=[IO.File]::ReadAllText($e.Settings)|ConvertFrom-Json
    $s|Add-Member -NotePropertyName enabledPlugins -NotePropertyValue ([pscustomobject]@{'agent-ops-core@agent-ops'=$true}) -Force
    [IO.File]::WriteAllText($e.Settings,($s|ConvertTo-Json -Depth 12),$utf8)
    $r=Install-AgentOpsClaudePlugin -StateDir $e.State -SettingsPath $e.Settings -Version '9.9.9' -Runner (FakeRunner)
    Assert ($r.Code -eq 0 -and $r.Status -eq 'UP_TO_DATE') ($r|ConvertTo-Json -Depth 4)
    Assert (-not ($script:calls|Where-Object {$_ -match 'install|update'})) ('Should not install or update when unchanged: '+($script:calls -join '; '))
}

Test 'version bump refreshes marketplace and updates the installed plugin' {
    $e=Env
    Install-AgentOpsClaudePlugin -StateDir $e.State -SettingsPath $e.Settings -Version '9.9.9' -Runner (FakeRunner)|Out-Null
    $s=[IO.File]::ReadAllText($e.Settings)|ConvertFrom-Json
    $s|Add-Member -NotePropertyName enabledPlugins -NotePropertyValue ([pscustomobject]@{'agent-ops-core@agent-ops'=$true}) -Force
    [IO.File]::WriteAllText($e.Settings,($s|ConvertTo-Json -Depth 12),$utf8)
    $r=Install-AgentOpsClaudePlugin -StateDir $e.State -SettingsPath $e.Settings -Version '9.10.0' -Runner (FakeRunner)
    Assert ($r.Code -eq 0 -and $r.Status -eq 'INSTALLED') ($r|ConvertTo-Json -Depth 4)
    $m=[IO.File]::ReadAllText((Join-Path $e.State 'claude-plugin/agent-ops-core/.claude-plugin/plugin.json'))|ConvertFrom-Json
    Assert ($m.version -eq '9.10.0') 'Version did not update'
    Assert (($script:calls -join "`n") -match 'plugin marketplace update agent-ops' -and ($script:calls -join "`n") -match 'plugin update agent-ops-core@agent-ops') ('Expected marketplace update and plugin update: '+($script:calls -join '; '))
}

Test 'uninstall runs claude plugin uninstall and restores loose entries while keeping user hooks' {
    $e=Env -enabled $true
    Install-AgentOpsClaudePlugin -StateDir $e.State -SettingsPath $e.Settings -Version '9.9.9' -Runner (FakeRunner)|Out-Null
    $u=Install-AgentOpsClaudePlugin -StateDir $e.State -SettingsPath $e.Settings -Runner (FakeRunner) -Uninstall
    Assert ($u.Code -eq 0 -and $u.Status -eq 'REMOVED') ($u|ConvertTo-Json -Depth 4)
    Assert (($script:calls -join "`n") -match 'plugin uninstall agent-ops-core@agent-ops') ('Missing uninstall call: '+($script:calls -join '; '))
    $sRaw=[IO.File]::ReadAllText($e.Settings)
    Assert ($sRaw -match 'agent-ops-hook\.ps1' -and $sRaw -match 'watch notice\.ps1') 'Loose entries or user hook missing after uninstall'
}

Test 'with the plugin enabled, SessionStart and SecretGuard no longer add loose Claude entries' {
    Import-Module (Join-Path $source 'scripts/SecretGuard.psm1') -Force
    Import-Module (Join-Path $source 'scripts/SessionStart.psm1') -Force
    $e=Env -enabled $true
    # Remove loose entries first so settings.json has only enabledPlugins + permissions.ask + user hook
    Install-AgentOpsClaudePlugin -StateDir $e.State -SettingsPath $e.Settings -Version '9.9.9' -Runner (FakeRunner)|Out-Null
    $s=[IO.File]::ReadAllText($e.Settings)|ConvertFrom-Json
    $s|Add-Member -NotePropertyName enabledPlugins -NotePropertyValue ([pscustomobject]@{'agent-ops-core@agent-ops'=$true}) -Force
    [IO.File]::WriteAllText($e.Settings,($s|ConvertTo-Json -Depth 12),$utf8)
    $t=Join-Path $script:base ('t-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($t)|Out-Null
    $paths=@{StateDir=$e.State;ClaudeSettingsPath=$e.Settings;CodexHooksPath=(Join-Path $t 'codex/hooks.json');AntigravityHooksPath=(Join-Path $t 'agy/hooks.json')}
    Install-AgentOpsSecretGuard @paths|Out-Null;Install-AgentOpsSessionStart @paths|Out-Null
    $sRaw=[IO.File]::ReadAllText($e.Settings)
    Assert ($sRaw -notmatch 'agent-ops-hook\.ps1') 'Loose Claude entries came back'
    Assert (($sRaw|ConvertFrom-Json).permissions.ask -contains 'Read(//**/.env)') 'permissions.ask lost'
}

Write-Host "Claude plugin: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}