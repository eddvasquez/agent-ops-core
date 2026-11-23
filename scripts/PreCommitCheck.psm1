Set-StrictMode -Version 2
# Automatic review before every commit, so the checks no longer depend on the agent remembering them.
# Test-AgentOpsPreCommit judges only what is staged: versioning (Protocol 7) and credentials in added lines.
# The Git hook is two files under the repository's hooks folder: a POSIX shim and a PowerShell launcher
# that resolves the active Agent Ops release at run time, so updates never require reinstalling it.
Import-Module (Join-Path $PSScriptRoot 'NativeProcess.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'Versioning.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'SecretScan.psm1') -Force
$script:marker='agent-ops:pre-commit'
$script:hookVersion='1'
$script:shim="#!/bin/sh`n# $($script:marker) v$($script:hookVersion)`n# Managed by Agent Ops: automatic review before each commit.`nif command -v powershell.exe >/dev/null 2>&1; then ps=powershell.exe; else ps=pwsh; fi`nexec `"`$ps`" -NoProfile -ExecutionPolicy Bypass -File `"`$(dirname `"`$0`")/agent-ops-pre-commit.ps1`"`n"
$script:launcher=@'
# agent-ops:pre-commit v1
# Managed by Agent Ops. Finds the active release and runs its pre-commit review on the staged changes.
$stateDir=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'})
$frame=$null
try{
    $s=[IO.File]::ReadAllText((Join-Path $stateDir 'update-state.json'))|ConvertFrom-Json
    if($s.Active -and $s.Active.Path){$frame=[string]$s.Active.Path}
    elseif($s.Mode -eq 'LOCAL_DEV' -and $s.Config -and $s.Config.InstallRoot){$frame=[string]$s.Config.InstallRoot}
}catch{}
$check=$(if($frame){Join-Path $frame 'scripts/pre-commit-check.ps1'}else{$null})
if(-not $check -or -not (Test-Path -LiteralPath $check -PathType Leaf)){
    [Console]::Error.WriteLine('Agent Ops: no se encontró la instalación en este equipo; la revisión automática se omitió en este guardado.')
    exit 0
}
& $check -RepositoryPath (Get-Location).Path
exit $LASTEXITCODE
'@

function Pc-Issue([string]$check,[string]$file,[string]$message,[string]$fix){[pscustomobject]@{Check=$check;File=$file;Message=$message;Fix=$fix}}
function Pc-VersioningFix([string]$message){
    if($message -match '(?:require an entry in|without an entry in) ([^\s]+?)\.?$'){return "Añade una línea en la sección '## [Unreleased]' de $($Matches[1]) que describa el cambio, prepárala junto al resto (git add) y vuelve a guardar."}
    return 'Corrige lo que indica el mensaje y vuelve a guardar. Para ver el detalle, ejecuta check-versioning.ps1 del marco.'
}

function Test-AgentOpsPreCommit {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryPath)
    $issues=@()
    try{
        $root=(Resolve-Path -LiteralPath $RepositoryPath).Path
        $v=Test-AgentOpsVersioning -RepositoryPath $root -Staged
        foreach($i in @($v.Issues)){$issues+=Pc-Issue 'versioning' $null $i (Pc-VersioningFix $i)}
        # Credentials: only lines being added now, so a historical leak does not block unrelated work.
        $head=Invoke-Git $root @('rev-parse','--verify','-q','HEAD') -AllowFailure
        $against=$(if($head.ExitCode -eq 0){'HEAD'}else{'4b825dc642cb6eb9a060e54bf8d69288fbee4904'})
        $diff=(Invoke-Git $root @('-c','core.quotePath=false','diff','--cached','--no-color','--no-ext-diff','-U0','--diff-filter=ACMR',$against)).Output
        $file=$null;$flagged=@{}
        foreach($line in ($diff -split "\r?\n")){
            if($line.StartsWith('+++ ')){$file=$(if($line -eq '+++ /dev/null'){$null}else{$line.Substring(4) -replace '^b/',''});continue}
            if($file -and $line.StartsWith('+') -and -not $flagged.ContainsKey($file) -and (Test-AgentOpsSecret $line.Substring(1))){$flagged[$file]=$true}
        }
        foreach($f in ($flagged.Keys|Sort-Object)){
            $issues+=Pc-Issue 'secrets' $f "Posible contraseña o clave en una línea nueva de $f." 'Quita la clave del archivo y guárdala fuera del proyecto (por ejemplo, en una variable de entorno). Si ya se compartió, cámbiala o revócala en el servicio.'
        }
    }catch{$issues+=Pc-Issue 'error' $null $_.Exception.Message 'Revisa que la carpeta sea un repositorio Git válido y vuelve a intentarlo.'}
    $blocked=@($issues).Count -gt 0
    return [pscustomobject]@{Code=$(if($blocked){1}else{0});Status=$(if($blocked){'BLOCKED'}else{'PASSED'});Issues=@($issues)}
}

