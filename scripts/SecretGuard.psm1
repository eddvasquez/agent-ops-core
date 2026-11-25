Set-StrictMode -Version 2
# Credential guard (before each tool action). One policy for every harness: Claude Code and Antigravity ask the
# user; Codex cannot ask before a tool, so it blocks and the agent explains. Only paths and commands count,
# never the text an agent writes. Installed once per user, so it protects every project on the computer.
Import-Module (Join-Path $PSScriptRoot 'HookIO.psm1') -Force
$script:examples='^\.env\.(example|sample|template|dist)$'
$script:dataExt='^(json|ya?ml|toml|ini|cfg|conf|env|txt|xml|properties)$'
$script:keyExt='^(pem|key|pfx|p12|jks|keystore)$'
$script:names='^(google-ads\.ya?ml|\.npmrc|\.pypirc|\.netrc|\.git-credentials|token\.json)$'

function Test-AgentOpsSecretPath {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Path)
    if(-not $Path){return $false}
    $name=(($Path.Trim().TrimEnd('\','/')) -split '[\\/]')[-1].ToLowerInvariant()
    if(-not $name -or $name -match $script:examples){return $false}
    if($name -eq '.env' -or $name.StartsWith('.env.')){return $true}
    if($name -match $script:names){return $true}
    if($name -match '^id_(rsa|dsa|ecdsa|ed25519)(\.pub)?$'){return $true}
    $ext=$(if($name.Contains('.')){$name.Substring($name.LastIndexOf('.')+1)}else{''})
    if($ext -match $script:keyExt){return $true}
    if($name -match 'credential|secret' -and ($ext -eq '' -or $ext -match $script:dataExt)){return $true}
    return $false
}

# Credential paths named in a shell command (quoted strings and bare words).
function Find-AgentOpsSecretInCommand {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Command)
    if(-not $Command){return @()}
    $tokens=@([regex]::Matches($Command,'"([^"]*)"|''([^'']*)''')|ForEach-Object {if($_.Groups[1].Success){$_.Groups[1].Value}else{$_.Groups[2].Value}})
    $tokens+=@($Command -split '[\s"''`(),;|<>=&]+'|Where-Object {$_})
    return @($tokens|Where-Object {Test-AgentOpsSecretPath $_}|Select-Object -Unique)
}

function Sg-Text($o,[string]$name){if($null -ne $o -and $o.PSObject.Properties[$name]){[string]$o.$name}else{''}}
function Get-AgentOpsToolTargets {
    [CmdletBinding()]
    param([ValidateSet('claude','codex','antigravity')][string]$Harness,$Event)
    $paths=@();$commands=@()
    if($Harness -eq 'antigravity'){
        $args=$(if($Event.PSObject.Properties['toolCall']){$Event.toolCall.args}else{$null})
        foreach($k in 'AbsolutePath','TargetFile','SearchPath','DirectoryPath'){$paths+=Sg-Text $args $k}
        $commands+=Sg-Text $args 'CommandLine'
    }else{
        $tool=Sg-Text $Event 'tool_name';$in=$(if($Event.PSObject.Properties['tool_input']){$Event.tool_input}else{$null})
        if($tool -eq 'apply_patch'){
            foreach($m in [regex]::Matches((Sg-Text $in 'command'),'(?m)^\*\*\* (?:Add File|Update File|Delete File|Move to): (.+?)\s*$')){$paths+=$m.Groups[1].Value}
        }else{
            foreach($k in 'file_path','notebook_path','path'){$paths+=Sg-Text $in $k}
            $commands+=Sg-Text $in 'command'
        }
    }
    $hits=@($paths|Where-Object {Test-AgentOpsSecretPath $_})
    foreach($c in $commands){$hits+=@(Find-AgentOpsSecretInCommand $c)}
    return @($hits|Where-Object {$_}|Select-Object -Unique)
}

function Get-AgentOpsSecretDecision {
    [CmdletBinding()]
    param([ValidateSet('claude','codex','antigravity')][string]$Harness,$Event)
    $targets=@(Get-AgentOpsToolTargets -Harness $Harness -Event $Event)
    if(-not $targets.Count){return [pscustomobject]@{Decision='ALLOW';Reason='';Targets=@()}}
    $list=$targets -join ', '
    if($Harness -eq 'codex'){
        return [pscustomobject]@{Decision='DENY';Targets=$targets;Reason="Agent Ops protege los archivos de credenciales ($list) y Codex no permite preguntar antes de actuar: explica al usuario qué necesitas de ese archivo y pídele que lo haga él o que te lo autorice."}
    }
    return [pscustomobject]@{Decision='ASK';Targets=$targets;Reason="Agent Ops protege los archivos de credenciales ($list). ¿Permites esta acción?"}
}

# --- Per-user installation in the three harnesses -------------------------------------------------------
# The shared launcher lives in HookIO (Install-AgentOpsHookLauncher).
# Claude: one filtered handler per suspicious pattern, so ordinary actions never start a process.
$script:pathGlobs=@('.env*','*secret*','*Secret*','*SECRET*','*credential*','*Credential*','*CREDENTIAL*','*.pem','*.key','*.pfx','*.p12','*.jks','*.keystore','id_rsa*','id_dsa*','id_ecdsa*','id_ed25519*','google-ads.y*ml','.npmrc','.pypirc','.netrc','token.json')
$script:commandWords=@('.env','secret','Secret','SECRET','credential','Credential','CREDENTIAL','.pem','.key','.pfx','.p12','.jks','keystore','id_rsa','id_dsa','id_ecdsa','id_ed25519','google-ads','.npmrc','.pypirc','.netrc','token.json')
function Sg-ClaudeGroup([string]$launcher){
    $runArgs=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,'-Hook','secret-guard','-Harness','claude')
    $rules=@();foreach($g in $script:pathGlobs){$rules+="Read(//**/$g)";$rules+="Edit(//**/$g)"}
    foreach($w in $script:commandWords){$rules+="Bash(*$w*)";$rules+="PowerShell(*$w*)"}
    [ordered]@{matcher='Read|Edit|MultiEdit|Write|NotebookEdit|Bash|PowerShell';hooks=@($rules|ForEach-Object {[ordered]@{type='command';if=$_;command='powershell.exe';args=$runArgs;timeout=15}})}
}
function Sg-Without($list,[string]$marker){,@($list|Where-Object {($_|ConvertTo-Json -Depth 12 -Compress) -notmatch [regex]::Escape($marker)})}

