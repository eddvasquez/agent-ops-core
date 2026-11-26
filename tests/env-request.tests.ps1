# Safe .env credential request flow: prepares .env.example and empty keys in .env (only when .gitignore
# ignores .env), and checks which keys are populated without ever reading or returning secret values.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/EnvRequest.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-envreq-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
function Repo([bool]$ignoreEnv=$true){
    $r=Join-Path $script:base ('p-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    [IO.Directory]::CreateDirectory($r)|Out-Null
    & git init -q -b main $r;& git -C $r config user.name T;& git -C $r config user.email t@localhost
    if($ignoreEnv){[IO.File]::WriteAllText((Join-Path $r '.gitignore'),".env`n",$utf8);& git -C $r add .gitignore;& git -C $r commit -q --no-verify -m base}
    else{[IO.File]::WriteAllText((Join-Path $r 'README.md'),'x',$utf8);& git -C $r add README.md;& git -C $r commit -q --no-verify -m base}
    return $r
}

Test 'refuses to create .env in a Git repo when .env is not ignored' {
    $r=Repo -ignoreEnv $false
    $res=New-AgentOpsEnvRequest -ProjectPath $r -Keys @('API_TOKEN')
    Assert ($res.Code -eq 1 -and $res.Status -eq 'UNSAFE_GITIGNORE' -and -not [IO.File]::Exists((Join-Path $r '.env'))) ($res|ConvertTo-Json -Depth 4)
}

Test 'prepares .env and .env.example and keeps existing secret values untouched' {
    $r=Repo -ignoreEnv $true
    [IO.File]::WriteAllText((Join-Path $r '.env'),"EXISTING_KEY=super-secret-value-123`n",$utf8)
    $res=New-AgentOpsEnvRequest -ProjectPath $r -Keys @('EXISTING_KEY','NEW_KEY')
    Assert ($res.Code -eq 0 -and $res.Status -eq 'READY') ($res|ConvertTo-Json -Depth 4)
    $envRaw=[IO.File]::ReadAllText((Join-Path $r '.env'))
    Assert ($envRaw -match 'EXISTING_KEY=super-secret-value-123' -and $envRaw -match '(?m)^NEW_KEY=\s*$') $envRaw
    $exRaw=[IO.File]::ReadAllText((Join-Path $r '.env.example'))
    Assert ($exRaw -match '(?m)^EXISTING_KEY=\s*$' -and $exRaw -match '(?m)^NEW_KEY=\s*$') $exRaw
    Assert (($res|ConvertTo-Json -Depth 5) -notmatch 'super-secret-value-123') 'Secret value leaked in output'
}

Test 'checks populated keys without ever returning secret values' {
    $r=Repo -ignoreEnv $true
    [IO.File]::WriteAllText((Join-Path $r '.env'),"KEY_A=valA_secret`nKEY_B=`n",$utf8)
    $c1=Test-AgentOpsEnvKeys -ProjectPath $r -Keys @('KEY_A','KEY_B')
    Assert ($c1.Code -eq 1 -and $c1.Status -eq 'MISSING_VALUES' -and (@($c1.Present) -contains 'KEY_A') -and (@($c1.Missing) -contains 'KEY_B')) ($c1|ConvertTo-Json -Depth 4)
    Assert (($c1|ConvertTo-Json -Depth 5) -notmatch 'valA_secret') 'Secret value leaked in Check output'
    [IO.File]::WriteAllText((Join-Path $r '.env'),"KEY_A=valA_secret`nKEY_B=valB_secret`n",$utf8)
    $c2=Test-AgentOpsEnvKeys -ProjectPath $r -Keys @('KEY_A','KEY_B')
    Assert ($c2.Code -eq 0 -and $c2.Status -eq 'READY' -and -not @($c2.Missing).Count) ($c2|ConvertTo-Json -Depth 4)
    Assert (($c2|ConvertTo-Json -Depth 5) -notmatch 'valA_secret|valB_secret') 'Secret value leaked when READY'
}

Test 'CLI script works for Prepare and Check without echoing secrets' {
    $r=Repo -ignoreEnv $true
    $engine=(Get-Process -Id $PID).Path
    $p=& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/request-env.ps1') -Action Prepare -ProjectPath $r -Keys @('MY_KEY')|Out-String
    Assert ($LASTEXITCODE -eq 0 -and ($p|ConvertFrom-Json).Status -eq 'READY') $p
    [IO.File]::WriteAllText((Join-Path $r '.env'),"MY_KEY=top-secret-999`n",$utf8)
    $c=& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/request-env.ps1') -Action Check -ProjectPath $r -Keys @('MY_KEY')|Out-String
    Assert ($LASTEXITCODE -eq 0 -and ($c|ConvertFrom-Json).Status -eq 'READY' -and $c -notmatch 'top-secret-999') $c
}

Write-Host "Env request: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}