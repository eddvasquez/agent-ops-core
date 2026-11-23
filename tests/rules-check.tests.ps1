[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/RulesCheck.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-rules-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
function Put($name,$text){$p=Join-Path $script:base ([guid]::NewGuid().ToString('N')+'-'+$name);[IO.File]::WriteAllText($p,$text,$utf8);return $p}
$rules=@'
# Reglas del proyecto

## Reglas activas

### R-001 [expresion-vetada] [ámbito: todas] [estado: activa]
- Regla: No usar "inversión segura" ni prometer rentabilidad garantizada.
- Motivo: El cliente no puede garantizar rendimientos.
- Origen: corrección del cliente, 2026-11-19
- Detectar: "inversión segura"; "re:rentabilidad\s+garantizad[oa]"

### R-002 [prohibido-afirmar] [ámbito: landing] [estado: activa]
- Regla: No mencionar la piscina.
- Detectar: "piscina"

### R-003 [dato-obligatorio] [ámbito: anuncios] [estado: activa]
- Regla: Todo anuncio incluye "Desde USD 120.000".
- Exigir: "Desde USD 120.000"

### R-004 [expresion-vetada] [ámbito: todas] [estado: retirada]
- Regla: Antes se vetaba "exclusivo"; el cliente lo volvió a aprobar.
- Detectar: "exclusivo"

### R-005 [tono] [ámbito: todas] [estado: activa]
- Regla: Tutear siempre al lector.

### R-006 [expresion-vetada] [ámbito: todas] [estado: activa]
- Regla: No usar "seguro" como adjetivo de venta.
- Detectar: "seguro"
'@
$rulesPath=Put 'reglas_proyecto.md' $rules

Test 'vetoed expression is detected regardless of case and accents, with file and line' {
    $d=Put 'ad.md' "Título`nUna INVERSION SEGURA para tu familia.`nDesde USD 120.000"
    $r=Test-AgentOpsRules -RulesPath $rulesPath -Path $d -Scope anuncios
    Assert ($r.Code -eq 1) ($r|ConvertTo-Json -Depth 6)
    $v=@($r.Violations|Where-Object {$_.Rule -eq 'R-001'})
    Assert ($v.Count -eq 1 -and $v[0].Line -eq 2 -and $v[0].File -eq $d) ($r.Violations|ConvertTo-Json -Depth 4)
}
Test 'regex patterns are supported' {
    $d=Put 'ad.md' "Rentabilidad   garantizada desde el primer mes. Desde USD 120.000"
    $r=Test-AgentOpsRules -RulesPath $rulesPath -Path $d -Scope anuncios
    Assert (@($r.Violations|Where-Object {$_.Rule -eq 'R-001'}).Count -eq 1) ($r|ConvertTo-Json -Depth 6)
}
Test 'a clean deliverable passes' {
    $d=Put 'ad.md' "Vive frente al mar. Desde USD 120.000"
    $r=Test-AgentOpsRules -RulesPath $rulesPath -Path $d -Scope anuncios
    Assert ($r.Code -eq 0 -and @($r.Violations).Count -eq 0) ($r|ConvertTo-Json -Depth 6)
}
Test 'retired rules are not applied' {
    $d=Put 'ad.md' "Un proyecto exclusivo. Desde USD 120.000"
    Assert ((Test-AgentOpsRules -RulesPath $rulesPath -Path $d -Scope anuncios).Code -eq 0) 'Retired rule applied'
}
Test 'scope is respected: landing-only rules do not apply to ads and vice versa' {
    $ad=Put 'ad.md' "Con piscina climatizada. Desde USD 120.000"
    Assert ((Test-AgentOpsRules -RulesPath $rulesPath -Path $ad -Scope anuncios).Code -eq 0) 'Landing rule applied to ads'
    $landing=Put 'landing.md' "Con piscina climatizada."
    $r=Test-AgentOpsRules -RulesPath $rulesPath -Path $landing -Scope landing
    Assert (@($r.Violations|Where-Object {$_.Rule -eq 'R-002'}).Count -eq 1) 'Landing rule not applied to landing'
    Assert (@($r.Violations|Where-Object {$_.Rule -eq 'R-003'}).Count -eq 0) 'Ads requirement applied to landing'
}
Test 'without a scope every active rule applies' {
    $d=Put 'x.md' "Con piscina."
    $r=Test-AgentOpsRules -RulesPath $rulesPath -Path $d
    Assert (@($r.Violations|Where-Object {$_.Rule -in @('R-002','R-003')}).Count -eq 2) ($r|ConvertTo-Json -Depth 6)
}
Test 'missing required text is reported' {
    $d=Put 'ad.md' "Vive frente al mar."
    $r=Test-AgentOpsRules -RulesPath $rulesPath -Path $d -Scope anuncios
    Assert ($r.Code -eq 1 -and @($r.Violations|Where-Object {$_.Rule -eq 'R-003' -and $_.Kind -eq 'missing'}).Count -eq 1) ($r|ConvertTo-Json -Depth 6)
}
Test 'whole words only: a vetoed word inside another word is not a violation' {
    $d=Put 'ad.md' "Trabajamos con una aseguradora líder. Desde USD 120.000"
    Assert ((Test-AgentOpsRules -RulesPath $rulesPath -Path $d -Scope anuncios).Code -eq 0) 'Matched inside another word'
}
Test 'directories are scanned for text deliverables' {
    $dir=Join-Path $script:base ('entregables-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($dir)|Out-Null
    [IO.File]::WriteAllText((Join-Path $dir 'a.md'),'Desde USD 120.000',$utf8)
    [IO.File]::WriteAllText((Join-Path $dir 'b.html'),'<p>Inversión segura</p> Desde USD 120.000',$utf8)
    [IO.File]::WriteAllBytes((Join-Path $dir 'c.png'),[byte[]](137,80,78,71))
    $r=Test-AgentOpsRules -RulesPath $rulesPath -Path $dir -Scope anuncios
    Assert (@($r.Files).Count -eq 2 -and @($r.Violations|Where-Object {$_.Rule -eq 'R-001'}).Count -eq 1) ($r|ConvertTo-Json -Depth 6)
}
Test 'rules without patterns are returned for model review' {
    $d=Put 'ad.md' 'Desde USD 120.000'
    $r=Test-AgentOpsRules -RulesPath $rulesPath -Path $d -Scope anuncios
    Assert (@($r.ReviewRules|Where-Object {$_.Id -eq 'R-005'}).Count -eq 1) ($r|ConvertTo-Json -Depth 6)
    Assert (@($r.ReviewRules|Where-Object {$_.Id -eq 'R-004'}).Count -eq 0) 'Retired rule listed for review'
}
Test 'malformed or duplicated rules are reported as issues' {
    $bad=Put 'reglas.md' "### R-001 [expresion-vetada] [ámbito: todas] [estado: activa]`n- Detectar: `"x`"`n### R-001 [tono] [ámbito: todas] [estado: activa]`n- Regla: y`n### R-002 sin corchetes`n- Regla: z`n### R-003 [desconocido] [ámbito: todas] [estado: activa]`n- Regla: w`n"
    $d=Put 'ad.md' 'texto'
    $r=Test-AgentOpsRules -RulesPath $bad -Path $d
    Assert ($r.Code -eq 1) 'Malformed rules accepted'
    Assert (@($r.Issues|Where-Object {$_ -match 'R-001.*duplicad|duplicate'}).Count -ge 1) ($r.Issues -join '; ')
    Assert (@($r.Issues|Where-Object {$_ -match 'R-002'}).Count -ge 1) ($r.Issues -join '; ')
    Assert (@($r.Issues|Where-Object {$_ -match 'R-003'}).Count -ge 1) ($r.Issues -join '; ')
}
Test 'a missing rules file is an issue' {
    $d=Put 'ad.md' 'texto'
    $r=Test-AgentOpsRules -RulesPath (Join-Path $script:base 'absent.md') -Path $d
    Assert ($r.Code -eq 1 -and ($r.Issues -join ' ') -match 'not found') ($r|ConvertTo-Json -Depth 6)
}
Test 'the empty template has no rules and passes' {
    $template=Join-Path $source 'templates/context/reglas_proyecto.md'
    $d=Put 'ad.md' 'cualquier texto'
    $r=Test-AgentOpsRules -RulesPath $template -Path $d
    Assert ($r.Code -eq 0 -and @($r.Rules).Count -eq 0) ($r|ConvertTo-Json -Depth 6)
}
Test 'CLI returns JSON and the exit code' {
    $d=Put 'ad.md' 'Inversión segura'
    $engine=(Get-Process -Id $PID).Path
    $json=& $engine -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/check-rules.ps1') -RulesPath $rulesPath -Path $d -Scope anuncios|Out-String
    Assert ($LASTEXITCODE -eq 1 -and ($json|ConvertFrom-Json).Code -eq 1) $json
}
Test 'an example that its own Detectar does not catch is an issue' {
    $rp=Put 'reglas.md' "### R-001 [expresion-vetada] [ámbito: todas] [estado: activa]`n- Regla: No prometer rentabilidad.`n- Detectar: `"rentabilidad garantizada`"`n- Ejemplo: `"Rentabilidad asegurada desde el primer mes`"`n"
    $r=Test-AgentOpsRules -RulesPath $rp -Path (Put 'ad.md' 'texto limpio')
    Assert ($r.Code -eq 1 -and @($r.Issues|Where-Object {$_ -match 'R-001.*Ejemplo'}).Count -eq 1) ($r|ConvertTo-Json -Depth 6)
}
Test 'an example caught by Detectar is accepted and semantic examples reach the reviewer' {
    $rp=Put 'reglas.md' "### R-001 [expresion-vetada] [ámbito: todas] [estado: activa]`n- Regla: No prometer rentabilidad.`n- Detectar: `"re:rentabilidad\s+(garantizad|asegurad)[oa]`"`n- Ejemplo: `"Rentabilidad asegurada desde el primer mes`"`n`n### R-002 [prohibido-afirmar] [ámbito: todas] [estado: activa]`n- Regla: No afirmar que hay financiación bancaria.`n- Ejemplo: `"Te ayudamos con el crédito hipotecario`"`n"
    $r=Test-AgentOpsRules -RulesPath $rp -Path (Put 'ad.md' 'texto limpio')
    Assert ($r.Code -eq 0) ($r|ConvertTo-Json -Depth 6)
    $sem=@($r.ReviewRules|Where-Object {$_.Id -eq 'R-002'})
    Assert ($sem.Count -eq 1 -and @($sem[0].Examples) -contains 'Te ayudamos con el crédito hipotecario') ($r.ReviewRules|ConvertTo-Json -Depth 4)
}
function ReviewFixture {
    $rp=Put 'reglas.md' "### R-001 [prohibido-afirmar] [ámbito: todas] [estado: activa]`n- Regla: No afirmar que hay financiación bancaria.`n`n### R-002 [tono] [ámbito: todas] [estado: activa]`n- Regla: Tutear siempre al lector.`n"
    $d=Put 'ad.md' 'Conoce tu nueva casa.'
    $out=Join-Path $script:base ([guid]::NewGuid().ToString('N')+'-revision.md')
    $r=Test-AgentOpsRules -RulesPath $rp -Path $d -ReviewOut $out
    return @{Rules=$rp;Deliverable=$d;Out=$out;Result=$r}
}
Test 'ReviewOut writes a pending checklist with a fingerprint of rules and deliverables' {
    $f=ReviewFixture;$text=[IO.File]::ReadAllText($f.Out)
    Assert ($f.Result.Code -eq 0 -and $text -match '(?m)^- R-001: PENDIENTE' -and $text -match '(?m)^- R-002: PENDIENTE' -and $text -match '(?m)^Huella: [0-9a-f]{64}$') $text
    Assert ($text.Contains('No afirmar que hay financiación bancaria.') -and $text.Contains($f.Deliverable)) 'Checklist lacks rule text or deliverable'
}
Test 'a completed verdict passes; a pending or failed rule blocks delivery' {
    $f=ReviewFixture;$text=[IO.File]::ReadAllText($f.Out)
    $r=Test-AgentOpsRules -RulesPath $f.Rules -Path $f.Deliverable -ReviewVerdictPath $f.Out
    Assert ($r.Code -eq 1 -and @($r.Issues|Where-Object {$_ -match 'R-001.*PENDIENTE|PENDIENTE.*R-001'}).Count -eq 1) ($r|ConvertTo-Json -Depth 6)
    [IO.File]::WriteAllText($f.Out,($text -replace '- R-001: PENDIENTE','- R-001: PASA — no menciona financiación' -replace '- R-002: PENDIENTE','- R-002: FALLA — "Conozca" trata de usted'),$utf8)
    $r=Test-AgentOpsRules -RulesPath $f.Rules -Path $f.Deliverable -ReviewVerdictPath $f.Out
    Assert ($r.Code -eq 1 -and @($r.Violations|Where-Object {$_.Rule -eq 'R-002' -and $_.Kind -eq 'semantic'}).Count -eq 1) ($r|ConvertTo-Json -Depth 6)
    [IO.File]::WriteAllText($f.Out,($text -replace '- R-001: PENDIENTE','- R-001: PASA — no menciona financiación' -replace '- R-002: PENDIENTE','- R-002: PASA — tutea'),$utf8)
    $r=Test-AgentOpsRules -RulesPath $f.Rules -Path $f.Deliverable -ReviewVerdictPath $f.Out
    Assert ($r.Code -eq 0) ($r|ConvertTo-Json -Depth 6)
}
Test 'a verdict for an older version of the deliverable or rules is rejected' {
    $f=ReviewFixture;$text=[IO.File]::ReadAllText($f.Out)
    [IO.File]::WriteAllText($f.Out,($text -replace 'PENDIENTE','PASA — revisado'),$utf8)
    [IO.File]::AppendAllText($f.Deliverable,' Te ayudamos con el crédito.',$utf8)
    $r=Test-AgentOpsRules -RulesPath $f.Rules -Path $f.Deliverable -ReviewVerdictPath $f.Out
    Assert ($r.Code -eq 1 -and @($r.Issues|Where-Object {$_ -match 'Huella|fingerprint'}).Count -eq 1) ($r|ConvertTo-Json -Depth 6)
}
Test 'a verdict missing an applicable rule is rejected' {
    $f=ReviewFixture;$text=[IO.File]::ReadAllText($f.Out)
    [IO.File]::WriteAllText($f.Out,(($text -replace '- R-001: PENDIENTE','- R-001: PASA — ok') -replace '(?m)^- R-002: PENDIENTE\r?\n?',''),$utf8)
    $r=Test-AgentOpsRules -RulesPath $f.Rules -Path $f.Deliverable -ReviewVerdictPath $f.Out
    Assert ($r.Code -eq 1 -and @($r.Issues|Where-Object {$_ -match 'R-002'}).Count -eq 1) ($r|ConvertTo-Json -Depth 6)
}
Test 'CLI writes the review checklist and validates the verdict' {
    $f=ReviewFixture;$out2=$f.Out+'.cli.md';$engine=(Get-Process -Id $PID).Path;$cli=Join-Path $source 'scripts/check-rules.ps1'
    & $engine -NoProfile -ExecutionPolicy Bypass -File $cli -RulesPath $f.Rules -Path $f.Deliverable -ReviewOut $out2|Out-Null
    Assert ($LASTEXITCODE -eq 0 -and (Test-Path $out2)) 'CLI did not write the checklist'
    $json=& $engine -NoProfile -ExecutionPolicy Bypass -File $cli -RulesPath $f.Rules -Path $f.Deliverable -ReviewVerdictPath $out2|Out-String
    Assert ($LASTEXITCODE -eq 1) ('Pending verdict accepted by CLI: '+$json)
}
Test 'a long Regla line is a warning that does not block the gate' {
    $long=(1..31|ForEach-Object {"palabra$_"}) -join ' '
    $rp=Put 'reglas_largas.md' ("## Reglas activas`n`n### R-010 [expresion-vetada] [ámbito: todas] [estado: activa]`n- Regla: $long`n- Detectar: `"vetado`"`n`n### R-011 [expresion-vetada] [ámbito: todas] [estado: activa]`n- Regla: No usar `"otro`".`n- Detectar: `"otro`"`n")
    $d=Put 'ok.md' 'Texto limpio.'
    $r=Test-AgentOpsRules -RulesPath $rp -Path $d
    Assert ($r.Code -eq 0) ($r|ConvertTo-Json -Depth 6)
    $w=@($r.Warnings)
    Assert ($w.Count -eq 1 -and $w[0] -match 'R-010' -and $w[0] -match '31') ($r|ConvertTo-Json -Depth 6)
}
Write-Host "Rules check: $script:passed passed, $script:failed failed."
if($script:failed){exit 1}
