# Acceptance review (R-016, R-017): before work, the user's literal request, criteria and what must not change are
# fixed in a contract; before delivery a reviewer in a clean context (with the project's rules and sources, never
# empty) judges each item with a citation. Invariants with a pattern are checked by script. At most three rounds.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/Acceptance.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-acceptance-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
function Put($r,$k,$t){$p=Join-Path $r $k;[IO.Directory]::CreateDirectory((Split-Path -Parent $p))|Out-Null;[IO.File]::WriteAllText($p,$t,$utf8);return $p}
function Project{
    $p=Join-Path $script:base ('p-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($p)|Out-Null
    Put $p '.context/reglas_proyecto.md' "# Reglas`n`n### R-001 [tono] [ámbito: todas] [estado: activa]`n- Regla: No afirmar «inversión segura».`n`n### R-002 [otro] [ámbito: todas] [estado: retirada]`n- Regla: Regla retirada.`n"|Out-Null
    Put $p 'docs/oferta.md' 'Oferta: Método AVE, 997 USD, garantía 30 días.'|Out-Null
    return $p
}
$request='Ajusta el copy de la landing sin cambiar la oferta: Método AVE a 997 USD con garantía de 30 días.'
function Contract($p){
    New-AgentOpsAcceptance -ProjectPath $p -Request $request -Criteria @('El titular menciona el Método AVE','Hay una llamada a la acción por encima del pliegue') -Invariants @('Precio 997 USD | 997\s*USD','Garantía de 30 días | garant[ií]a de 30 d[ií]as','Tono comercial directo') -Sources @('docs/oferta.md')
}
function Mark($sheet,[hashtable]$verdicts){
    $t=[IO.File]::ReadAllText($sheet)
    foreach($k in $verdicts.Keys){$t=[regex]::Replace($t,'(?m)^- '+[regex]::Escape($k)+': PENDIENTE.*$','- '+$k+': '+$verdicts[$k])}
    [IO.File]::WriteAllText($sheet,$t,$utf8)
}

Test 'the contract keeps the literal request, the criteria, what must not change and the closed scope' {
    $p=Project;$c=Contract $p
    $t=[IO.File]::ReadAllText($c.Path)
    Assert ($c.Code -eq 0 -and $t.Contains($request)) "Literal request missing:`n$t"
    Assert ($t -match '(?m)^- C1: El titular menciona el Método AVE$' -and $t -match '(?m)^- C2: ') $t
    Assert ($t -match '(?m)^- I1: Precio 997 USD \| 997\\s\*USD$' -and $t -match '(?m)^- I3: Tono comercial directo$') $t
    Assert ($t -match 'No cambiar la oferta ni crear variantes') 'Closed scope missing'
}
Test 'the review sheet carries the project (rules, sources, contract), the judge-only role and every item pending' {
    $p=Project;$c=Contract $p;$d=Put $p 'landing/copy.md' "# Método AVE`nInscríbete hoy por 997 USD con garantía de 30 días. [Quiero entrar]"
    $r=New-AgentOpsAcceptanceReview -ProjectPath $p -Id $c.Id -Deliverable @($d)
    $s=[IO.File]::ReadAllText($r.Sheet)
    Assert ($r.Code -eq 0 -and $r.Round -eq 1 -and $s -match '(?m)^Huella: [0-9a-f]{64}$' -and $s -match '(?m)^Ronda: 1$') $s
    Assert ($s.Contains('R-001') -and $s.Contains('«inversión segura»') -and -not $s.Contains('Regla retirada')) 'Active rules must be in the sheet, literally'
    Assert ($s.Contains('docs/oferta.md') -and $s.Contains('997 USD, garantía 30 días')) 'Project sources must be in the sheet'
    Assert ($s -match 'no reescribas' -and $s -match 'No cambiar la oferta') 'The reviewer must be told to judge, not rewrite'
    foreach($id in 'C1','C2','I1','I2','I3'){Assert ($s -match "(?m)^- ${id}: PENDIENTE") "$id must be pending"}
}
Test 'an invariant missing from the deliverable fails automatically, whatever the reviewer says' {
    $p=Project;$c=Contract $p;$d=Put $p 'landing/copy.md' "# Método AVE`nInscríbete hoy por 497 USD, sin riesgo. [Quiero entrar]"
    $r=New-AgentOpsAcceptanceReview -ProjectPath $p -Id $c.Id -Deliverable @($d)
    $s=[IO.File]::ReadAllText($r.Sheet)
    Assert ($s -match '(?m)^- I1: FALLA - automático' -and $s -match '(?m)^- I2: FALLA - automático') $s
    Mark $r.Sheet @{C1='PASA - "# Método AVE"';C2='PASA - "[Quiero entrar]"';I3='PASA - "Inscríbete hoy"'}
    $v=Test-AgentOpsAcceptance -ProjectPath $p -Id $c.Id
    Assert ($v.Code -ne 0 -and $v.Status -eq 'FAILED' -and (@($v.Failed) -join ',') -eq 'I1,I2') ($v|ConvertTo-Json -Depth 4)
}
Test 'a verdict counts only when complete, cited and about the current deliverable' {
    $p=Project;$c=Contract $p;$d=Put $p 'landing/copy.md' "# Método AVE`nInscríbete hoy por 997 USD con garantía de 30 días. [Quiero entrar]"
    $r=New-AgentOpsAcceptanceReview -ProjectPath $p -Id $c.Id -Deliverable @($d)
    Assert ((Test-AgentOpsAcceptance -ProjectPath $p -Id $c.Id).Status -eq 'PENDING') 'Pending items accepted'
    Mark $r.Sheet @{C1='PASA';C2='PASA - "[Quiero entrar]"';I1='PASA - "997 USD"';I2='PASA - "garantía de 30 días"';I3='PASA - "Inscríbete hoy"'}
    Assert ((Test-AgentOpsAcceptance -ProjectPath $p -Id $c.Id).Status -eq 'INVALID') 'A PASA without citation was accepted'
    Mark $r.Sheet @{}
    $t=[IO.File]::ReadAllText($r.Sheet) -replace '(?m)^- C1: PASA$','- C1: PASA - "# Método AVE"';[IO.File]::WriteAllText($r.Sheet,$t,$utf8)
    $v=Test-AgentOpsAcceptance -ProjectPath $p -Id $c.Id
    Assert ($v.Code -eq 0 -and $v.Status -eq 'ACCEPTED') ($v|ConvertTo-Json -Depth 4)
    Put $p 'landing/copy.md' "# Otra cosa"|Out-Null
    Assert ((Test-AgentOpsAcceptance -ProjectPath $p -Id $c.Id).Status -eq 'STALE') 'A verdict about an older deliverable was accepted'
}
Test 'after three failed rounds the work is delivered saying what is missing; there is no fourth round' {
    $p=Project;$c=Contract $p;$d=Put $p 'landing/copy.md' "# Sin oferta"
    foreach($round in 1,2,3){
        $r=New-AgentOpsAcceptanceReview -ProjectPath $p -Id $c.Id -Deliverable @($d)
        Assert ($r.Round -eq $round) "Expected round $round"
        Mark $r.Sheet @{C1='FALLA - "# Sin oferta"';C2='FALLA - "# Sin oferta"';I3='FALLA - "# Sin oferta"'}
        $v=Test-AgentOpsAcceptance -ProjectPath $p -Id $c.Id
    }
    Assert ($v.Status -eq 'DELIVER_WITH_GAPS' -and @($v.Failed).Count -ge 3) ($v|ConvertTo-Json -Depth 4)
    $r=New-AgentOpsAcceptanceReview -ProjectPath $p -Id $c.Id -Deliverable @($d)
    Assert ($r.Code -ne 0 -and $r.Status -eq 'ROUND_LIMIT') ($r|ConvertTo-Json -Depth 4)
}
Write-Host "Acceptance: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
