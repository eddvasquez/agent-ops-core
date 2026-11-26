Set-StrictMode -Version 2
# Pre-deploy audit (OWASP WSTG-CONF-03, read-only): inspects a web/deploy directory for exposed VCS folders,
# credentials, state files, backups, dumps, archives and diagnostic leftovers before publishing.
Import-Module (Join-Path $PSScriptRoot 'SecretGuard.psm1') -Force

function Da-Classify([string]$rel){
    $norm=$rel -replace '\\','/'
    if($norm -match '(^|/)(\.git|\.svn|\.hg)(/|$)'){return 'vcs-exposed'}
    if($norm -match '(^|/)(\.DS_Store|Thumbs\.db)$'){return 'os-metadata'}
    if(Test-AgentOpsSecretPath $norm){return 'credential-or-state'}
    if($norm -match '\.(bak|old|orig|save|swp|swo)$' -or $norm -match '~$'){return 'backup-or-editor'}
    if($norm -match '\.(sql|dump|sqlite|sqlite3|db)$'){return 'database-dump'}
    if($norm -match '\.(zip|tar|tar\.gz|tgz|rar|7z)$'){return 'archive'}
    if($norm -match '(?i)(^|/)(phpinfo\.php|debug\.log|error_log)$'){return 'diagnostic'}
    return ''
}

function Test-AgentOpsDeploySurface {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)
    $res=[ordered]@{Code=0;Status='CLEAN';Path=$Path;Findings=@();Summary='';Issues=@()}
    try{
        if(-not [IO.Directory]::Exists($Path)){
            $res.Code=1;$res.Status='FAILED';$res.Issues=@("La carpeta a revisar no existe: $Path")
            return [pscustomobject]$res
        }
        $root=(Resolve-Path -LiteralPath $Path).Path
        $res.Path=$root
        $findings=@()
        foreach($f in @(Get-ChildItem -LiteralPath $root -Recurse -Force -File -ErrorAction SilentlyContinue)){
            $rel=$f.FullName.Substring($root.Length).TrimStart('\').Replace('\','/')
            $kind=Da-Classify $rel
            if($kind){
                $findings+=[pscustomobject]@{Kind=$kind;Path=$rel}
            }
        }
        $findings=@($findings|Sort-Object Path)
        $res.Findings=$findings
        if($findings.Count){
            $res.Code=1;$res.Status='BLOCKED'
            $res.Summary="Se encontraron $($findings.Count) archivos de riesgo WSTG-CONF-03 antes de desplegar."
        }else{
            $res.Summary='Carpeta limpia: sin respaldos, credenciales ni restos WSTG-CONF-03.'
        }
    }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($_.Exception.Message)}
    return [pscustomobject]$res
}
Export-ModuleMember -Function Test-AgentOpsDeploySurface