[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/LearningProposals.psm1') -Force
$base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-learning-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($base)|Out-Null
$passed=0;$failed=0
function Assert($v,$m){if(-not $v){throw $m}}
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_";Write-Host $_.ScriptStackTrace}}
function Hub([int]$Skills=3){
    $hub=Join-Path $base ([guid]::NewGuid().ToString('N'))
    $names=@('google-ads-media-buyer','gtm-media-buyer-orchestrator','google-ads-palabras-clave-nuevas')
    for($i=0;$i -lt $Skills;$i++){
        $name=if($i -lt $names.Count){$names[$i]}else{"skill-$i"}
        $dir=Join-Path $hub $name;[IO.Directory]::CreateDirectory($dir)|Out-Null
        [IO.File]::WriteAllText((Join-Path $dir 'SKILL.md'),"---`nname: $name`nversion: 1.4.2`ndescription: d`n---`n`n# $name`n")
    }
    [IO.Directory]::CreateDirectory((Join-Path $hub 'changelogs'))|Out-Null
    return $hub
}
function Snapshot($hub){
    @(Get-ChildItem $hub -Recurse -File|Where-Object {$_.FullName -notlike '*\proposals\*'}|Sort-Object FullName|ForEach-Object {$_.FullName+'='+(Get-FileHash $_.FullName).Hash}) -join "`n"
}
function Write-Proposal([string]$Text){
    $p=Join-Path $base ([guid]::NewGuid().ToString('N')+'.md');[IO.File]::WriteAllText($p,$Text,[Text.UTF8Encoding]::new($false));return $p
}
function Proposal([hashtable]$o=@{}){
    $f=@{Destino='3';Skill='google-ads-media-buyer';Version='1.4.2 -> 1.5.0';Riesgo='bajo';Size='+4 -1';Desc=$null
         Validation="";Overlaps="Ninguno: el formato solo lo define esta skill.";Umbral=$null;Fusion=$null}
    foreach($k in $o.Keys){$f[$k]=$o[$k]}
    $lines=@('# Propuesta 20261120-101500-a1b2c3','',"- Destino: $($f.Destino)","- Skill: $($f.Skill)","- Versión: $($f.Version)","- Riesgo: $($f.Riesgo)","- Tamaño: $($f.Size)")
    if($null -ne $f.Desc){$lines+="- Descripción nueva: $($f.Desc)"}
    $lines+=@('','## Por qué','Las entidades se citaban con dos formatos distintos según el archivo que el agente leía primero.','',
              '## Evidencia','- mcp for google tag manager, 2026-11-11: Regla 22 frente a la skill.','- google-ads-mcp, 2026-11-11: alertas con `(ID: X)`.','',
              '## Cambio','### Bloque 1','```diff','- Cita las entidades como `Nombre (ID: X)`.','+ Cita las entidades como `Nombre Exacto [ID X]`.','```','')
    if($f.Validation){$lines+=@('## Validación',$f.Validation,'')}
    $lines+=@('## Solapamientos',$f.Overlaps,'','## Alternativas descartadas','Regla de proyecto: el formato afecta a todos los proyectos de Google Ads.','')
    if($f.Umbral){$lines+=@('## Umbral')+$f.Umbral+@('')}
    if($f.Fusion){$lines+=@('## Fusión o archivo',$f.Fusion,'')}
    return ($lines -join "`n")
}
$allChecks=@('- [x] Repetida en al menos dos proyectos o tres sesiones.','- [x] Evidencia antes y después de que el modelo lo hace peor sin ella.','- [x] No cabe como parche o referencia de una skill existente.','- [x] Su descripción no se solapa con la de otra skill.')

# Caso A: candidatas huérfanas en mcp meta ads.
Test 'a captured candidate lands in the hub inbox with every field and never touches a skill' {
    $hub=Hub;$before=Snapshot $hub
    $r=New-LearningCandidate -HubPath $hub -Signal patron -Project 'mcp meta ads' -Harness 'Claude Code' -Summary 'Tests de wire para APIs publicitarias' -Evidence 'Los tests con mocks no verificaban el contrato real con Meta; aplica también a Google Ads y GTM.' -Skill 'google-ads-media-buyer' -Now ([datetime]'2026-11-20T10:15:00')
    Assert ($r.Code -eq 0 -and $r.Status -eq 'CAPTURED') ($r|ConvertTo-Json -Depth 5)
    Assert ($r.Path -like (Join-Path $hub 'proposals\inbox\20261120-101500-*.md')) "Unexpected path $($r.Path)"
    $t=[IO.File]::ReadAllText($r.Path)
    foreach($e in @('- Señal: patron','- Proyecto: mcp meta ads','- Arnés: Claude Code','- Skill: google-ads-media-buyer','## Resumen','Tests de wire','## Evidencia','contrato real con Meta')){Assert ($t.Contains($e)) "Missing '$e' in`n$t"}
    Assert ((Snapshot $hub) -eq $before) 'Capturing modified files outside proposals/'
}
Test 'two captures in the same second never overwrite each other' {
    $hub=Hub;$now=[datetime]'2026-11-20T10:15:00'
    $a=New-LearningCandidate -HubPath $hub -Signal exito -Project p -Harness h -Summary s -Evidence e -Now $now
    $b=New-LearningCandidate -HubPath $hub -Signal exito -Project p -Harness h -Summary s -Evidence e -Now $now
    Assert ($a.Code -eq 0 -and $b.Code -eq 0 -and $a.Path -ne $b.Path) 'Second capture collided'
    Assert ([IO.File]::ReadAllText($a.Path).Contains('- Skill: (sin asignar)')) 'Unassigned skill not stated'
}
Test 'invalid signals, empty evidence and skills outside the hub are rejected without writing' {
    $hub=Hub
    $r=New-LearningCandidate -HubPath $hub -Signal opinion -Project p -Harness h -Summary s -Evidence e
    Assert ($r.Code -eq 2 -and ($r.Issues -join ' ') -match 'Señal') ($r|ConvertTo-Json -Depth 5)
    $r=New-LearningCandidate -HubPath $hub -Signal fallo -Project p -Harness h -Summary s -Evidence '  '
    Assert ($r.Code -eq 2 -and ($r.Issues -join ' ') -match 'Evidencia') ($r|ConvertTo-Json -Depth 5)
    $r=New-LearningCandidate -HubPath $hub -Signal fallo -Project p -Harness h -Summary s -Evidence e -Skill 'impeccable'
    Assert ($r.Code -eq 2 -and ($r.Issues -join ' ') -match 'SKILL_NOT_IN_HUB') ($r|ConvertTo-Json -Depth 5)
    Assert (-not (Test-Path (Join-Path $hub 'proposals\inbox'))) 'Rejected candidate created the inbox'
}

# Caso D: mejora con riesgo medio respaldada por pruebas.
Test 'a complete proposal is valid and exposes its parsed fields' {
    $hub=Hub;$p=Write-Proposal (Proposal @{Riesgo='medio';Validation='170 pruebas simuladas antes y después; todas en verde.'})
    $r=Test-LearningProposal -Path $p -HubPath $hub
    Assert ($r.Code -eq 0 -and $r.Status -eq 'VALID') ($r|ConvertTo-Json -Depth 5)
    Assert ($r.Proposal.Skill -eq 'google-ads-media-buyer' -and $r.Proposal.To -eq '1.5.0' -and $r.Proposal.Blocks -eq 1 -and $r.Proposal.Added -eq 4 -and $r.Proposal.Removed -eq 1) ($r.Proposal|ConvertTo-Json)
}
Test 'medium or high risk without before/after validation is invalid' {
    $r=Test-LearningProposal -Path (Write-Proposal (Proposal @{Riesgo='alto'}))
    Assert ($r.Code -eq 2 -and ($r.Issues -join ' ') -match 'Validación') ($r|ConvertTo-Json -Depth 5)
}
# Caso E: engorde de la descripción de una skill.
Test 'a new description longer than 300 characters is invalid' {
    $r=Test-LearningProposal -Path (Write-Proposal (Proposal @{Desc=('x'*301)}))
    Assert ($r.Code -eq 2 -and ($r.Issues -join ' ') -match '300') ($r|ConvertTo-Json -Depth 5)
    $r=Test-LearningProposal -Path (Write-Proposal (Proposal @{Desc=('x'*300)}))
    Assert ($r.Code -eq 0) ($r|ConvertTo-Json -Depth 5)
}
# Caso B: un cambio que toca varias skills debe declarar sus solapamientos.
Test 'missing overlaps, reasons, evidence or blocks make a proposal invalid' {
    $t=(Proposal) -replace '(?s)## Solapamientos.*?(?=## Alternativas)',''
    $r=Test-LearningProposal -Path (Write-Proposal $t)
    Assert ($r.Code -eq 2 -and ($r.Issues -join ' ') -match 'Solapamientos') ($r|ConvertTo-Json -Depth 5)
    $t=(Proposal) -replace '### Bloque 1',''
    $r=Test-LearningProposal -Path (Write-Proposal $t)
    Assert ($r.Code -eq 2 -and ($r.Issues -join ' ') -match 'Bloque') ($r|ConvertTo-Json -Depth 5)
}
Test 'destinations, risk, size and versions must be well formed and the version must increase' {
    foreach($c in @(@{Destino='2'},@{Destino='7'},@{Riesgo='critico'},@{Size='doce'},@{Version='1.4.2 -> 1.4.2'},@{Version='1.4 -> 1.5'})){
        $r=Test-LearningProposal -Path (Write-Proposal (Proposal $c))
        Assert ($r.Code -eq 2) ("Accepted "+($c|ConvertTo-Json -Compress))
    }
}
Test 'a patch or reference must target a skill that exists in the hub' {
    $hub=Hub;$r=Test-LearningProposal -Path (Write-Proposal (Proposal @{Skill='impeccable'})) -HubPath $hub
    Assert ($r.Code -eq 2 -and ($r.Issues -join ' ') -match 'SKILL_NOT_IN_HUB') ($r|ConvertTo-Json -Depth 5)
}
Test 'a new skill must pass all four threshold checks' {
    $hub=Hub;$new=@{Destino='5';Skill='mcp-wire-tests';Version='nueva -> 1.0.0';Riesgo='medio';Validation='3 escenarios con y sin la skill.'}
    $partial=@($allChecks[0],'- [ ] Evidencia antes y después de que el modelo lo hace peor sin ella.',$allChecks[2],$allChecks[3])
    $r=Test-LearningProposal -Path (Write-Proposal (Proposal ($new+@{Umbral=$partial}))) -HubPath $hub
    Assert ($r.Code -eq 2 -and ($r.Issues -join ' ') -match 'Umbral') ($r|ConvertTo-Json -Depth 5)
    $r=Test-LearningProposal -Path (Write-Proposal (Proposal $new)) -HubPath $hub
    Assert ($r.Code -eq 2 -and ($r.Issues -join ' ') -match 'Umbral') 'Missing threshold section accepted'
    $r=Test-LearningProposal -Path (Write-Proposal (Proposal ($new+@{Umbral=$allChecks}))) -HubPath $hub
    Assert ($r.Code -eq 0) ($r|ConvertTo-Json -Depth 5)
    $existing=$new.Clone();$existing.Skill='google-ads-media-buyer';$existing.Umbral=$allChecks
    $r=Test-LearningProposal -Path (Write-Proposal (Proposal $existing)) -HubPath $hub
    Assert ($r.Code -eq 2 -and ($r.Issues -join ' ') -match 'ya existe') 'New skill with an existing name accepted'
}
Test 'at the 25-skill ceiling a new skill must merge or archive another' {
    $hub=Hub 25;$new=@{Destino='5';Skill='mcp-wire-tests';Version='nueva -> 1.0.0';Riesgo='medio';Validation='v';Umbral=$allChecks}
    $r=Test-LearningProposal -Path (Write-Proposal (Proposal $new)) -HubPath $hub
    Assert ($r.Code -eq 2 -and ($r.Issues -join ' ') -match '25') ($r|ConvertTo-Json -Depth 5)
    $r=Test-LearningProposal -Path (Write-Proposal (Proposal ($new+@{Fusion='Archivar skill-24: sin uso en 120 días.'}))) -HubPath $hub
    Assert ($r.Code -eq 0) ($r|ConvertTo-Json -Depth 5)
}
Test 'the queue reports inbox and pending counts and the active skill count' {
    $hub=Hub
    New-LearningCandidate -HubPath $hub -Signal fallo -Project p -Harness h -Summary s -Evidence e|Out-Null
    New-LearningCandidate -HubPath $hub -Signal patron -Project p -Harness h -Summary s -Evidence e|Out-Null
    $pending=Join-Path $hub 'proposals\pending';[IO.Directory]::CreateDirectory($pending)|Out-Null
    [IO.File]::WriteAllText((Join-Path $pending 'x.md'),(Proposal))
    $q=Get-LearningQueue -HubPath $hub
    Assert ($q.Code -eq 0 -and $q.Inbox -eq 2 -and $q.Pending -eq 1 -and $q.ActiveSkills -eq 3 -and $q.SkillCeiling -eq 25) ($q|ConvertTo-Json -Depth 5)
    $empty=Get-LearningQueue -HubPath (Hub)
    Assert ($empty.Inbox -eq 0 -and $empty.Pending -eq 0) 'Empty hub reported items'
}
Test 'the command-line wrappers return the same JSON contract and exit code' {
    $hub=Hub;$ps=(Get-Process -Id $PID).Path
    $out=& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/capture-learning.ps1') -HubPath $hub -Signal correccion -Project p -Harness h -Summary s -Evidence e
    Assert ($LASTEXITCODE -eq 0 -and ($out -join "`n"|ConvertFrom-Json).Status -eq 'CAPTURED') ($out -join "`n")
    $out=& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/check-proposal.ps1') -Path (Write-Proposal (Proposal @{Riesgo='alto'})) -HubPath $hub
    Assert ($LASTEXITCODE -eq 2 -and ($out -join "`n"|ConvertFrom-Json).Status -eq 'INVALID') ($out -join "`n")
    $out=& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/learning-queue.ps1') -HubPath $hub
    Assert ($LASTEXITCODE -eq 0 -and ($out -join "`n"|ConvertFrom-Json).Inbox -eq 1) ($out -join "`n")
}

Test 'triage groups inbox candidates by skill, counts project recurrence and supports discarding' {
    $hub=Hub
    New-LearningCandidate -HubPath $hub -Signal patron -Project projA -Harness claude -Summary 'Regla X' -Evidence 'ev1' -Skill 'google-ads-media-buyer' -Now ([datetime]'2026-11-20T10:00:00')|Out-Null
    New-LearningCandidate -HubPath $hub -Signal patron -Project projB -Harness codex -Summary 'Regla X' -Evidence 'ev2' -Skill 'google-ads-media-buyer' -Now ([datetime]'2026-11-21T10:00:00')|Out-Null
    $c3=New-LearningCandidate -HubPath $hub -Signal fallo -Project projA -Harness claude -Summary 'Solo projA' -Evidence 'ev3' -Now ([datetime]'2026-11-22T10:00:00')
    $t=Invoke-LearningTriage -HubPath $hub
    $g=@($t.Groups|Where-Object {$_.Skill -eq 'google-ads-media-buyer'})
    $single=@($t.Groups|Where-Object {$_.Skill -eq '(sin asignar)'})
    Assert ($t.Code -eq 0 -and $g.Count -eq 1 -and $g[0].Projects.Count -eq 2 -and $g[0].Decision -eq 'READY_FOR_PROPOSAL') ($t|ConvertTo-Json -Depth 5)
    Assert ($single.Count -eq 1 -and $single[0].Decision -eq 'PROJECT_RULE_CANDIDATE') ($t|ConvertTo-Json -Depth 5)
    $d=Invoke-LearningTriage -HubPath $hub -DiscardId $c3.Id -Reason 'Caso aislado de projA'
    Assert ($d.Code -eq 0 -and $d.Status -eq 'DISCARDED' -and -not (Test-Path $c3.Path) -and (Test-Path (Join-Path $hub "proposals/rejected/$($c3.Id).md"))) ($d|ConvertTo-Json -Depth 4)
}
Test 'apply-proposal applies only approved blocks, bumps SemVer, writes changelog and handles reject or mismatch' {
    $hub=Hub
    $skillMd=Join-Path $hub 'google-ads-media-buyer/SKILL.md'
    [IO.File]::WriteAllText($skillMd,"---`nname: google-ads-media-buyer`nversion: 1.0.0`n---`nRegla uno.`nRegla dos.`n",[Text.UTF8Encoding]::new($false))
    $pending=Join-Path $hub 'proposals/pending';[IO.Directory]::CreateDirectory($pending)|Out-Null
    $propText=@(
        '# Propuesta p1','',
        '- Destino: 3','- Skill: google-ads-media-buyer','- Version: 1.0.0 -> 1.1.0','- Riesgo: bajo','- Tamano: +2 -2','',
        '## Por que','Mejora verificada.','','## Evidencia','Caso real.','','## Cambio',
        '### Bloque 1','Antes:','```','Regla uno.','```','Después:','```','Regla uno mejorada.','```','',
        '### Bloque 2','Antes:','```','Regla dos.','```','Después:','```','Regla dos mejorada.','```','',
        '## Solapamientos','Ninguno.','','## Alternativas descartadas','Nada.'
    ) -join "`n"
    $propPath=Join-Path $pending 'p1.md'
    [IO.File]::WriteAllText($propPath,$propText,[Text.UTF8Encoding]::new($false))
    $res=Invoke-LearningProposalApply -HubPath $hub -Path $propPath -ApprovedBlocks @(1)
    Assert ($res.Code -eq 0 -and $res.Status -eq 'APPLIED' -and $res.AppliedBlocks -eq 1) ($res|ConvertTo-Json -Depth 4)
    $updated=[IO.File]::ReadAllText($skillMd)
    Assert ($updated -match 'version: 1\.1\.0' -and $updated -match 'Regla uno mejorada\.' -and $updated -match 'Regla dos\.' -and $updated -notmatch 'Regla dos mejorada\.') $updated
    Assert (Test-Path (Join-Path $hub 'changelogs/google-ads-media-buyer.md')) 'Skill changelog missing'
    Assert (-not (Test-Path $propPath) -and (Test-Path (Join-Path $hub 'proposals/applied/p1.md'))) 'Proposal not moved to applied'

    $badPath=Join-Path $pending 'p2.md'
    [IO.File]::WriteAllText($badPath,($propText -replace '1\.0\.0 -> 1\.1\.0','1.1.0 -> 1.2.0' -replace 'Regla uno\.','No existe en skill'),[Text.UTF8Encoding]::new($false))
    $mm=Invoke-LearningProposalApply -HubPath $hub -Path $badPath -ApprovedBlocks @(1)
    Assert ($mm.Code -eq 1 -and $mm.Status -eq 'PATCH_MISMATCH') ($mm|ConvertTo-Json -Depth 4)
    $rej=Invoke-LearningProposalApply -HubPath $hub -Path $badPath -Reject -Reason 'No aplica'
    Assert ($rej.Code -eq 0 -and $rej.Status -eq 'REJECTED' -and (Test-Path (Join-Path $hub 'proposals/rejected/p2.md'))) ($rej|ConvertTo-Json -Depth 4)
}
Test 'triage-learnings and apply-proposal CLI wrappers return JSON contract' {
    $hub=Hub;$ps=(Get-Process -Id $PID).Path
    New-LearningCandidate -HubPath $hub -Signal correccion -Project p1 -Harness claude -Summary 's1' -Evidence 'e1' -Skill 'google-ads-media-buyer'|Out-Null
    $out=& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/triage-learnings.ps1') -HubPath $hub
    Assert ($LASTEXITCODE -eq 0 -and ($out -join "`n"|ConvertFrom-Json).Code -eq 0) ($out -join "`n")
}
Test 'Register-SkillUsage writes single usage.jsonl, merges conflict copies and upgrades outcome without duplicating session' {
    $hub=Hub
    $r1=Register-SkillUsage -HubPath $hub -Skill 'google-ads-media-buyer' -Project 'proj1' -SessionId 'sess-1' -Harness 'claude' -Source 'hook' -Outcome 'used' -Now ([datetime]'2026-11-20T10:00:00Z')
    $r2=Register-SkillUsage -HubPath $hub -Skill 'google-ads-media-buyer' -Project 'proj1' -SessionId 'sess-1' -Harness 'claude' -Source 'declared' -Outcome 'helped' -Now ([datetime]'2026-11-20T10:05:00Z')
    Assert ($r1.Code -eq 0 -and $r2.Code -eq 0 -and $r2.Status -eq 'UPDATED') ($r2|ConvertTo-Json -Depth 4)
    $usageFile=Join-Path $hub 'proposals/usage.jsonl'
    Assert (Test-Path $usageFile) 'usage.jsonl missing'
    $rows=@([IO.File]::ReadAllLines($usageFile)|Where-Object {$_}|ForEach-Object {$_|ConvertFrom-Json})
    Assert ($rows.Count -eq 1 -and $rows[0].outcome -eq 'helped') ($rows|ConvertTo-Json -Depth 4)
    # Conflict copy from cloud sync is consolidated on read
    $conflict=Join-Path $hub 'proposals/usage (conflicted copy).jsonl'
    [IO.File]::WriteAllText($conflict,((@{timestamp='2026-11-21T10:00:00Z';skill='gtm-media-buyer-orchestrator';project='proj2';session_id='sess-2';harness='codex';source='declared';outcome='hurt'}|ConvertTo-Json -Compress)+"`n"),[Text.UTF8Encoding]::new($false))
    $all=@(Get-SkillUsageHistory -HubPath $hub)
    Assert ($all.Count -eq 2 -and (@($all|Where-Object {$_.skill -eq 'gtm-media-buyer-orchestrator'}).Count -eq 1)) ($all|ConvertTo-Json -Depth 4)
}
Test 'Sync-SkillUsageFromTranscripts detects Skill calls and SKILL.md reads across harnesses' {
    $hub=Hub;$proj=Join-Path $base ('proj-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory($proj)|Out-Null
    $clRoot=Join-Path $base ('cl-'+[guid]::NewGuid().ToString('N').Substring(0,6));[IO.Directory]::CreateDirectory((Join-Path $clRoot 'p1'))|Out-Null
    $clJson=(@{type='assistant';sessionId='cl-s1';timestamp='2026-11-25T10:00:00Z';cwd=$proj;message=@{role='assistant';content=@(@{type='tool_use';name='Skill';input=@{skill='google-ads-media-buyer'}})}}|ConvertTo-Json -Compress -Depth 6)
    [IO.File]::WriteAllText((Join-Path $clRoot 'p1/conv.jsonl'),"$clJson`n",[Text.UTF8Encoding]::new($false))
    $agRoot=Join-Path $base ('ag-'+[guid]::NewGuid().ToString('N').Substring(0,6));$agConv=Join-Path $agRoot 'conv1/.system_generated/logs';[IO.Directory]::CreateDirectory($agConv)|Out-Null
    $agLine=(@{source='MODEL';type='PLANNER_RESPONSE';created_at='2026-11-25T11:00:00Z';tool_calls=@(@{name='read_file';args=@{Path=(Join-Path $hub 'gtm-media-buyer-orchestrator/SKILL.md')}});content="Using $proj"}|ConvertTo-Json -Compress -Depth 6)
    [IO.File]::WriteAllText((Join-Path $agConv 'transcript.jsonl'),"$agLine`n",[Text.UTF8Encoding]::new($false))
    $sync=Sync-SkillUsageFromTranscripts -HubPath $hub -ProjectPath $proj -ClaudeProjectsRoot $clRoot -CodexSessionsRoot (Join-Path $base 'no-codex') -AntigravityBrainRoot $agRoot
    Assert ($sync.Code -eq 0 -and $sync.Recorded -ge 2) ($sync|ConvertTo-Json -Depth 5)
    $hist=@(Get-SkillUsageHistory -HubPath $hub)
    Assert ((@($hist|Where-Object {$_.skill -eq 'google-ads-media-buyer'}).Count -ge 1) -and (@($hist|Where-Object {$_.skill -eq 'gtm-media-buyer-orchestrator'}).Count -ge 1)) ($hist|ConvertTo-Json -Depth 4)
}
Test 'Get-SkillPruningCandidates guards cold-start, protects core/always_keep, detects 90d inactive & hurt, and closes archive/merge loop' {
    $hub=Hub 4
    $fw=Join-Path $base ('fw-'+[guid]::NewGuid().ToString('N').Substring(0,6));$fwSkills=Join-Path $fw 'skills';[IO.Directory]::CreateDirectory((Join-Path $fwSkills 'dev-tdd'))|Out-Null
    [IO.File]::WriteAllText((Join-Path $fwSkills 'dev-tdd/SKILL.md'),"---`nname: dev-tdd`nversion: 1.0.0`ndescription: tdd`n---`n# dev-tdd`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $hub 'skill-3/SKILL.md'),"---`nname: skill-3`nversion: 1.0.0`ndescription: d`nalways_keep: true`n---`n# s3`n",[Text.UTF8Encoding]::new($false))
    $now=[datetime]'2026-11-26T12:00:00Z'
    # Cold start: usage started only 10 days ago
    Register-SkillUsage -HubPath $hub -Skill 'google-ads-media-buyer' -Project 'p' -SessionId 's-cold' -Outcome 'used' -Now $now.AddDays(-10)|Out-Null
    $cold=Get-SkillPruningCandidates -HubPath $hub -FrameworkPath $fw -Now $now
    Assert ($cold.Code -eq 0 -and $cold.Status -eq 'INSUFFICIENT_HISTORY' -and @($cold.Candidates|Where-Object {$_.Status -eq 'PRUNE_INACTIVE'}).Count -eq 0) ($cold|ConvertTo-Json -Depth 5)
    # Mature history (>90 days): make google-ads-palabras-clave-nuevas old on disk and unused, and gtm hurt twice
    $oldDir=Join-Path $hub 'google-ads-palabras-clave-nuevas';(Get-Item $oldDir).CreationTimeUtc=$now.AddDays(-120);(Get-Item (Join-Path $oldDir 'SKILL.md')).LastWriteTimeUtc=$now.AddDays(-120)
    (Get-Item (Join-Path $hub 'skill-3')).CreationTimeUtc=$now.AddDays(-120);(Get-Item (Join-Path $hub 'skill-3/SKILL.md')).LastWriteTimeUtc=$now.AddDays(-120)
    Register-SkillUsage -HubPath $hub -Skill 'google-ads-media-buyer' -Project 'p' -SessionId 's-old' -Outcome 'used' -Now $now.AddDays(-110)|Out-Null
    Register-SkillUsage -HubPath $hub -Skill 'gtm-media-buyer-orchestrator' -Project 'p' -SessionId 'h1' -Outcome 'hurt' -Now $now.AddDays(-5)|Out-Null
    Register-SkillUsage -HubPath $hub -Skill 'gtm-media-buyer-orchestrator' -Project 'p' -SessionId 'h2' -Outcome 'hurt' -Now $now.AddDays(-2)|Out-Null
    $pr=Get-SkillPruningCandidates -HubPath $hub -FrameworkPath $fw -Now $now -EmitProposals
    Assert ($pr.Code -eq 0 -and (@($pr.Candidates|Where-Object {$_.Skill -eq 'google-ads-palabras-clave-nuevas' -and $_.Status -eq 'PRUNE_INACTIVE'}).Count -eq 1)) ($pr|ConvertTo-Json -Depth 5)
    Assert ((@($pr.Candidates|Where-Object {$_.Skill -eq 'gtm-media-buyer-orchestrator' -and $_.Status -eq 'REVIEW_HURT'}).Count -eq 1)) ($pr|ConvertTo-Json -Depth 5)
    Assert ((@($pr.Candidates|Where-Object {$_.Skill -eq 'skill-3' -and $_.Status -eq 'PROTECTED'}).Count -eq 1)) ($pr|ConvertTo-Json -Depth 5)
    Assert ($pr.EmittedProposals.Count -ge 1 -and (Test-Path $pr.EmittedProposals[0])) ($pr|ConvertTo-Json -Depth 5)
    $check=Test-LearningProposal -Path $pr.EmittedProposals[0] -HubPath $hub
    Assert ($check.Code -eq 0) ($check|ConvertTo-Json -Depth 4)
    # Apply archive proposal (destination 6) without deleting
    $app=Invoke-LearningProposalApply -HubPath $hub -Path $pr.EmittedProposals[0] -ApprovedBlocks @(1)
    Assert ($app.Code -eq 0 -and $app.Status -eq 'APPLIED' -and -not (Test-Path $oldDir) -and (Test-Path (Join-Path $hub 'proposals/archived/google-ads-palabras-clave-nuevas/SKILL.md'))) ($app|ConvertTo-Json -Depth 4)
}
Test 'Test-SkillCatalog parses multiline YAML, detects containment + Jaccard overlaps across hub and core, and distinguishes errors vs warnings' {
    $hub=Hub 2;$fw=Join-Path $base ('fw2-'+[guid]::NewGuid().ToString('N').Substring(0,6));$fwSkills=Join-Path $fw 'skills'
    [IO.Directory]::CreateDirectory((Join-Path $fwSkills 'dev-tdd'))|Out-Null
    [IO.File]::WriteAllText((Join-Path $fwSkills 'dev-tdd/SKILL.md'),"---`nname: dev-tdd`nversion: 1.0.0`ndescription: >-`n  Metodologia estricta TDD para pruebas automatizadas antes de codigo.`ntriggers:`n  - `"dev-tdd`"`n  - `"red-green-refactor`"`n---`n# dev-tdd`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $hub 'google-ads-media-buyer/SKILL.md'),"---`nname: google-ads-media-buyer`nversion: 1.0.0`ndescription: Auditoria completa de campanas Google Ads, pujas Smart Bidding, palabras clave negativas, calidad de subasta, presupuestos y conversiones offline para cuentas B2B y e-commerce.`n---`n# big`n",[Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText((Join-Path $hub 'gtm-media-buyer-orchestrator/SKILL.md'),"---`nname: gtm-media-buyer-orchestrator`nversion: 1.0.0`ndescription: Auditoria de campanas Google Ads y palabras clave negativas.`n---`n# small`n",[Text.UTF8Encoding]::new($false))
    $cat=Test-SkillCatalog -HubPath $hub -FrameworkPath $fw -Strict
    Assert ($cat.Code -eq 0 -and $cat.Summary.HubSkills -eq 2 -and $cat.Summary.TotalDescriptionChars -gt 100 -and $cat.Overlaps.Count -ge 1 -and (@($cat.Overlaps|Where-Object {$_.Containment -ge 0.7}).Count -ge 1)) ($cat|ConvertTo-Json -Depth 5)
    # Hard error when > 1024 chars
    [IO.File]::WriteAllText((Join-Path $hub 'gtm-media-buyer-orchestrator/SKILL.md'),"---`nname: gtm-media-buyer-orchestrator`nversion: 1.0.0`ndescription: $('x'*1025)`n---`n# too long`n",[Text.UTF8Encoding]::new($false))
    $bad=Test-SkillCatalog -HubPath $hub -FrameworkPath $fw -Strict
    Assert ($bad.Code -eq 2 -and $bad.Errors.Count -ge 1) ($bad|ConvertTo-Json -Depth 5)
}
Test 'Phase 3 CLI wrappers record-usage, prune-skills and check-skill-catalog return JSON contract' {
    $hub=Hub;$ps=(Get-Process -Id $PID).Path
    $o1=& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/record-usage.ps1') -HubPath $hub -Skill 'google-ads-media-buyer' -Project p1 -Outcome helped
    Assert ($LASTEXITCODE -eq 0 -and ($o1 -join "`n"|ConvertFrom-Json).Code -eq 0) ($o1 -join "`n")
    $o2=& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/prune-skills.ps1') -HubPath $hub
    Assert ($LASTEXITCODE -eq 0 -and ($o2 -join "`n"|ConvertFrom-Json).Code -eq 0) ($o2 -join "`n")
    $o3=& $ps -NoProfile -ExecutionPolicy Bypass -File (Join-Path $source 'scripts/check-skill-catalog.ps1') -HubPath $hub -FrameworkPath $source
    Assert ($LASTEXITCODE -eq 0 -and ($o3 -join "`n"|ConvertFrom-Json).Code -eq 0) ($o3 -join "`n")
}
Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "Passed: $passed Failed: $failed"
if(-not $failed){Remove-TestFixtures $base}
if($failed){exit 1}