# Native rules (no process at all). Claude Code: "ask" rules only affect the agent's own file tools, so the list can
# be broad; examples (.env.example…) are left out so they never prompt. The hook still covers commands and the rest.
$script:nativeClaude=@('.env','.env.local','.env.*.local','.env.production','.env.prod','.env.staging','.env.development','.env.dev','.env.test',
    '*.pem','*.key','*.pfx','*.p12','*.jks','*.keystore','*.kdbx','id_rsa','id_dsa','id_ecdsa','id_ed25519',
    'google-ads.yaml','google-ads.yml','.npmrc','.pypirc','.netrc','.htpasswd','token.json','credentials.json','client_secret*.json',
    'secrets.yaml','secrets.yml','secrets.json','service-account*.json','*.tfstate','*.tfvars')
function Sg-NativeClaudeRules{,@(foreach($g in $script:nativeClaude){"Read(//**/$g)";"Edit(//**/$g)"})}
# Codex: a sandbox deny also stops every program Codex runs, so only private keys, which ordinary programs never read
# (decided by the user, 2026-11-25). .env, google-ads.yaml, .npmrc or .pem stay with the hook (block and explain).
$script:nativeCodex=@('**/id_rsa','**/id_dsa','**/id_ecdsa','**/id_ed25519','**/*.pfx','**/*.p12','**/*.jks','**/*.keystore','**/*.kdbx')
$script:codexTop='default_permissions = "agent-ops"  # agent-ops-core: credenciales'
$script:codexBegin='# >>> agent-ops-core: perfil de credenciales (gestionado; se quita con install-secret-guard.ps1 -Uninstall)'
$script:codexEnd='# <<< agent-ops-core'
function Sg-CodexBlock([string]$n){
    $lines=@($script:codexBegin,'[permissions.agent-ops]','description = "Como :workspace, sin leer claves privadas (Agent Ops Core)"','extends = ":workspace"','',
        '[permissions.agent-ops.filesystem.":workspace_roots"]','"." = "write"')
    foreach($g in $script:nativeCodex){$lines+="`"$g`" = `"deny`""}
    $lines+=$script:codexEnd
    return ($lines -join $n)+$n
}
function Sg-CodexStrip([string]$t){
    $t=[regex]::Replace($t,'(?m)^default_permissions = "agent-ops"  # agent-ops-core: credenciales\r?\n','')
    return [regex]::Replace($t,'\r?\n'+[regex]::Escape($script:codexBegin)+'[\s\S]*?'+[regex]::Escape($script:codexEnd)+'\r?\n','')
}
# Returns @{Text;Warning}: the new config.toml text, or the unchanged one with a warning when the user manages the sandbox.
function Sg-CodexConfig([string]$current,[bool]$remove){
    $base=Sg-CodexStrip $current
    if($remove){return @{Text=$base;Warning=$null}}
    if($base -match '(?m)^\s*(sandbox_mode|default_permissions)\s*=' -or $base -match '(?m)^\s*\[sandbox_workspace_write\]'){
        return @{Text=$current;Warning='Codex: config.toml ya define su propio aislamiento (sandbox_mode o default_permissions); no se cambia. Las claves privadas siguen protegidas por el hook.'}
    }
    $n=$(if($base.Contains("`r`n")){"`r`n"}else{"`n"})
    if($base -and -not $base.EndsWith("`n")){$base+=$n}
    $m=[regex]::Match($base,'(?m)^\s*\[')
    $text=$(if($m.Success){$base.Substring(0,$m.Index)+$script:codexTop+$n+$base.Substring($m.Index)}else{$base+$script:codexTop+$n})
    $text+=$n+(Sg-CodexBlock $n)
    $warn=$(if($base -match '(?m)^\s*sandbox\s*=\s*"unelevated"'){'Codex: con el aislamiento "unelevated" de Windows la negación de lectura no se aplica; el hook sigue protegiendo.'}else{$null})
    return @{Text=$text;Warning=$warn}
}

function Install-AgentOpsSecretGuard {
    [CmdletBinding()]
    param([string]$StateDir=(Join-Path $env:LOCALAPPDATA 'AgentOps'),
          [string]$ClaudeSettingsPath=(Join-Path $HOME '.claude/settings.json'),
          [string]$CodexHooksPath=$(if($env:CODEX_HOME){Join-Path $env:CODEX_HOME 'hooks.json'}else{Join-Path $HOME '.codex/hooks.json'}),
          [string]$AntigravityHooksPath=(Join-Path $HOME '.gemini/config/hooks.json'),
          [string]$CodexConfigPath='',
          [switch]$Uninstall)
    $res=[ordered]@{Code=0;Status='UP_TO_DATE';Files=@();Issues=@();Warnings=@()}
    # Next to the Codex hooks file, so a test (or another CODEX_HOME) never touches the real configuration.
    if(-not $CodexConfigPath){$CodexConfigPath=Join-Path (Split-Path -Parent $CodexHooksPath) 'config.toml'}
    try{
        $launcher=Join-Path $StateDir 'hooks/agent-ops-hook.ps1'
        $marker='secret-guard'
        $win={param($h) "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$launcher`" -Hook secret-guard -Harness $h"}
        $changed=@()
        $edit={param([string]$path,[scriptblock]$change)
            $c=Read-AgentOpsJsonFile $path;$before=$c|ConvertTo-Json -Depth 12 -Compress
            $c=& $change $c
            if(($c|ConvertTo-Json -Depth 12 -Compress) -ne $before){Write-AgentOpsJsonFile $path $c;$script:changedFiles+=@($path)}
        }
        $script:changedFiles=@()
        if(-not $Uninstall){$l=Install-AgentOpsHookLauncher -StateDir $StateDir;if($l.Changed){$script:changedFiles+=@($l.Path)}}
        # Each entry is rebuilt from scratch: older versions are replaced, never duplicated, and only real changes are written.
        $swap={param($c,$entry)
            if(-not $c.Contains('hooks')){$c['hooks']=[ordered]@{}}
            $list=$(if($c['hooks'].Contains('PreToolUse')){Sg-Without @($c['hooks']['PreToolUse']) $marker}else{@()})
            if($entry){$list=@($list)+@($entry)}
            if(@($list).Count){$c['hooks']['PreToolUse']=@($list)}elseif($c['hooks'].Contains('PreToolUse')){$c['hooks'].Remove('PreToolUse')}
            return $c}
        & $edit $ClaudeSettingsPath {param($c)
            $c=& $swap $c $(if($Uninstall){$null}else{Sg-ClaudeGroup $launcher})
            $ours=Sg-NativeClaudeRules
            if(-not $c.Contains('permissions')){$c['permissions']=[ordered]@{}}
            $ask=@($(if($c['permissions'].Contains('ask')){@($c['permissions']['ask'])}else{@()})|Where-Object {$ours -notcontains $_})
            if(-not $Uninstall){$ask=@($ask)+@($ours)}
            if(@($ask).Count){$c['permissions']['ask']=@($ask)}elseif($c['permissions'].Contains('ask')){$c['permissions'].Remove('ask')}
            if(-not $c['permissions'].Count){$c.Remove('permissions')}
            return $c}
        & $edit $CodexHooksPath {param($c)
            $c=& $swap $c $(if($Uninstall){$null}else{[ordered]@{matcher='Bash|apply_patch|mcp__.*';hooks=@([ordered]@{type='command';command="pwsh -NoProfile -File `"$($launcher -replace '\\','/')`" -Hook secret-guard -Harness codex";commandWindows=(& $win 'codex');timeout=15})}})
            # When Codex asks for approval (for example to leave the sandbox), a request that names a credential is denied too.
            $existing=$(if($c['hooks'].Contains('PermissionRequest')){@($c['hooks']['PermissionRequest'])}else{@()})
            $list=@($existing|Where-Object {$_ -and (($_|ConvertTo-Json -Depth 12 -Compress) -notmatch 'permission-request')})
            if(-not $Uninstall){$list=@($list)+@([ordered]@{matcher='Bash|apply_patch|mcp__.*';hooks=@([ordered]@{type='command';command="pwsh -NoProfile -File `"$($launcher -replace '\\','/')`" -Hook permission-request -Harness codex";commandWindows="powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$launcher`" -Hook permission-request -Harness codex";timeout=15})})}
            if(@($list).Count){$c['hooks']['PermissionRequest']=@($list)}else{$c['hooks'].Remove('PermissionRequest')}
            if(-not $c['hooks'].Count){$c.Remove('hooks')}
            return $c}
        & $edit $AntigravityHooksPath {param($c)
            if($c.Contains('agent-ops-secret-guard')){$c.Remove('agent-ops-secret-guard')}
            if(-not $Uninstall){$c['agent-ops-secret-guard']=[ordered]@{PreToolUse=@([ordered]@{matcher='view_file|write_to_file|replace_file_content|multi_replace_file_content|run_command|grep_search';hooks=@([ordered]@{type='command';command=(& $win 'antigravity');timeout=15})})}}
            return $c}
        # Codex native profile (text edit of config.toml: top-level key before the first table, block at the end).
        $current=$(if([IO.File]::Exists($CodexConfigPath)){[IO.File]::ReadAllText($CodexConfigPath)}else{''})
        $codex=Sg-CodexConfig $current ([bool]$Uninstall)
        if($codex.Warning){$res.Warnings=@($res.Warnings)+@($codex.Warning)}
        if($codex.Text -ne $current){
            if($current){$backups=Join-Path $StateDir 'backups';[IO.Directory]::CreateDirectory($backups)|Out-Null;[IO.File]::WriteAllText((Join-Path $backups ('codex-config-'+[datetime]::UtcNow.ToString('yyyyMMddTHHmmssfff')+'.toml')),$current,(New-Object Text.UTF8Encoding($false)))}
            [IO.Directory]::CreateDirectory((Split-Path -Parent $CodexConfigPath))|Out-Null
            [IO.File]::WriteAllText($CodexConfigPath,$codex.Text,(New-Object Text.UTF8Encoding($false)));$script:changedFiles+=@($CodexConfigPath)
        }
        $res.Files=@($script:changedFiles)
        if($script:changedFiles.Count){$res.Status=$(if($Uninstall){'REMOVED'}else{'INSTALLED'})}elseif($Uninstall){$res.Status='NOT_INSTALLED'}
    }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($_.Exception.Message)}
    return [pscustomobject]$res
}
Export-ModuleMember -Function Test-AgentOpsSecretPath,Find-AgentOpsSecretInCommand,Get-AgentOpsToolTargets,Get-AgentOpsSecretDecision,Install-AgentOpsSecretGuard
