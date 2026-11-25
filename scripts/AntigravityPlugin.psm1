Set-StrictMode -Version 2
# Antigravity plugin of the framework: its hooks (session start, credential guard, activity) and rules as one versioned
# unit in ~/.gemini/config/plugins/agent-ops-core. The hooks.json is produced by the same installers that write the
# loose entries (one source of truth), the plugin is validated (agy plugin validate --strict when agy exists) and only
# then the loose entries in ~/.gemini/config/hooks.json are removed: Antigravity is never left uncovered or duplicated.
Import-Module (Join-Path $PSScriptRoot 'HookIO.psm1')
Import-Module (Join-Path $PSScriptRoot 'SecretGuard.psm1')
Import-Module (Join-Path $PSScriptRoot 'SessionStart.psm1')
$script:name='agent-ops-core'
$script:loose=@('agent-ops-secret-guard','agent-ops-session-start','agent-ops-activity')

function Ap-DefaultValidator([string]$dir){
    $agy=Get-Command agy -ErrorAction SilentlyContinue
    if(-not $agy){return $true}
    $ErrorActionPreference='Continue'
    & $agy.Source plugin validate $dir --strict *>$null  # the path goes first: agy reads the first argument as the plugin path
    return ($LASTEXITCODE -eq 0)
}
function Ap-Files([string]$dir){
    $map=@{};if(-not [IO.Directory]::Exists($dir)){return $map}
    foreach($f in Get-ChildItem -LiteralPath $dir -Recurse -File){$map[$f.FullName.Substring($dir.Length+1).Replace('\','/')]=[IO.File]::ReadAllText($f.FullName)}
    return $map
}
function Ap-Same($a,$b){
    if($a.Count -ne $b.Count){return $false}
    foreach($k in $a.Keys){if(-not $b.ContainsKey($k) -or $b[$k] -ne $a[$k]){return $false}}
    return $true
}

function Install-AgentOpsAntigravityPlugin {
    [CmdletBinding()]
    param([string]$StateDir=(Join-Path $env:LOCALAPPDATA 'AgentOps'),
          [string]$ConfigDir=(Join-Path $HOME '.gemini/config'),
          [string]$Version='',[scriptblock]$Validator,[switch]$Uninstall)
    $res=[ordered]@{Code=0;Status='UP_TO_DATE';Plugin=$null;Issues=@()}
    $target=Join-Path $ConfigDir "plugins/$script:name";$res.Plugin=$target
    $hooksPath=Join-Path $ConfigDir 'hooks.json'
    if($Uninstall){
        $manifest=Join-Path $target 'plugin.json'
        if([IO.File]::Exists($manifest) -and (([IO.File]::ReadAllText($manifest)|ConvertFrom-Json).name -eq $script:name)){Remove-Item -LiteralPath $target -Recurse -Force;$res.Status='REMOVED'}else{$res.Status='NOT_INSTALLED'}
        return [pscustomobject]$res
    }
    if(-not $Version){$v=Join-Path $PSScriptRoot '../docs/VERSION';$Version=$(if([IO.File]::Exists($v)){[IO.File]::ReadAllText($v).Trim()}else{'0.0.0'})}
    if(-not $Validator){$Validator=${function:Ap-DefaultValidator}}
    $work=Join-Path ([IO.Path]::GetTempPath()) ('aoc-agplugin-'+[guid]::NewGuid().ToString('N').Substring(0,12))
    $stage=Join-Path $work $script:name;$scratch=Join-Path $work 'scratch'
    try{
        [IO.Directory]::CreateDirectory($stage)|Out-Null;[IO.Directory]::CreateDirectory($scratch)|Out-Null
        # Same installers as the loose entries, pointed at the plugin's hooks.json (Claude/Codex files go to scratch).
        $p=@{StateDir=$StateDir;ClaudeSettingsPath=(Join-Path $scratch 'claude.json');CodexHooksPath=(Join-Path $scratch 'codex/hooks.json');AntigravityHooksPath=(Join-Path $stage 'hooks.json')}
        foreach($r in @((Install-AgentOpsSecretGuard @p),(Install-AgentOpsSessionStart @p))){if($r.Code -ne 0){throw ('Hook generation failed: '+(@($r.Issues) -join '; '))}}
        $manifest=[ordered]@{'$schema'='https://antigravity.google/schemas/v1/plugin.json';name=$script:name;displayName='Agent Ops Core';version=$Version;description='Protocolos de Agent Ops Core en Antigravity: aviso al empezar la sesión, protección de credenciales, registro de actividad y reglas del marco.'}
        [IO.File]::WriteAllText((Join-Path $stage 'plugin.json'),($manifest|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
        $rules=Join-Path $PSScriptRoot '../templates/antigravity-plugin/rules'
        [IO.Directory]::CreateDirectory((Join-Path $stage 'rules'))|Out-Null
        foreach($f in Get-ChildItem -LiteralPath $rules -File){Copy-Item -LiteralPath $f.FullName -Destination (Join-Path $stage "rules/$($f.Name)")}
        if(-not (& $Validator $stage)){$res.Code=1;$res.Status='INVALID';$res.Issues=@('El plugin no pasó la validación (agy plugin validate --strict); no se cambió nada.');return [pscustomobject]$res}
        if(-not (Ap-Same (Ap-Files $stage) (Ap-Files $target))){
            if([IO.Directory]::Exists($target)){Remove-Item -LiteralPath $target -Recurse -Force}
            [IO.Directory]::CreateDirectory((Split-Path $target))|Out-Null
            Move-Item -LiteralPath $stage -Destination $target
            $res.Status='INSTALLED'
        }
        # Only now, with a valid plugin in place, the loose entries go.
        $c=Read-AgentOpsJsonFile $hooksPath;$removed=$false
        foreach($k in $script:loose){if($c.Contains($k)){$c.Remove($k);$removed=$true}}
        if($removed){Write-AgentOpsJsonFile $hooksPath $c;if($res.Status -eq 'UP_TO_DATE'){$res.Status='INSTALLED'}}
    }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($_.Exception.Message)}
    finally{if([IO.Directory]::Exists($work)){Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue}}
    return [pscustomobject]$res
}
Export-ModuleMember -Function Install-AgentOpsAntigravityPlugin
