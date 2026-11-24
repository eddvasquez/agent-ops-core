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
$script:launcher=@'
# agent-ops hook launcher v1. Managed by Agent Ops: runs a hook of the active, verified release.
param([Parameter(Mandatory=$true)][string]$Hook,[Parameter(Mandatory=$true)][string]$Harness)
$stateDir=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'})
$frame=$null
try{
    $s=[IO.File]::ReadAllText((Join-Path $stateDir 'update-state.json'))|ConvertFrom-Json
    if($s.Active -and $s.Active.Path){$frame=[string]$s.Active.Path}
    elseif($s.Mode -eq 'LOCAL_DEV' -and $s.Config -and $s.Config.InstallRoot){$frame=[string]$s.Config.InstallRoot}
}catch{}
$script=$(if($frame -and $Hook -match '^[a-z-]+$'){Join-Path $frame "scripts/$Hook-hook.ps1"}else{$null})
if(-not $script -or -not (Test-Path -LiteralPath $script -PathType Leaf)){
    if($Harness -eq 'antigravity'){$b=[Text.Encoding]::UTF8.GetBytes('{"decision":"allow"}');$o=[Console]::OpenStandardOutput();$o.Write($b,0,$b.Length);$o.Flush()}
    exit 0
}
& $script -Harness $Harness
exit $LASTEXITCODE
'@
function Sg-Has($list,[string]$marker){@($list|Where-Object {($_|ConvertTo-Json -Depth 12 -Compress) -match [regex]::Escape($marker)}).Count -gt 0}
function Sg-Without($list,[string]$marker){,@($list|Where-Object {($_|ConvertTo-Json -Depth 12 -Compress) -notmatch [regex]::Escape($marker)})}

function Install-AgentOpsSecretGuard {
    [CmdletBinding()]
    param([string]$StateDir=(Join-Path $env:LOCALAPPDATA 'AgentOps'),
          [string]$ClaudeSettingsPath=(Join-Path $HOME '.claude/settings.json'),
          [string]$CodexHooksPath=$(if($env:CODEX_HOME){Join-Path $env:CODEX_HOME 'hooks.json'}else{Join-Path $HOME '.codex/hooks.json'}),
          [string]$AntigravityHooksPath=(Join-Path $HOME '.gemini/config/hooks.json'),
          [switch]$Uninstall)
    $res=[ordered]@{Code=0;Status='UP_TO_DATE';Files=@();Issues=@()}
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
        if(-not $Uninstall){
            $text=($script:launcher -replace "`r",'')
            if(-not [IO.File]::Exists($launcher) -or ([IO.File]::ReadAllText($launcher) -replace "`r",'').TrimStart([char]0xFEFF) -ne $text){
                [IO.Directory]::CreateDirectory((Split-Path $launcher))|Out-Null;[IO.File]::WriteAllText($launcher,$text,(New-Object Text.UTF8Encoding($true)));$script:changedFiles+=@($launcher)
            }
        }
        & $edit $ClaudeSettingsPath {param($c)
            if(-not $c.Contains('hooks')){$c['hooks']=[ordered]@{}}
            $list=$(if($c['hooks'].Contains('PreToolUse')){@($c['hooks']['PreToolUse'])}else{@()})
            if($Uninstall){$list=Sg-Without $list $marker}
            elseif(-not (Sg-Has $list $marker)){$list+=@([ordered]@{matcher='Read|Edit|MultiEdit|Write|NotebookEdit|Bash|PowerShell|Grep';hooks=@([ordered]@{type='command';command='powershell.exe';args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,'-Hook','secret-guard','-Harness','claude');timeout=15})})}
            if(@($list).Count){$c['hooks']['PreToolUse']=@($list)}elseif($c['hooks'].Contains('PreToolUse')){$c['hooks'].Remove('PreToolUse')}
            return $c}
        & $edit $CodexHooksPath {param($c)
            if(-not $c.Contains('hooks')){$c['hooks']=[ordered]@{}}
            $list=$(if($c['hooks'].Contains('PreToolUse')){@($c['hooks']['PreToolUse'])}else{@()})
            if($Uninstall){$list=Sg-Without $list $marker}
            elseif(-not (Sg-Has $list $marker)){$list+=@([ordered]@{hooks=@([ordered]@{type='command';command="pwsh -NoProfile -File `"$($launcher -replace '\\','/')`" -Hook secret-guard -Harness codex";commandWindows=(& $win 'codex');timeout=15})})}
            if(@($list).Count){$c['hooks']['PreToolUse']=@($list)}elseif($c['hooks'].Contains('PreToolUse')){$c['hooks'].Remove('PreToolUse')}
            return $c}
        & $edit $AntigravityHooksPath {param($c)
            if($Uninstall){if($c.Contains('agent-ops-secret-guard')){$c.Remove('agent-ops-secret-guard')}}
            elseif(-not $c.Contains('agent-ops-secret-guard')){$c['agent-ops-secret-guard']=[ordered]@{PreToolUse=@([ordered]@{matcher='view_file|write_to_file|replace_file_content|multi_replace_file_content|run_command|grep_search';hooks=@([ordered]@{type='command';command=(& $win 'antigravity');timeout=15})})}}
            return $c}
        $res.Files=@($script:changedFiles)
        if($script:changedFiles.Count){$res.Status=$(if($Uninstall){'REMOVED'}else{'INSTALLED'})}elseif($Uninstall){$res.Status='NOT_INSTALLED'}
    }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($_.Exception.Message)}
    return [pscustomobject]$res
}
Export-ModuleMember -Function Test-AgentOpsSecretPath,Find-AgentOpsSecretInCommand,Get-AgentOpsToolTargets,Get-AgentOpsSecretDecision,Install-AgentOpsSecretGuard
