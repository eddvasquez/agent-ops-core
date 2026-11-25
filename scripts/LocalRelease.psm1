Set-StrictMode -Version 2
# Local release proof (R-014). The committed HEAD of the framework repository is checked out in a temporary copy
# and every suite runs there with the candidate's own run-tests.ps1, in Windows PowerShell and in PowerShell 7,
# plus the public package and versioning checks. Only an all-green result is written as the proof that
# Install-AgentOpsLocalRelease requires. The copy is always removed (only aoc-localrelease-* under %TEMP%).
Import-Module (Join-Path $PSScriptRoot 'NativeProcess.psm1')

function Lr-Remove([string]$root,[string]$dir){
    $null=Invoke-Git -RepositoryPath $root -Arguments @('worktree','remove','--force',$dir) -AllowFailure
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    if([IO.Directory]::Exists($dir) -and (Split-Path -Parent $dir) -eq $temp -and (Split-Path -Leaf $dir) -like 'aoc-localrelease-*'){
        Get-ChildItem -LiteralPath $dir -Recurse -Force -File -ErrorAction SilentlyContinue|ForEach-Object {if($_.IsReadOnly){$_.IsReadOnly=$false}}
        Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $null=Invoke-Git -RepositoryPath $root -Arguments @('worktree','prune') -AllowFailure
}
# Default runner: every suite of the copy with its own runner, then (once) the release and versioning checks.
function Lr-DefaultRunner([string]$dir,[string]$edition){
    $exe=$(if($edition -eq 'Core'){'pwsh'}else{Join-Path $env:WINDIR 'System32/WindowsPowerShell/v1.0/powershell.exe'})
    $json=& $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'scripts/run-tests.ps1') -ProjectPath $dir 2>$null|Out-String
    try{$r=$json|ConvertFrom-Json}catch{return [pscustomobject]@{Green=$false;Suites=@();Failures=@("run-tests ($edition) did not answer JSON")}}
    $failures=@(@($r.Results)|Where-Object {$_.Exit -ne 0}|ForEach-Object {"$($_.Suite) ($edition): "+$(if($_.PSObject.Properties['Failures'] -and @($_.Failures).Count){@($_.Failures) -join ' | '}else{$_.Summary})})
    $failures+=@($r.Issues|Where-Object {$_})
    if($edition -eq 'Desktop'){
        $sha=((& git -C $dir rev-parse HEAD)|Select-Object -First 1).Trim()
        & $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'scripts/check-release.ps1') -Commit $sha -RepositoryPath $dir *>$null
        if($LASTEXITCODE -ne 0){$failures+="check-release: código $LASTEXITCODE"}
        & $exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $dir 'scripts/check-versioning.ps1') -RepositoryPath $dir *>$null
        if($LASTEXITCODE -ne 0){$failures+="check-versioning: código $LASTEXITCODE"}
    }
    return [pscustomobject]@{Green=($r.Code -eq 0 -and -not $failures.Count);Suites=@(@($r.Results)|ForEach-Object {"$($_.Suite) ($edition): $($_.Summary)"});Failures=$failures}
}

function New-AgentOpsLocalProof {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$SourceRepo,
          [string]$StateDir=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'}),
          [scriptblock]$Runner)
    $res=[ordered]@{Code=1;Status='RED';Sha=$null;Proof=$null;Suites=@();Failures=@();Issues=@()}
    $root=(Resolve-Path -LiteralPath $SourceRepo).Path
    if(-not $Runner){$Runner=${function:Lr-DefaultRunner}}
    $dir=Join-Path ([IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')) ('aoc-localrelease-'+[guid]::NewGuid().ToString('N').Substring(0,12))
    $made=$false
    try{
        # Only the commit is tested (in a copy): uncommitted changes are left out, so work can go on meanwhile.
        if(((Invoke-Git -RepositoryPath $root -Arguments @('status','--porcelain','--untracked-files=all')).Output).Trim()){$res.Issues=@('Hay cambios sin guardar: no se incluyen; se prueba el último commit.')}
        $sha=((Invoke-Git -RepositoryPath $root -Arguments @('rev-parse','HEAD')).Output).Trim().ToLowerInvariant();$res.Sha=$sha
        $null=Invoke-Git -RepositoryPath $root -Arguments @('worktree','add','--detach','--quiet',$dir,$sha);$made=$true
        foreach($edition in 'Desktop','Core'){
            $r=& $Runner $dir $edition
            $res.Suites+=@($r.Suites);$res.Failures+=@($r.Failures)
            if(-not $r.Green){return [pscustomobject]$res}
        }
        $proofDir=Join-Path $StateDir 'local-proofs';[IO.Directory]::CreateDirectory($proofDir)|Out-Null
        $path=Join-Path $proofDir "$sha.json"
        [IO.File]::WriteAllText($path,([ordered]@{SchemaVersion=1;Sha=$sha;Green=$true;Editions=@('Desktop','Core');Suites=@($res.Suites);At=[datetime]::UtcNow.ToString('o')}|ConvertTo-Json -Depth 4),(New-Object Text.UTF8Encoding($false)))
        $res.Code=0;$res.Status='PROVEN';$res.Proof=$path
    }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($_.Exception.Message)}
    finally{if($made){Lr-Remove $root $dir}}
    return [pscustomobject]$res
}
Export-ModuleMember -Function New-AgentOpsLocalProof