function Get-AgentOpsGitHookPlan {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectPath)
    $plan=[ordered]@{Status='NOT_GIT';HooksDir=$null;Files=@();Issues=@()}
    $root=(Resolve-Path -LiteralPath $ProjectPath).Path
    $top=Invoke-Git $root @('rev-parse','--show-toplevel') -AllowFailure
    if($top.ExitCode -ne 0 -or [IO.Path]::GetFullPath(($top.Output.Trim() -replace '/','\')).TrimEnd('\') -ne $root.TrimEnd('\')){return [pscustomobject]$plan}
    $custom=Invoke-Git $root @('config','--get','core.hooksPath') -AllowFailure
    if($custom.ExitCode -eq 0 -and $custom.Output.Trim()){
        $plan.Status='HOOK_REVIEW_REQUIRED';$plan.Issues=@("El proyecto usa su propia carpeta de hooks (core.hooksPath = $($custom.Output.Trim())); hay que integrar la revisión a mano.")
        return [pscustomobject]$plan
    }
    $rel=(Invoke-Git $root @('rev-parse','--git-path','hooks')).Output.Trim()
    $dir=$(if([IO.Path]::IsPathRooted($rel)){[IO.Path]::GetFullPath($rel)}else{[IO.Path]::GetFullPath((Join-Path $root $rel))})
    $plan.HooksDir=$dir
    $wanted=@(
        @{Name='pre-commit';Text=$script:shim;Bom=$false},
        @{Name='agent-ops-pre-commit.ps1';Text=($script:launcher -replace "`r",'');Bom=$true}
    )
    $files=@()
    foreach($w in $wanted){
        $path=Join-Path $dir $w.Name
        $key=$(if($path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){$path.Substring($root.Length+1) -replace '\\','/'}else{$null})
        if([IO.File]::Exists($path)){
            $current=[IO.File]::ReadAllText($path)
            if(($current -replace "`r",'').TrimStart([char]0xFEFF) -eq $w.Text){continue}
            if($current -notmatch [regex]::Escape($script:marker)){
                $plan.Status='HOOK_REVIEW_REQUIRED';$plan.Issues=@("Ya existe un hook $($w.Name) de otra herramienta; no se sobrescribe. Hay que integrar la revisión a mano.")
                $plan.Files=@();return [pscustomobject]$plan
            }
        }
        $files+=[pscustomobject]@{Key=$key;Path=$path;Text=$w.Text;Bom=$w.Bom}
    }
    $plan.Files=@($files);$plan.Status=$(if($files.Count){'READY'}else{'UP_TO_DATE'})
    return [pscustomobject]$plan
}

function Get-AgentOpsGitHookBytes($file){
    $enc=New-Object Text.UTF8Encoding($file.Bom)
    return [byte[]]($enc.GetPreamble()+$enc.GetBytes($file.Text))
}

function Install-AgentOpsGitHook {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([Parameter(Mandatory)][string]$ProjectPath)
    $plan=Get-AgentOpsGitHookPlan -ProjectPath $ProjectPath
    $res=[ordered]@{Code=0;Status=$plan.Status;HooksDir=$plan.HooksDir;Files=@();Issues=@($plan.Issues)}
    if($plan.Status -eq 'HOOK_REVIEW_REQUIRED'){$res.Code=2}
    if($plan.Status -ne 'READY'){return [pscustomobject]$res}
    if(-not $PSCmdlet.ShouldProcess($plan.HooksDir,'Install the Agent Ops pre-commit review')){return [pscustomobject]$res}
    [IO.Directory]::CreateDirectory($plan.HooksDir)|Out-Null
    foreach($f in $plan.Files){[IO.File]::WriteAllBytes($f.Path,(Get-AgentOpsGitHookBytes $f));$res.Files+=@($f.Path)}
    $res.Status='INSTALLED'
    return [pscustomobject]$res
}
Export-ModuleMember -Function Test-AgentOpsPreCommit,Get-AgentOpsGitHookPlan,Get-AgentOpsGitHookBytes,Install-AgentOpsGitHook
