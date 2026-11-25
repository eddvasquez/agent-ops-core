Set-StrictMode -Version 2
# Antigravity permissions. Antigravity keeps its permission lists in ~/.gemini/config/config.json
# (userSettings.globalPermissionGrants: allow, ask, deny; rules look like action(target)). The framework adds "ask"
# rules for the credential folders that exist, so Antigravity asks before reading them. A rule the user already
# decided about (in any list) is left alone, nothing else in the file changes, a copy is kept before every change and
# nothing is created when Antigravity has no configuration. Antigravity reads the file when it starts.
$script:candidates=@('.ssh','AppData/Roaming/gcloud','.aws','.azure','.kube','.docker','.git-credentials','.netrc','.npmrc')

# Antigravity drops the drive letter and uses forward slashes on Windows.
function Convert-AgentOpsAntigravityPath([string]$Path){
    $full=[IO.Path]::GetFullPath($Path) -replace '^[A-Za-z]:',''
    return ($full -replace '\\','/').TrimEnd('/')
}

function Install-AgentOpsAntigravityPermissions {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ConfigPath,[Parameter(Mandatory=$true)][string]$HomeDir,
          [Parameter(Mandatory=$true)][string]$BackupDir)
    $res=[ordered]@{Code=0;Status='UP_TO_DATE';Added=@();Backup='';Issues=@()}
    if(-not [IO.File]::Exists($ConfigPath)){$res.Status='NO_CONFIG';return [pscustomobject]$res}
    try{$cfg=[IO.File]::ReadAllText($ConfigPath)|ConvertFrom-Json}
    catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@('Unreadable Antigravity configuration: '+$_.Exception.Message);return [pscustomobject]$res}
    if($null -eq $cfg){$res.Code=1;$res.Status='FAILED';$res.Issues=@('Empty Antigravity configuration');return [pscustomobject]$res}
    $existing=@()
    if($cfg.PSObject.Properties['userSettings'] -and $cfg.userSettings.PSObject.Properties['globalPermissionGrants']){
        $grants=$cfg.userSettings.globalPermissionGrants
        foreach($list in 'allow','ask','deny'){if($grants.PSObject.Properties[$list]){$existing+=@($grants.$list)}}
    }
    $new=@()
    foreach($c in $script:candidates){
        $p=Join-Path $HomeDir $c
        if([IO.Directory]::Exists($p) -or [IO.File]::Exists($p)){
            $rule='read_file('+(Convert-AgentOpsAntigravityPath $p)+')'
            if($existing -notcontains $rule){$new+=$rule}
        }
    }
    if(-not $new.Count){return [pscustomobject]$res}
    try{
        [IO.Directory]::CreateDirectory($BackupDir)|Out-Null
        $backup=Join-Path $BackupDir ('antigravity-config-'+[datetime]::Now.ToString('yyyyMMddTHHmmssfff')+'.json')
        [IO.File]::Copy($ConfigPath,$backup)
        if(-not $cfg.PSObject.Properties['userSettings']){$cfg|Add-Member -NotePropertyName userSettings -NotePropertyValue ([pscustomobject]@{})}
        if(-not $cfg.userSettings.PSObject.Properties['globalPermissionGrants']){$cfg.userSettings|Add-Member -NotePropertyName globalPermissionGrants -NotePropertyValue ([pscustomobject]@{})}
        $g=$cfg.userSettings.globalPermissionGrants
        if(-not $g.PSObject.Properties['ask']){$g|Add-Member -NotePropertyName ask -NotePropertyValue @()}
        $g.ask=@($g.ask)+@($new)
        $tmp=$ConfigPath+'.aoc-tmp'
        [IO.File]::WriteAllText($tmp,($cfg|ConvertTo-Json -Depth 50),(New-Object Text.UTF8Encoding($false)))
        Move-Item -LiteralPath $tmp -Destination $ConfigPath -Force
        $res.Status='UPDATED';$res.Added=$new;$res.Backup=$backup
    }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($_.Exception.Message)}
    return [pscustomobject]$res
}
Export-ModuleMember -Function Convert-AgentOpsAntigravityPath,Install-AgentOpsAntigravityPermissions
