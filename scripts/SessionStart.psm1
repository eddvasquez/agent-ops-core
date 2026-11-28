Set-StrictMode -Version 2
# Session start (Protocol 1 made automatic). In a project governed by Agent Ops Core, the harness tells the
# agent to run MODO ENTRADA before anything else, with a short local snapshot: no network, Git prevails.
# After a compaction it injects the active rules again (Protocol 8). Nothing recorded by a previous session
# (requests, next steps) is ever copied into the context: only whether it was interrupted.
Import-Module (Join-Path $PSScriptRoot 'HookIO.psm1')
Import-Module (Join-Path $PSScriptRoot 'RulesCheck.psm1')
Import-Module (Join-Path $PSScriptRoot 'ActivityLog.psm1')
$script:maxBrief=6000

# Git may write to stderr (a folder that is not a repository): in Windows PowerShell 5.1 that must not throw.
function Ss-Root([string]$path){
    $ErrorActionPreference='Continue'
    $full=[IO.Path]::GetFullPath($path)
    $top=(& git -C $full rev-parse --show-toplevel 2>$null)
    if($LASTEXITCODE -eq 0 -and $top){return [IO.Path]::GetFullPath(($top|Select-Object -First 1).Trim())}
    $d=$full
    while($d){if([IO.File]::Exists((Join-Path $d 'AGENTS.md'))){return $d};$p=[IO.Path]::GetDirectoryName($d);if($p -eq $d){break};$d=$p}
    return $full
}
function Ss-Governed([string]$root){
    $agents=Join-Path $root 'AGENTS.md'
    return ([IO.File]::Exists($agents) -and ([IO.File]::ReadAllText($agents,[Text.Encoding]::UTF8) -match 'MODO ENTRADA'))
}
function Ss-Norm([string]$p){
    if([string]::IsNullOrWhiteSpace($p)){return ''}
    try{return [IO.Path]::GetFullPath($p).TrimEnd('\','/')}catch{return $p.TrimEnd('\','/')}
}
function Ss-OutdatedAgents([string]$root){
    $agents=Join-Path $root 'AGENTS.md'
    if(-not [IO.File]::Exists($agents)){return $false}
    $txt=[IO.File]::ReadAllText($agents,[Text.Encoding]::UTF8)
    if($txt -notmatch '<!--\s*agent-ops:begin\s+version=(\d+\.\d+\.\d+)'){return $true}
    $cur=[version]$Matches[1]
    $vf=Join-Path (Split-Path $PSScriptRoot -Parent) 'docs\VERSION'
    if([IO.File]::Exists($vf)){
        $raw=([IO.File]::ReadAllText($vf,[Text.Encoding]::UTF8)).Trim()
        if($raw -match '^\d+\.\d+\.\d+$'){return ($cur -lt [version]$raw)}
    }
    return $false
}
function Ss-CanOfferInit([string]$root,[string]$stateDir){
    if([string]::IsNullOrWhiteSpace($stateDir) -or -not [IO.File]::Exists((Join-Path $stateDir 'update-state.json'))){return $false}
    $n=Ss-Norm $root
    if(-not $n){return $false}
    $pr=Ss-Norm ([IO.Path]::GetPathRoot($n))
    if($n -eq $pr){return $false}
    $excluded=@($env:USERPROFILE,$HOME,[IO.Path]::GetTempPath(),$env:TEMP,$env:TMP,$env:LOCALAPPDATA,$env:APPDATA)|ForEach-Object{Ss-Norm $_}|Where-Object{$_}
    if($excluded -contains $n){return $false}
    $stNorm=Ss-Norm $stateDir
    if($stNorm -and ($n -eq $stNorm -or $n.StartsWith($stNorm+'\',[StringComparison]::OrdinalIgnoreCase))){return $false}
    if($n -match '(?i)(^|[\\/])AgentOps-runtime([\\/]|$)'){return $false}
    $df=Join-Path $stateDir 'uninitialized-defer.json'
    $dj=Read-AgentOpsJsonFile $df
    if($dj -is [System.Collections.IDictionary] -and $dj.Contains('Projects') -and $dj['Projects']){
        foreach($item in @($dj['Projects'])){
            if((Ss-Norm ([string]$item)).Equals($n,[StringComparison]::OrdinalIgnoreCase)){return $false}
        }
    }
    return $true
}
function Ss-Dirty([string]$root){
    $ErrorActionPreference='Continue'
    $lines=@(& git -C $root -c core.quotepath=false status --porcelain --untracked-files=all 2>$null)
    if($LASTEXITCODE -ne 0){return -1}
    return @($lines|Where-Object {$_}).Count
}
function Ss-Interrupted([string]$root){
    $cp=Join-Path $root '.context/checkpoint.json'
    if(-not [IO.File]::Exists($cp)){return $false}
    try{$c=[IO.File]::ReadAllText($cp,[Text.Encoding]::UTF8)|ConvertFrom-Json;return ($c.PSObject.Properties['State'] -and [string]$c.State -ne 'CLOSED')}catch{return $false}
}
# What the cut session did since its checkpoint started, from the activity log (facts recorded by the harness).
function Ss-SinceCheckpoint([string]$root,[string]$stateDir){
    try{
        $c=[IO.File]::ReadAllText((Join-Path $root '.context/checkpoint.json'),[Text.Encoding]::UTF8)|ConvertFrom-Json
        # PowerShell 7 already turns ISO strings into DateTime while reading JSON; text would lose the zone.
        $since=$(if($c.PSObject.Properties['StartedAt'] -and $c.StartedAt){if($c.StartedAt -is [datetime]){$c.StartedAt}else{[datetime]::Parse([string]$c.StartedAt,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)}}else{[datetime]::MinValue})
        $a=Get-AgentOpsActivitySummary -StateDir $stateDir -ProjectPath $root -Since $since
        $n=@($a.Files).Count
        if(-not $n -and -not $a.TestRuns){return ''}
        $files=@($a.Files|Select-Object -First 6) -join ', ';if($n -gt 6){$files+=" y $($n-6) más"}
        $part=$(if($n){"tocó $n "+$(if($n -eq 1){'archivo'}else{'archivos'})+" ($files)"}else{'no tocó archivos'})
        $tests=$(if($a.TestRuns){" y hubo $($a.TestRuns) "+$(if($a.TestRuns -eq 1){'ejecución'}else{'ejecuciones'})+" de pruebas ($($a.TestFailures) en rojo)"}else{' y no ejecutó pruebas'})
        return "- Desde su último punto de control, la sesión cortada $part$tests (registro de actividad del arnés)."
    }catch{return ''}
}
function Ss-PendingUpdate([string]$stateDir){
    try{
        $s=[IO.File]::ReadAllText((Join-Path $stateDir 'update-state.json'))|ConvertFrom-Json
        $c=$(if($s.PSObject.Properties['Candidate']){$s.Candidate}else{$null})
        return ($c -and $c.PSObject.Properties['Sha'] -and $c.Sha -and -not ($c.PSObject.Properties['Approved'] -and $c.Approved) -and @('DETECTED','READY') -contains [string]$c.Status)
    }catch{return $false}
}
function Ss-Rules([string]$root,[int]$budget){
    $path=Join-Path $root '.context/reglas_proyecto.md'
    if(-not [IO.File]::Exists($path)){return @()}
    $all=@(& (Get-Module RulesCheck) {param($p) (Read-AgentOpsRules $p).Rules} $path|Where-Object {$_.State -eq 'activa'})
    $lines=@();$used=0;$shown=0
    foreach($r in $all){
        $line="- $($r.Id): «$($r.Text)»"
        if($used+$line.Length+1 -gt $budget){break}
        $lines+=$line;$used+=$line.Length+1;$shown++
    }
    if($shown -lt $all.Count){$lines+="- … y $($all.Count-$shown) más: léelas en .context/reglas_proyecto.md."}
    return $lines
}

function Get-AgentOpsSessionBrief {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectPath,
          [string]$StateDir=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'}),
          [ValidateSet('startup','resume','clear','compact','fork')][string]$Source='startup',
          [string]$Harness='')
    $root=Ss-Root $ProjectPath
    if(-not (Ss-Governed $root)){
        if($Source -ne 'compact' -and (Ss-CanOfferInit $root $StateDir)){
            return "Agent Ops Core · esta carpeta ($root) aún no usa Agent Ops Core. Si el usuario quiere empezar a usarlo aquí, explícale en lenguaje llano que puedes preparar la memoria del proyecto (ops-project-init) o recordar no volver a preguntar en esta carpeta con integrations.ps1 -Action DeferProjectInit -ProjectPath `"$root`"."
        }
        return ''
    }
    $out=New-Object Collections.Generic.List[string]
    $out.Add("Agent Ops Core · inicio de sesión ($Source) en $root.")
    if($Source -eq 'compact'){
        $out.Add('La conversación se acaba de compactar: no repitas el MODO ENTRADA; retoma el paso en curso y relee .context/reglas_proyecto.md antes del siguiente entregable (Protocolo 8). Reglas activas, literales:')
    }elseif($Source -eq 'resume'){
        $out.Add('Sesión reanudada: si en esta conversación aún no se hizo el MODO ENTRADA, hazlo antes de tocar archivos; si ya se hizo, vuelve a auditar Git (git status -s) antes de continuar.')
    }else{
        $out.Add('Este proyecto sigue AGENTS.md. Antes de tocar archivos o escribir código, haz el MODO ENTRADA con la skill ops-session-handoff (Paso 0 de actualización, lectura de AGENTS.md y .context/, auditoría Git y reporte de 5 puntos) y espera la confirmación explícita del usuario.')
    }
    $out.Add('Destilación silenciosa (Protocolo 4): observa cada corrección del usuario (qué falló -> corrección -> verificación) para clasificarla al cierre en su destino más ligero con session-distill.ps1 si hubo señal.')
    $facts=New-Object Collections.Generic.List[string]
    $dirty=Ss-Dirty $root
    if($dirty -eq 1){$facts.Add('- Hay 1 archivo sin guardar en Git.')}elseif($dirty -gt 1){$facts.Add("- Hay $dirty archivos sin guardar en Git.")}
    if(Ss-Interrupted $root){
        $facts.Add("- La sesión anterior se cortó antes de su MODO SALIDA: ejecuta resume-session.ps1 -ProjectPath `"$root`" y retómala desde su siguiente paso.")
        $did=Ss-SinceCheckpoint $root $StateDir;if($did){$facts.Add($did)}
    }
    if(Ss-PendingUpdate $StateDir){$facts.Add('- Hay una actualización verificada del marco pendiente de decisión: preséntala en el Paso 0.')}
    if($Source -ne 'compact' -and (Ss-OutdatedAgents $root)){$facts.Add('- AGENTS.md está desactualizado: sugiere al usuario poner al día el proyecto con migración (ops-project-migrate) en lenguaje llano; si aparece AGENTS_REVIEW_REQUIRED, explica cada cambio propio en lenguaje llano antes de decidir.')}
    try{
        if(-not (Get-Module ActivityLog)){Import-Module (Join-Path $PSScriptRoot 'ActivityLog.psm1') -Force}
        $cw=Get-AgentOpsConcurrentWriters -StateDir $StateDir -ProjectPath $root -CurrentHarness $Harness -WindowMinutes 15
        if($cw.Detected){
            $cFiles=@($cw.Files|Select-Object -First 4) -join ', '
            $facts.Add("- Aviso de escritor único (Protocolo 5): otro arnés ($($cw.Harnesses -join ', ')) escribió recientemente en este proyecto (hace $($cw.MinutesAgo) min: $cFiles). Confirma con el usuario antes de modificar archivos.")
        }
    }catch{}
    if($facts.Count -and $Source -ne 'compact'){$out.Add('Estado local (sin red; si discrepa con Git, prevalece Git):');foreach($f in $facts){$out.Add($f)}}
    if($Source -eq 'compact'){
        $used=($out -join "`n").Length
        foreach($l in (Ss-Rules $root ($script:maxBrief-$used-200))){$out.Add($l)}
        foreach($f in $facts){$out.Add($f)}
    }
    $text=($out -join "`n")
    if($text.Length -gt $script:maxBrief){$text=$text.Substring(0,$script:maxBrief-60)+"`n… (recortado: lee .context/reglas_proyecto.md)"}
    return $text
}

# Before a compaction (Claude Code: stdout becomes instructions for the summary). What the summary must keep so
# the next stretch of the session does not lose the user's words, the rules or the plan.
$script:maxCompact=3000
function Get-AgentOpsCompactInstructions {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ProjectPath)
    $root=Ss-Root $ProjectPath
    if(-not (Ss-Governed $root)){return ''}
    $out=New-Object Collections.Generic.List[string]
    $out.Add('Instrucciones de Agent Ops Core para este resumen. Conserva, con las palabras exactas del usuario cuando las haya:')
    $out.Add('1. Cada petición, corrección o rechazo del usuario en esta sesión, citado literalmente.')
    $out.Add('2. Las reglas registradas o enmendadas (R-NNN) con su texto literal.')
    $out.Add('3. El plan en curso: pasos hechos, paso actual y siguiente paso exacto.')
    $out.Add('4. Los archivos modificados y si están guardados (commit), publicados (push) o solo en disco.')
    $out.Add('5. Las decisiones o preguntas pendientes del usuario y las aprobaciones dadas (qué y para qué).')
    $out.Add('6. Los resultados de pruebas con suite, número de pruebas y versión de PowerShell.')
    $out.Add('7. Cada corrección del usuario resuelta en la sesión como trayectoria (qué falló -> corrección -> verificación) para destilar al cierre.')
    $out.Add('No conviertas en un resumen vago lo que el usuario pidió; si algo es incierto, dilo así.')
    $ErrorActionPreference='Continue'
    $files=@(& git -C $root -c core.quotepath=false status --porcelain --untracked-files=all 2>$null|Where-Object {$_}|ForEach-Object {$_.Substring(3).Trim('"')})
    if($LASTEXITCODE -eq 0 -and $files.Count){
        $shown=@($files|Select-Object -First 15)
        $more=$(if($files.Count -gt 15){" (y $($files.Count-15) más)"}else{''})
        $out.Add("Estado en Git ahora: $($files.Count) sin guardar: $($shown -join ', ')$more.")
    }
    $rulesPath=Join-Path $root '.context/reglas_proyecto.md'
    if([IO.File]::Exists($rulesPath)){
        $ids=@(& (Get-Module RulesCheck) {param($p) (Read-AgentOpsRules $p).Rules} $rulesPath|Where-Object {$_.State -eq 'activa'}|ForEach-Object {$_.Id})
        if($ids.Count){$out.Add("Reglas activas del proyecto: $($ids -join ', ') (texto en .context/reglas_proyecto.md).")}
    }
    $text=$out -join "`n"
    if($text.Length -gt $script:maxCompact){$text=$text.Substring(0,$script:maxCompact-40)+"`n… (recortado)"}
    return $text
}

# Answer in each harness's own format; an empty brief says nothing.
function ConvertTo-AgentOpsSessionStartOutput([string]$Harness,[string]$Brief){
    if($Harness -eq 'antigravity'){
        if(-not $Brief){return '{}'}
        return ([ordered]@{injectSteps=@([ordered]@{systemMessage=[ordered]@{systemMessage=$Brief;metadata=[ordered]@{source='agent-ops-core'}}})}|ConvertTo-Json -Depth 6 -Compress)
    }
    if(-not $Brief){return ''}
    return ([ordered]@{hookSpecificOutput=[ordered]@{hookEventName='SessionStart';additionalContext=$Brief}}|ConvertTo-Json -Depth 4 -Compress)
}

# Ours = an entry that runs the Agent Ops launcher with the session-start hook (args may be one string or a list).
function Ss-Without($list,[string]$pattern){,@($list|Where-Object {($_|ConvertTo-Json -Depth 12 -Compress) -notmatch $pattern})}
function Install-AgentOpsSessionStart {
    [CmdletBinding()]
    param([string]$StateDir=(Join-Path $env:LOCALAPPDATA 'AgentOps'),
          [string]$ClaudeSettingsPath=(Join-Path $HOME '.claude/settings.json'),
          [string]$CodexHooksPath=$(if($env:CODEX_HOME){Join-Path $env:CODEX_HOME 'hooks.json'}else{Join-Path $HOME '.codex/hooks.json'}),
          [string]$AntigravityHooksPath=(Join-Path $HOME '.gemini/config/hooks.json'),
          [switch]$Uninstall)
    $res=[ordered]@{Code=0;Status='UP_TO_DATE';Files=@();Issues=@()}
    try{
        $marker='agent-ops-hook\.ps1.{0,40}session-start';$matcher='startup|resume|clear|compact'
        $launcher=Join-Path $StateDir 'hooks/agent-ops-hook.ps1'
        $win={param($h) "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$launcher`" -Hook session-start -Harness $h"}
        $changed=New-Object Collections.Generic.List[string]
        if(-not $Uninstall){$l=Install-AgentOpsHookLauncher -StateDir $StateDir;if($l.Changed){$changed.Add($l.Path)}}
        $edit={param([string]$path,[scriptblock]$change)
            $c=Read-AgentOpsJsonFile $path;$before=$c|ConvertTo-Json -Depth 12 -Compress
            $c=& $change $c
            if(($c|ConvertTo-Json -Depth 12 -Compress) -ne $before){Write-AgentOpsJsonFile $path $c;$changed.Add($path)}
        }
        # Each entry is rebuilt from scratch: older versions are replaced, never duplicated; other hooks stay.
        $swap={param($c,$entry,[string]$event='SessionStart',[string]$pattern=$marker)
            if(-not $c.Contains('hooks')){$c['hooks']=[ordered]@{}}
            $list=$(if($c['hooks'].Contains($event)){Ss-Without @($c['hooks'][$event]) $pattern}else{@()})
            if($entry){$list=@($list)+@($entry)}
            if(@($list).Count){$c['hooks'][$event]=@($list)}elseif($c['hooks'].Contains($event)){$c['hooks'].Remove($event)}
            return $c}
        $claude=[ordered]@{matcher=$matcher;hooks=@([ordered]@{type='command';command='powershell.exe';args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,'-Hook','session-start','-Harness','claude');timeout=20})}
        $codex=[ordered]@{matcher=$matcher;hooks=@([ordered]@{type='command';command="pwsh -NoProfile -File `"$($launcher -replace '\\','/')`" -Hook session-start -Harness codex";commandWindows=(& $win 'codex');timeout=20;statusMessage='Agent Ops: preparando el inicio de sesión';additionalContextLimit=2500})}
        # Claude Code only: before a compaction its stdout becomes instructions for the summary (Codex ignores it).
        $compact=[ordered]@{matcher='manual|auto';hooks=@([ordered]@{type='command';command='powershell.exe';args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,'-Hook','pre-compact','-Harness','claude');timeout=20})}
        $isClaudePluginOn={param($c) ($c.Contains('enabledPlugins') -and $c['enabledPlugins'] -is [System.Collections.IDictionary] -and $c['enabledPlugins'].Contains('agent-ops-core@agent-ops') -and [bool]$c['enabledPlugins']['agent-ops-core@agent-ops'])}
        & $edit $ClaudeSettingsPath {param($c)
            $off=$Uninstall -or (& $isClaudePluginOn $c)
            $c=& $swap $c $(if($off){$null}else{$claude})
            & $swap $c $(if($off){$null}else{$compact}) 'PreCompact' 'agent-ops-hook\.ps1.{0,40}pre-compact'}
        # After each action (activity log): in the background where the harness allows it (Claude Code, Codex).
        $postClaude=[ordered]@{matcher='Edit|Write|MultiEdit|NotebookEdit|Bash|PowerShell|Skill';hooks=@([ordered]@{type='command';command='powershell.exe';args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,'-Hook','post-tool','-Harness','claude');async=$true;timeout=20})}
        $postCodex=[ordered]@{matcher='apply_patch|Bash';hooks=@([ordered]@{type='command';command="pwsh -NoProfile -File `"$($launcher -replace '\\','/')`" -Hook post-tool -Harness codex";commandWindows=("powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$launcher`" -Hook post-tool -Harness codex");async=$true;timeout=20})}
        $postPattern='agent-ops-hook\.ps1.{0,40}post-tool'
        & $edit $ClaudeSettingsPath {param($c) $off=$Uninstall -or (& $isClaudePluginOn $c); & $swap $c $(if($off){$null}else{$postClaude}) 'PostToolUse' $postPattern}
        # Claude Code: when a subagent stops, a reviewer that edited the deliverable is sent back (R-017).
        $subClaude=[ordered]@{hooks=@([ordered]@{type='command';command='powershell.exe';args=@('-NoProfile','-ExecutionPolicy','Bypass','-File',$launcher,'-Hook','subagent-stop','-Harness','claude');timeout=20})}
        & $edit $ClaudeSettingsPath {param($c) $off=$Uninstall -or (& $isClaudePluginOn $c); & $swap $c $(if($off){$null}else{$subClaude}) 'SubagentStop' 'agent-ops-hook\.ps1.{0,40}subagent-stop'}
        & $edit $CodexHooksPath {param($c)
            $c=& $swap $c $(if($Uninstall){$null}else{$codex})
            & $swap $c $(if($Uninstall){$null}else{$postCodex}) 'PostToolUse' $postPattern}
        & $edit $AntigravityHooksPath {param($c)
            if($c.Contains('agent-ops-session-start')){$c.Remove('agent-ops-session-start')}
            if($c.Contains('agent-ops-activity')){$c.Remove('agent-ops-activity')}
            if(-not $Uninstall -and -not [IO.File]::Exists((Join-Path (Split-Path -Parent $AntigravityHooksPath) 'plugins/agent-ops-core/plugin.json'))){$c['agent-ops-activity']=[ordered]@{PostToolUse=@([ordered]@{matcher='write_to_file|replace_file_content|multi_replace_file_content|run_command';hooks=@([ordered]@{type='command';command="powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$launcher`" -Hook post-tool -Harness antigravity";timeout=10})})}}
            if(-not $Uninstall -and -not [IO.File]::Exists((Join-Path (Split-Path -Parent $AntigravityHooksPath) 'plugins/agent-ops-core/plugin.json'))){$c['agent-ops-session-start']=[ordered]@{SessionStart=@([ordered]@{type='command';command=(& $win 'antigravity');timeout=20})}}
            return $c}
        $res.Files=@($changed)
        if($changed.Count){$res.Status=$(if($Uninstall){'REMOVED'}else{'INSTALLED'})}elseif($Uninstall){$res.Status='NOT_INSTALLED'}
    }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($_.Exception.Message)}
    return [pscustomobject]$res
}
Export-ModuleMember -Function Get-AgentOpsSessionBrief,Get-AgentOpsCompactInstructions,ConvertTo-AgentOpsSessionStartOutput,Install-AgentOpsSessionStart
