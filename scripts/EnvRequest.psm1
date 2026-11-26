Set-StrictMode -Version 2
# Safe .env credential request flow: prepares .env.example and empty keys in .env (only when .gitignore
# ignores .env), and checks which keys have non-empty values without ever returning secret values.
Import-Module (Join-Path $PSScriptRoot 'NativeProcess.psm1') -Force
$script:utf8=New-Object Text.UTF8Encoding($false)

function Er-ReadKeys([string]$path){
    $map=@{}
    if(-not [IO.File]::Exists($path)){return $map}
    foreach($line in [IO.File]::ReadAllLines($path)){
        $t=$line.Trim()
        if(-not $t -or $t.StartsWith('#')){continue}
        $idx=$t.IndexOf('=');if($idx -lt 1){continue}
        $k=$t.Substring(0,$idx).Trim();$v=$t.Substring($idx+1).Trim()
        $map[$k]=([string]$v).Length -gt 0
    }
    return $map
}

function Er-AppendMissing([string]$path,[string[]]$keys){
    $existing=Er-ReadKeys $path
    $toAdd=@($keys|Where-Object {$_ -and -not $existing.ContainsKey($_)}|Select-Object -Unique)
    if(-not $toAdd.Count -and [IO.File]::Exists($path)){return}
    $prefix=''
    if([IO.File]::Exists($path)){
        $raw=[IO.File]::ReadAllText($path)
        if($raw -and -not $raw.EndsWith("`n")){$prefix="`n"}
    }
    $body=($toAdd|ForEach-Object {"$_="}) -join "`n"
    if($body){$body+="`n"}
    [IO.File]::AppendAllText($path,($prefix+$body),$script:utf8)
}

function New-AgentOpsEnvRequest {
    [CmdletBinding()]
    param([string]$ProjectPath=(Get-Location).Path,[Parameter(Mandatory)][string[]]$Keys)
    $res=[ordered]@{Code=0;Status='READY';EnvPath='';ExamplePath='';MissingKeys=@();Message='';Issues=@()}
    try{
        $root=(Resolve-Path -LiteralPath $ProjectPath).Path
        $envPath=Join-Path $root '.env';$exPath=Join-Path $root '.env.example'
        $res.EnvPath=$envPath;$res.ExamplePath=$exPath
        $top=Invoke-Git $root @('rev-parse','--show-toplevel') -AllowFailure
        if($top.ExitCode -eq 0 -and [IO.Path]::GetFullPath(($top.Output.Trim() -replace '/','\')).TrimEnd('\') -eq $root.TrimEnd('\')){
            $ig=Invoke-Git $root @('check-ignore','-q','--','.env') -AllowFailure
            if($ig.ExitCode -ne 0){
                $res.Code=1;$res.Status='UNSAFE_GITIGNORE'
                $res.Issues=@('.env no esta ignorado por .gitignore; anade .env a .gitignore antes de crearlo.')
                return [pscustomobject]$res
            }
        }
        Er-AppendMissing $exPath $Keys
        Er-AppendMissing $envPath $Keys
        $check=Test-AgentOpsEnvKeys -ProjectPath $root -Keys $Keys
        $res.MissingKeys=@($check.Missing)
        $res.Message="Abre $envPath, rellena las claves vacias y guarda el archivo sin pegar valores en el chat."
    }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($_.Exception.Message)}
    return [pscustomobject]$res
}

function Test-AgentOpsEnvKeys {
    [CmdletBinding()]
    param([string]$ProjectPath=(Get-Location).Path,[Parameter(Mandatory)][string[]]$Keys)
    $res=[ordered]@{Code=0;Status='READY';Present=@();Missing=@();Issues=@()}
    try{
        $root=(Resolve-Path -LiteralPath $ProjectPath).Path
        $map=Er-ReadKeys (Join-Path $root '.env')
        $present=@();$missing=@()
        foreach($k in @($Keys|Where-Object {$_}|Select-Object -Unique)){
            if($map.ContainsKey($k) -and $map[$k]){$present+=$k}else{$missing+=$k}
        }
        $res.Present=@($present);$res.Missing=@($missing)
        if($missing.Count){$res.Code=1;$res.Status='MISSING_VALUES'}
    }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($_.Exception.Message)}
    return [pscustomobject]$res
}
Export-ModuleMember -Function New-AgentOpsEnvRequest,Test-AgentOpsEnvKeys