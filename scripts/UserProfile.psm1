Set-StrictMode -Version 2
# Per-person language profile (Protocol 9). It lives in the machine's private state, never in a project,
# so one person gets the same language in every project and harness. Source is ASCII-only.
$script:familiarity=@{none='plain';some='bridged';fluent='technical'}
$script:details=@('result','steps','full')

function Up-DefaultStateDir{
    if($env:LOCALAPPDATA){return (Join-Path $env:LOCALAPPDATA 'AgentOps')}
    return (Join-Path $HOME '.agent-ops-state')
}
function Up-ProfilePath([string]$StateDir){Join-Path $StateDir 'user-profile.json'}

function Get-AgentOpsUserProfile {
    [CmdletBinding()]
    param([string]$StateDir=(Up-DefaultStateDir))
    $issues=@();$status='MISSING';$profile=$null
    $path=Up-ProfilePath $StateDir
    if(Test-Path -LiteralPath $path -PathType Leaf){
        try{
            $p=[IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)|ConvertFrom-Json
            if($p.Status -notin @('SET','SKIPPED')){throw 'unknown status'}
            $status=[string]$p.Status
            $profile=[pscustomobject]@{Role=[string]$p.Role;TechFamiliarity=[string]$p.TechFamiliarity;Detail=[string]$p.Detail;UpdatedAt=[string]$p.UpdatedAt}
        }catch{$issues+="Profile file is unreadable and will be asked again: $path";$status='MISSING';$profile=$null}
    }
    $register='plain'
    if($status -eq 'SET' -and $script:familiarity.ContainsKey($profile.TechFamiliarity)){$register=$script:familiarity[$profile.TechFamiliarity]}
    [pscustomobject]@{Code=0;Status=$status;Register=$register;AskInterview=($status -eq 'MISSING');Profile=$profile;Path=$path;Issues=@($issues)}
}

function Set-AgentOpsUserProfile {
    [CmdletBinding()]
    param([string]$StateDir=(Up-DefaultStateDir),[string]$Role='',[string]$TechFamiliarity='',[string]$Detail='',[switch]$Skipped)
    $issues=@()
    if($Skipped){$data=[ordered]@{Status='SKIPPED';Role='';TechFamiliarity='';Detail='result'}}
    else{
        $Role=$Role.Trim()
        if(-not $Role -or $Role.Length -gt 80){$issues+='Role is required (1-80 characters).'}
        if(-not $script:familiarity.ContainsKey($TechFamiliarity)){$issues+="TechFamiliarity must be one of: $(@($script:familiarity.Keys|Sort-Object) -join ', ')."}
        if($Detail -notin $script:details){$issues+="Detail must be one of: $($script:details -join ', ')."}
        $data=[ordered]@{Status='SET';Role=$Role;TechFamiliarity=$TechFamiliarity;Detail=$Detail}
    }
    $path=Up-ProfilePath $StateDir
    if($issues.Count){return [pscustomobject]@{Code=1;Status='INVALID';Path=$path;Issues=@($issues)}}
    $data.UpdatedAt=(Get-Date).ToUniversalTime().ToString('o')
    try{
        [IO.Directory]::CreateDirectory($StateDir)|Out-Null
        $tmp=$path+'.tmp'
        [IO.File]::WriteAllText($tmp,([pscustomobject]$data|ConvertTo-Json),(New-Object Text.UTF8Encoding $false))
        if(Test-Path -LiteralPath $path){Remove-Item -LiteralPath $path -Force}
        Move-Item -LiteralPath $tmp -Destination $path
    }catch{return [pscustomobject]@{Code=1;Status='FAILED';Path=$path;Issues=@($_.Exception.Message)}}
    [pscustomobject]@{Code=0;Status=$data.Status;Path=$path;Issues=@()}
}
Export-ModuleMember -Function Get-AgentOpsUserProfile,Set-AgentOpsUserProfile
