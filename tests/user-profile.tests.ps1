[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/UserProfile.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-profile-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
function NewState{$d=Join-Path $script:base ([guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($d)|Out-Null;return $d}

Test 'without a profile the status is MISSING and the register defaults to plain language' {
    $s=NewState;$r=Get-AgentOpsUserProfile -StateDir $s
    Assert ($r.Code -eq 0 -and $r.Status -eq 'MISSING' -and $r.Register -eq 'plain' -and $r.AskInterview) ($r|ConvertTo-Json -Depth 4)
}
Test 'a saved profile is returned with its register and the interview is not asked again' {
    $s=NewState
    $w=Set-AgentOpsUserProfile -StateDir $s -Role 'marketing' -TechFamiliarity none -Detail result
    Assert ($w.Code -eq 0 -and $w.Status -eq 'SET') ($w|ConvertTo-Json -Depth 4)
    $r=Get-AgentOpsUserProfile -StateDir $s
    Assert ($r.Status -eq 'SET' -and -not $r.AskInterview -and $r.Register -eq 'plain' -and $r.Profile.Role -eq 'marketing' -and $r.Profile.Detail -eq 'result') ($r|ConvertTo-Json -Depth 4)
}
Test 'familiarity maps to the language register' {
    $s=NewState
    Set-AgentOpsUserProfile -StateDir $s -Role 'ux' -TechFamiliarity some -Detail steps|Out-Null
    Assert ((Get-AgentOpsUserProfile -StateDir $s).Register -eq 'bridged') 'some -> bridged'
    Set-AgentOpsUserProfile -StateDir $s -Role 'desarrollo' -TechFamiliarity fluent -Detail full|Out-Null
    Assert ((Get-AgentOpsUserProfile -StateDir $s).Register -eq 'technical') 'fluent -> technical'
}
Test 'skipping the interview stores plain defaults and is not asked again' {
    $s=NewState;$w=Set-AgentOpsUserProfile -StateDir $s -Skipped
    Assert ($w.Code -eq 0 -and $w.Status -eq 'SKIPPED') ($w|ConvertTo-Json -Depth 4)
    $r=Get-AgentOpsUserProfile -StateDir $s
    Assert ($r.Status -eq 'SKIPPED' -and $r.Register -eq 'plain' -and -not $r.AskInterview) ($r|ConvertTo-Json -Depth 4)
}
Test 'invalid values are rejected and nothing is written' {
    $s=NewState;$w=Set-AgentOpsUserProfile -StateDir $s -Role 'x' -TechFamiliarity expert -Detail result
    Assert ($w.Code -eq 1 -and @($w.Issues).Count -ge 1) ($w|ConvertTo-Json -Depth 4)
    Assert ((Get-AgentOpsUserProfile -StateDir $s).Status -eq 'MISSING') 'Invalid profile was written'
}
Test 'a corrupt profile file is reported, defaults to plain language and asks again' {
    $s=NewState;[IO.File]::WriteAllText((Join-Path $s 'user-profile.json'),'{ not json')
    $r=Get-AgentOpsUserProfile -StateDir $s
    Assert ($r.Code -eq 0 -and $r.Status -eq 'MISSING' -and $r.Register -eq 'plain' -and $r.AskInterview -and @($r.Issues).Count -eq 1) ($r|ConvertTo-Json -Depth 4)
}
Test 'CLI prints JSON and exits with the result code' {
    $s=NewState;$engine=(Get-Process -Id $PID).Path;$cli=Join-Path $source 'scripts/user-profile.ps1'
    $json=& $engine -NoProfile -ExecutionPolicy Bypass -File $cli -Action Set -StateDir $s -Role 'investigacion de mercados' -TechFamiliarity none -Detail steps|Out-String
    Assert ($LASTEXITCODE -eq 0) $json
    $r=(& $engine -NoProfile -ExecutionPolicy Bypass -File $cli -Action Get -StateDir $s|Out-String)|ConvertFrom-Json
    Assert ($LASTEXITCODE -eq 0 -and $r.Status -eq 'SET' -and $r.Profile.Role -eq 'investigacion de mercados') ($r|ConvertTo-Json -Depth 4)
    & $engine -NoProfile -ExecutionPolicy Bypass -File $cli -Action Set -StateDir $s -Role 'x' -TechFamiliarity bad -Detail steps|Out-Null
    Assert ($LASTEXITCODE -eq 1) 'Invalid value accepted by CLI'
}
Remove-Item -LiteralPath $script:base -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "User profile: $script:passed passed, $script:failed failed."
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
