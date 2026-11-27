[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/SessionDistill.psm1') -Force
Import-Module (Join-Path $source 'scripts/LearningProposals.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-distill-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_";Write-Host $_.ScriptStackTrace}}
function NewDir([string]$n){$d=Join-Path $script:base ($n+'-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($d)|Out-Null;return $d}
function NewHub{
    $h=NewDir 'hub'
    $s=Join-Path $h 'google-ads-media-buyer';[IO.Directory]::CreateDirectory($s)|Out-Null
    [IO.File]::WriteAllText((Join-Path $s 'SKILL.md'),"---`nname: google-ads-media-buyer`nversion: 1.0.0`ndescription: Auditoria de campanas Google Ads y listas de palabras clave negativas.`n---`n# gas`n",$utf8)
    return $h
}
function NewProj{
    $p=NewDir 'proj'
    [IO.File]::WriteAllText((Join-Path $p 'AGENTS.md'),"### Protocolo 1 (MODO ENTRADA)`n",$utf8)
    [IO.Directory]::CreateDirectory((Join-Path $p '.context'))|Out-Null
    return $p
}

Test 'session without corrections or test failures returns QUIET and writes nothing to hub' {
    $p=NewProj;$h=NewHub;$st=NewDir 'state'
    $r=Invoke-SessionDistill -ProjectPath $p -HubPath $h -StateDir $st -ClaudeProjectsRoot (NewDir 'cl') -CodexSessionsRoot (NewDir 'cx') -AntigravityBrainRoot (NewDir 'ag') -CaptureToInbox
    Assert ($r.Code -eq 0 -and $r.Status -eq 'QUIET' -and $r.Findings.Count -eq 0 -and -not (Test-Path (Join-Path $h 'proposals/inbox'))) ($r|ConvertTo-Json -Depth 5)
}

Test 'secret in session directive is blocked as SECRET_BLOCKED and never captured' {
    $p=NewProj;$h=NewHub;$st=NewDir 'state'
    $ag=NewDir 'ag';$conv=Join-Path $ag 'c1/.system_generated/logs';[IO.Directory]::CreateDirectory($conv)|Out-Null
    $tok='ghp_'+'1234567890abcdefghij123456'
    $line=(@{source='USER_EXPLICIT';type='USER_INPUT';created_at=[datetime]::UtcNow.ToString('o');content="<USER_REQUEST>Nunca uses el token $tok en $p </USER_REQUEST>"}|ConvertTo-Json -Compress)
    [IO.File]::WriteAllText((Join-Path $conv 'transcript.jsonl'),"$line`n",$utf8)
    $r=Invoke-SessionDistill -ProjectPath $p -HubPath $h -StateDir $st -ClaudeProjectsRoot (NewDir 'cl') -CodexSessionsRoot (NewDir 'cx') -AntigravityBrainRoot $ag -CaptureToInbox
    Assert ($r.Code -eq 0 -and $r.Status -eq 'SIGNAL_FOUND' -and $r.Blocked.Count -ge 1 -and $r.Captured.Count -eq 0 -and -not (Test-Path (Join-Path $h 'proposals/inbox'))) ($r|ConvertTo-Json -Depth 5)
}

Test 'reusable skill-aligned correction is sanitized and classified as destination 3 without proposing new skill' {
    $p=NewProj;$h=NewHub;$st=NewDir 'state'
    [IO.File]::WriteAllText((Join-Path $p '.context/private_terms.txt'),"AcmeClient`n",$utf8)
    $ag=NewDir 'ag';$conv=Join-Path $ag 'c2/.system_generated/logs';[IO.Directory]::CreateDirectory($conv)|Out-Null
    $line=(@{source='USER_EXPLICIT';type='USER_INPUT';created_at=[datetime]::UtcNow.ToString('o');content="<USER_REQUEST>Siempre revisa las palabras clave negativas de campanas Google Ads en AcmeClient antes de subir presupuesto para C:\Users\Alice\docs y juan@acme.com.</USER_REQUEST> $p"}|ConvertTo-Json -Compress)
    [IO.File]::WriteAllText((Join-Path $conv 'transcript.jsonl'),"$line`n",$utf8)
    $r=Invoke-SessionDistill -ProjectPath $p -HubPath $h -StateDir $st -ClaudeProjectsRoot (NewDir 'cl') -CodexSessionsRoot (NewDir 'cx') -AntigravityBrainRoot $ag -CaptureToInbox
    Assert ($r.Code -eq 0 -and $r.Status -eq 'SIGNAL_FOUND' -and $r.LowRiskReview.Count -ge 1 -and $r.Captured.Count -ge 1) ($r|ConvertTo-Json -Depth 5)
    Assert ((@($r.Findings|Where-Object {$_.Destination -eq 5}).Count) -eq 0) 'Single session must never propose destination 5'
    $txt=[IO.File]::ReadAllText($r.Captured[0].Path,$utf8)
    Assert ($txt -notmatch 'AcmeClient|Alice|juan@acme\.com' -and $txt -match '<CLIENTE>' -and $txt -match '<USER_HOME>' -and $txt -match '<EMAIL>') $txt
}

Test 'test failures in ActivityLog classify as destination 2b code check' {
    $p=NewProj;$h=NewHub;$st=NewDir 'state'
    Import-Module (Join-Path $source 'scripts/ActivityLog.psm1') -Force
    Add-AgentOpsActivity -StateDir $st -Harness claude -Event (@{cwd=$p;tool_name='Bash';tool_input=@{command='pwsh -File tests/a.tests.ps1'};tool_response=@{exitCode=1}}|ConvertTo-Json -Compress)
    Add-AgentOpsActivity -StateDir $st -Harness claude -Event (@{cwd=$p;tool_name='Edit';tool_input=@{file_path=(Join-Path $p 'scripts/a.ps1')}}|ConvertTo-Json -Compress)
    $r=Invoke-SessionDistill -ProjectPath $p -HubPath $h -StateDir $st -ClaudeProjectsRoot (NewDir 'cl') -CodexSessionsRoot (NewDir 'cx') -AntigravityBrainRoot (NewDir 'ag')
    Assert ($r.Code -eq 0 -and $r.Status -eq 'SIGNAL_FOUND' -and (@($r.Findings|Where-Object {$_.Destination -eq '2b'}).Count -ge 1)) ($r|ConvertTo-Json -Depth 5)
}

Test 'session-distill.ps1 CLI wrapper returns JSON contract' {
    $p=NewProj;$h=NewHub;$st=NewDir 'state';$ps=(Get-Process -Id $PID).Path
    $out=& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/session-distill.ps1') -ProjectPath $p -HubPath $h -StateDir $st -ClaudeProjectsRoot (NewDir 'cl') -CodexSessionsRoot (NewDir 'cx') -AntigravityBrainRoot (NewDir 'ag')
    $j=$out -join "`n"|ConvertFrom-Json
    Assert ($LASTEXITCODE -eq 0 -and $j.Code -eq 0 -and $j.Status -eq 'QUIET') ($out -join "`n")
}

Write-Host "Session distill: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}