# Pre-deploy audit (OWASP WSTG-CONF-03, read-only): checks a web/deploy folder for exposed VCS metadata,
# credentials, backups, database dumps, archives and diagnostic files without modifying anything.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/DeployAudit.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-deployaudit-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
function Put($r,$k,$t='x'){$p=Join-Path $r $k;[IO.Directory]::CreateDirectory((Split-Path -Parent $p))|Out-Null;[IO.File]::WriteAllText($p,$t,$utf8);return $p}
function NewDir([string]$n){$d=Join-Path $script:base ($n+'-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($d)|Out-Null;return $d}

Test 'a clean deploy folder returns CLEAN and exit code 0' {
    $d=NewDir 'clean'
    Put $d 'index.html' '<h1>Hola</h1>'|Out-Null
    Put $d 'assets/app.js' 'console.log(1);'|Out-Null
    Put $d '.env.example' 'API_KEY='|Out-Null
    $r=Test-AgentOpsDeploySurface -Path $d
    Assert ($r.Code -eq 0 -and $r.Status -eq 'CLEAN' -and -not @($r.Findings).Count) ($r|ConvertTo-Json -Depth 5)
}

Test 'detects exposed .git, credentials, backups, dumps, archives and diagnostic files' {
    $d=NewDir 'dirty'
    foreach($bad in '.git/HEAD','.env','wp-config.php.bak','wp-config.php~','db_dump.sql','backup.zip','phpinfo.php','debug.log','terraform.tfstate'){
        Put $d $bad 'x'|Out-Null
    }
    $r=Test-AgentOpsDeploySurface -Path $d
    Assert ($r.Code -eq 1 -and $r.Status -eq 'BLOCKED') ($r|ConvertTo-Json -Depth 5)
    $paths=@($r.Findings|ForEach-Object {$_.Path})
    foreach($bad in '.git/HEAD','.env','wp-config.php.bak','wp-config.php~','db_dump.sql','backup.zip','phpinfo.php','debug.log','terraform.tfstate'){
        Assert ($paths -contains $bad) "Missing finding for ${bad}: $($paths -join ', ')"
    }
}

Test 'missing path returns FAILED with non-zero code' {
    $missing=Join-Path $script:base 'does-not-exist'
    $r=Test-AgentOpsDeploySurface -Path $missing
    Assert ($r.Code -eq 1 -and $r.Status -eq 'FAILED') ($r|ConvertTo-Json -Depth 5)
}

Test 'CLI script returns JSON and exit code 1 when blocked, 0 when clean' {
    $clean=NewDir 'cli-clean';Put $clean 'index.html' '<p>ok</p>'|Out-Null
    $dirty=NewDir 'cli-dirty';Put $dirty 'secret.bak' 'x'|Out-Null
    $engine=(Get-Process -Id $PID).Path
    $outClean=& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/check-deploy.ps1') -Path $clean|Out-String
    Assert ($LASTEXITCODE -eq 0 -and ($outClean|ConvertFrom-Json).Status -eq 'CLEAN') $outClean
    $outDirty=& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/check-deploy.ps1') -Path $dirty|Out-String
    Assert ($LASTEXITCODE -eq 1 -and ($outDirty|ConvertFrom-Json).Status -eq 'BLOCKED') $outDirty
}

Write-Host "Deploy audit: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}