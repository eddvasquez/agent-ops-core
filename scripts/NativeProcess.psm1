Set-StrictMode -Version 2
# Single launcher for native programs (git, etc.). Windows PowerShell 5.1 does not escape embedded
# double quotes and never stops on a native failure, so every call here builds a correctly escaped
# argument string (same rules as Up-Arguments in UpdateCoordinator.psm1) and returns the exit code.

function ConvertTo-NativeArgumentString([string[]]$Arguments){
    $quoted=foreach($v in $Arguments){
        if($v -and $v -notmatch '[\s"]'){$v}
        else{'"'+[regex]::Replace([regex]::Replace([string]$v,'(\\*)"','$1$1\"'),'(\\+)$','$1$1')+'"'}
    }
    return ($quoted -join ' ')
}

function Invoke-NativeProcess {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$FilePath,[string[]]$Arguments=@(),[string]$WorkingDirectory='')
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=(Get-Command $FilePath -CommandType Application -ErrorAction Stop|Select-Object -First 1).Source
    $info.Arguments=ConvertTo-NativeArgumentString $Arguments
    if($WorkingDirectory){$info.WorkingDirectory=$WorkingDirectory}
    $info.UseShellExecute=$false;$info.CreateNoWindow=$true
    $info.RedirectStandardOutput=$true;$info.RedirectStandardError=$true
    $info.StandardOutputEncoding=[Text.Encoding]::UTF8;$info.StandardErrorEncoding=[Text.Encoding]::UTF8
    $info.EnvironmentVariables['GIT_TERMINAL_PROMPT']='0'
    $p=New-Object Diagnostics.Process;$p.StartInfo=$info
    try{
        [void]$p.Start()
        $errTask=$p.StandardError.ReadToEndAsync()
        $out=$p.StandardOutput.ReadToEnd();$p.WaitForExit()
        return [pscustomobject]@{ExitCode=$p.ExitCode;Output=$out;Error=$errTask.Result}
    }finally{$p.Dispose()}
}

function Invoke-Git {
    # git with the repository pinned via -C and UTF-8/unquoted paths; throws unless -AllowFailure.
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$RepositoryPath,[Parameter(Mandatory)][string[]]$Arguments,[switch]$AllowFailure)
    $all=@('-C',$RepositoryPath,'-c','core.quotepath=false','-c','i18n.commitEncoding=UTF-8','-c','i18n.logOutputEncoding=UTF-8')+$Arguments
    $r=Invoke-NativeProcess -FilePath 'git' -Arguments $all
    if($r.ExitCode -ne 0 -and -not $AllowFailure){throw ('git '+($Arguments -join ' ')+' failed ('+$r.ExitCode+'): '+$r.Error.Trim())}
    return $r
}
Export-ModuleMember -Function ConvertTo-NativeArgumentString,Invoke-NativeProcess,Invoke-Git
