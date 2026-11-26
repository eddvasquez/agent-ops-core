Set-StrictMode -Version 2
# Claude Code plugin of the framework: its hooks (SessionStart, PreCompact, PostToolUse, SubagentStop, PreToolUse)
# as one versioned unit in StateDir\claude-plugin\agent-ops-core with a local marketplace. The hooks.json is built
# by the same installers that write the loose entries (one source of truth). Validation, marketplace registration
# and installation must all succeed before the loose entries in ~/.claude/settings.json are removed.
Import-Module (Join-Path $PSScriptRoot 'HookIO.psm1')
Import-Module (Join-Path $PSScriptRoot 'SecretGuard.psm1')
Import-Module (Join-Path $PSScriptRoot 'SessionStart.psm1')
$script:name='agent-ops-core'
$script:market='agent-ops'
$script:pluginId='agent-ops-core@agent-ops'
$script:utf8=New-Object Text.UTF8Encoding($false)

function Cp-DefaultRunner([string[]]$a){
    $ErrorActionPreference='Continue'
    $o=& claude @a 2>&1|Out-String
    return @{Code=$LASTEXITCODE;Output=$o}
}
function Cp-Files([string]$dir){
    $map=@{};if(-not [IO.Directory]::Exists($dir)){return $map}
    foreach($f in Get-ChildItem -LiteralPath $dir -Recurse -File){$map[$f.FullName.Substring($dir.Length+1).Replace('\','/')]=[IO.File]::ReadAllText($f.FullName)}
    return $map
}
function Cp-Same($a,$b){
    if($a.Count -ne $b.Count){return $false}
    foreach($k in $a.Keys){if(-not $b.ContainsKey($k) -or $b[$k] -ne $a[$k]){return $false}}
    return $true
}
function Cp-PluginEnabled($cfg){
    return ($cfg.Contains('enabledPlugins') -and $cfg['enabledPlugins'] -is [System.Collections.IDictionary] -and $cfg['enabledPlugins'].Contains($script:pluginId) -and [bool]$cfg['enabledPlugins'][$script:pluginId])
}
function Cp-HasLooseHooks($cfg){
    if(-not $cfg.Contains('hooks') -or -not ($cfg['hooks'] -is [System.Collections.IDictionary])){return $false}
    foreach($k in $cfg['hooks'].Keys){
        $json=@($cfg['hooks'][$k])|ConvertTo-Json -Depth 12 -Compress
        if($json -match 'agent-ops-hook\.ps1'){return $true}
    }
    return $false
}

function Install-AgentOpsClaudePlugin {
    [CmdletBinding()]
    param([string]$StateDir=(Join-Path $env:LOCALAPPDATA 'AgentOps'),
          [string]$SettingsPath=(Join-Path $HOME '.claude/settings.json'),
          [scriptblock]$Runner,
          [string]$Version='',
          [switch]$Uninstall)
    $res=[ordered]@{Code=0;Status='UP_TO_DATE';Plugin='';Issues=@()}
    if(-not $Runner){$Runner=${function:Cp-DefaultRunner}}
    $mpTarget=Join-Path $StateDir 'claude-plugin'
    $pluginTarget=Join-Path $mpTarget $script:name
    $res.Plugin=$pluginTarget
    if($Uninstall){
        try{
            $ur=& $Runner @('plugin','uninstall',$script:pluginId)
            $c=Read-AgentOpsJsonFile $SettingsPath
            if($c.Contains('enabledPlugins') -and $c['enabledPlugins'] -is [System.Collections.IDictionary] -and $c['enabledPlugins'].Contains($script:pluginId)){
                $c['enabledPlugins'].Remove($script:pluginId)
                if(-not $c['enabledPlugins'].Count){$c.Remove('enabledPlugins')}
                Write-AgentOpsJsonFile $SettingsPath $c
            }
            $work=Join-Path ([IO.Path]::GetTempPath()) ('aoc-clplugin-un-'+[guid]::NewGuid().ToString('N').Substring(0,10))
            [IO.Directory]::CreateDirectory($work)|Out-Null
            try{
                $p=@{StateDir=$StateDir;ClaudeSettingsPath=$SettingsPath;CodexHooksPath=(Join-Path $work 'codex/hooks.json');AntigravityHooksPath=(Join-Path $work 'agy/hooks.json')}
                Install-AgentOpsSecretGuard @p|Out-Null
                Install-AgentOpsSessionStart @p|Out-Null
            }finally{Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}
            if($ur.Code -ne 0){$res.Code=1;$res.Status='FAILED';$res.Issues=@("claude plugin uninstall failed: $($ur.Output)")}
            else{$res.Status='REMOVED'}
        }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($_.Exception.Message)}
        return [pscustomobject]$res
    }
    if(-not $Version){$v=Join-Path $PSScriptRoot '../docs/VERSION';$Version=$(if([IO.File]::Exists($v)){[IO.File]::ReadAllText($v).Trim()}else{'0.0.0'})}
    $work=Join-Path ([IO.Path]::GetTempPath()) ('aoc-clplugin-'+[guid]::NewGuid().ToString('N').Substring(0,12))
    $stageMp=Join-Path $work 'claude-plugin'
    $stagePlugin=Join-Path $stageMp $script:name
    $scratch=Join-Path $work 'scratch'
    try{
        [IO.Directory]::CreateDirectory((Join-Path $stagePlugin '.claude-plugin'))|Out-Null
        [IO.Directory]::CreateDirectory((Join-Path $stagePlugin 'hooks'))|Out-Null
        [IO.Directory]::CreateDirectory((Join-Path $stageMp '.claude-plugin'))|Out-Null
        [IO.Directory]::CreateDirectory($scratch)|Out-Null
        $tempClaude=Join-Path $scratch 'claude.json'
        $p=@{StateDir=$StateDir;ClaudeSettingsPath=$tempClaude;CodexHooksPath=(Join-Path $scratch 'codex/hooks.json');AntigravityHooksPath=(Join-Path $scratch 'agy/hooks.json')}
        foreach($r in @((Install-AgentOpsSecretGuard @p),(Install-AgentOpsSessionStart @p))){if($r.Code -ne 0){throw ('Hook generation failed: '+(@($r.Issues) -join '; '))}}
        $gen=Read-AgentOpsJsonFile $tempClaude
        $hooksObj=[ordered]@{hooks=$(if($gen.Contains('hooks')){$gen['hooks']}else{[ordered]@{}})}
        [IO.File]::WriteAllText((Join-Path $stagePlugin 'hooks/hooks.json'),($hooksObj|ConvertTo-Json -Depth 12),$script:utf8)
        $manifest=[ordered]@{name=$script:name;version=$Version;description='Agent Ops Core hooks for Claude Code: session start, pre-compact, post-tool activity, subagent stop and credential guard.'}
        [IO.File]::WriteAllText((Join-Path $stagePlugin '.claude-plugin/plugin.json'),($manifest|ConvertTo-Json -Depth 4),$script:utf8)
        $marketplace=[ordered]@{name=$script:market;owner=[ordered]@{name='Agent Ops Core'};plugins=@([ordered]@{name=$script:name;source="./$script:name"})}
        [IO.File]::WriteAllText((Join-Path $stageMp '.claude-plugin/marketplace.json'),($marketplace|ConvertTo-Json -Depth 6),$script:utf8)
        $vr=& $Runner @('plugin','validate',$stagePlugin)
        if($vr.Code -ne 0){$res.Code=1;$res.Status='FAILED';$res.Issues=@("claude plugin validate failed: $($vr.Output)");return [pscustomobject]$res}
        $sameFiles=Cp-Same (Cp-Files $stageMp) (Cp-Files $mpTarget)
        $cfg=Read-AgentOpsJsonFile $SettingsPath
        $enabled=Cp-PluginEnabled $cfg
        $hasLoose=Cp-HasLooseHooks $cfg
        if($sameFiles -and $enabled -and -not $hasLoose){return [pscustomobject]$res}
        if(-not $sameFiles){
            if([IO.Directory]::Exists($mpTarget)){Remove-Item -LiteralPath $mpTarget -Recurse -Force}
            [IO.Directory]::CreateDirectory((Split-Path $mpTarget))|Out-Null
            Move-Item -LiteralPath $stageMp -Destination $mpTarget
        }
        if($enabled){
            $mr=& $Runner @('plugin','marketplace','update',$script:market)
            if($mr.Code -ne 0){throw "claude plugin marketplace update failed: $($mr.Output)"}
            $ir=& $Runner @('plugin','update',$script:pluginId)
            if($ir.Code -ne 0){throw "claude plugin update failed: $($ir.Output)"}
        }else{
            $mr=& $Runner @('plugin','marketplace','add',$mpTarget)
            if($mr.Code -ne 0){throw "claude plugin marketplace add failed: $($mr.Output)"}
            $ir=& $Runner @('plugin','install',$script:pluginId)
            if($ir.Code -ne 0){throw "claude plugin install failed: $($ir.Output)"}
        }
        # Only after validation and installation/update succeed, strip loose framework hooks from settings.json.
        $cfg=Read-AgentOpsJsonFile $SettingsPath
        if($cfg.Contains('hooks') -and $cfg['hooks'] -is [System.Collections.IDictionary]){
            $changed=$false
            foreach($ev in @($cfg['hooks'].Keys)){
                $kept=Select-AgentOpsEntriesWithout @($cfg['hooks'][$ev]) 'agent-ops-hook.ps1'
                if(@($kept).Count -ne @($cfg['hooks'][$ev]).Count){$changed=$true}
                if(@($kept).Count){$cfg['hooks'][$ev]=@($kept)}else{$cfg['hooks'].Remove($ev)}
            }
            if(-not $cfg['hooks'].Count){$cfg.Remove('hooks')}
            if($changed){Write-AgentOpsJsonFile $SettingsPath $cfg}
        }
        $res.Status='INSTALLED'
    }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($_.Exception.Message)}
    finally{if([IO.Directory]::Exists($work)){Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}}
    return [pscustomobject]$res
}
Export-ModuleMember -Function Install-AgentOpsClaudePlugin