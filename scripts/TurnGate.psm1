Set-StrictMode -Version 2
# Turn gate (end-of-turn sensor). An agent may finish its turn only when the code it changed has green tests
# recorded by the framework itself (run-tests.ps1), never on its own word. Harness adapters only translate.
# Pilot: active only in the framework repository. Loop guard: at most two returns in a row per session.
Import-Module (Join-Path $PSScriptRoot 'NativeProcess.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'HarnessRadar.psm1') -Force
$script:codePattern='\.(ps1|psm1|psd1|sh|bat|cmd|py|js|mjs|cjs|ts)$|^\.github/workflows/.+\.ya?ml$|^scripts/.+\.json$'
$script:maxReturns=2

function Tg-Sha([byte[]]$bytes){$h=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($h.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}}
function Tg-Evidence([string]$root){Join-Path $root '.context/test-evidence.json'}

# Fingerprint of the uncommitted code: changed, new or deleted code files and their exact content.
function Get-AgentOpsCodeFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectPath)
    $root=(Resolve-Path -LiteralPath $ProjectPath).Path
    $raw=(Invoke-Git $root @('-c','core.quotePath=false','status','--porcelain=v1','-z','--untracked-files=all')).Output
    $items=@($raw -split "`0");$files=@()
    for($i=0;$i -lt $items.Count;$i++){
        $e=$items[$i];if($e.Length -lt 4){continue}
        $code=$e.Substring(0,2);$path=$e.Substring(3)
        if($code -match 'R|C'){$i++}  # renames/copies carry the old path as the next item
        if($path -match '^(\.context|docs)/' -or $path -notmatch $script:codePattern){continue}
        $full=Join-Path $root $path
        $hash=$(if([IO.File]::Exists($full)){Tg-Sha ([IO.File]::ReadAllBytes($full))}else{'deleted'})
        $files+=[pscustomobject]@{Path=$path;Hash=$hash}
    }
    $files=@($files|Sort-Object Path -Unique)
    $print=$(if($files.Count){Tg-Sha ([Text.Encoding]::UTF8.GetBytes((($files|ForEach-Object {"$($_.Path):$($_.Hash)"}) -join "`n")))}else{$null})
    return [pscustomobject]@{Fingerprint=$print;Files=@($files|ForEach-Object {$_.Path})}
}

# Runs the project's suites with the current engine and records evidence only if every suite is green
# and the code did not change while they ran.
function Invoke-AgentOpsTestRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectPath,[string[]]$Suites=@())
    $res=[ordered]@{Code=1;Status='RED';Fingerprint=$null;Results=@();Evidence=$null;Issues=@()}
    try{
        $root=(Resolve-Path -LiteralPath $ProjectPath).Path
        $before=Get-AgentOpsCodeFingerprint -ProjectPath $root;$res.Fingerprint=$before.Fingerprint
        $names=$(if($Suites.Count){$Suites}else{@(Get-ChildItem (Join-Path $root 'tests') -Filter '*.tests.ps1'|ForEach-Object {$_.Name -replace '\.tests\.ps1$',''})})
        $engine=(Get-Process -Id $PID).Path
        foreach($n in $names){
            $file=Join-Path $root "tests/$n.tests.ps1"
            if(-not [IO.File]::Exists($file)){$res.Results+=@([pscustomobject]@{Suite=$n;Exit=-1;Summary='no existe'});continue}
            $pref=$ErrorActionPreference;$ErrorActionPreference='Continue'
            try{$out=& $engine -NoProfile -ExecutionPolicy Bypass -File $file 2>&1|Out-String;$exit=$LASTEXITCODE}finally{$ErrorActionPreference=$pref}
            $res.Results+=@([pscustomobject]@{Suite=$n;Exit=$exit;Summary=(($out.Trim() -split "`n")[-1]).Trim()})
        }
        $after=Get-AgentOpsCodeFingerprint -ProjectPath $root
        if(@($res.Results|Where-Object {$_.Exit -ne 0}).Count){return [pscustomobject]$res}
        if($after.Fingerprint -ne $before.Fingerprint){$res.Issues=@('El código cambió mientras corrían las pruebas; vuelve a ejecutarlas.');return [pscustomobject]$res}
        $edition=$PSVersionTable.PSEdition
        $evidence=[ordered]@{SchemaVersion=1;Fingerprint=$before.Fingerprint;Files=$before.Files;Suites=@($res.Results|ForEach-Object {"$($_.Suite) ($edition): $($_.Summary)"});At=[datetime]::UtcNow.ToString('o')}
        $path=Tg-Evidence $root;[IO.Directory]::CreateDirectory((Split-Path $path))|Out-Null
        [IO.File]::WriteAllText($path,($evidence|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
        $res.Code=0;$res.Status='GREEN';$res.Evidence=$path
    }catch{$res.Issues=@($_.Exception.Message)}
    return [pscustomobject]$res
}

function Tg-Counter([string]$stateDir,[string]$sessionId){
    $dir=Join-Path $stateDir 'turn-gate';[IO.Directory]::CreateDirectory($dir)|Out-Null
    return Join-Path $dir ((Tg-Sha ([Text.Encoding]::UTF8.GetBytes([string]$sessionId))).Substring(0,16)+'.json')
}

function Test-AgentOpsTurnGate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectPath,[string]$StateDir=(Join-Path $env:LOCALAPPDATA 'AgentOps'),[string]$SessionId='')
    $res=[ordered]@{Decision='ALLOW';Status='CLEAN';Reason='';Files=@()}
    if(-not (Test-AgentOpsFrameworkRepository -ProjectPath $ProjectPath)){$res.Status='NOT_PILOT';return [pscustomobject]$res}
    $root=(Resolve-Path -LiteralPath $ProjectPath).Path
    $fp=Get-AgentOpsCodeFingerprint -ProjectPath $root
    $counter=Tg-Counter $StateDir $SessionId
    if(-not $fp.Fingerprint){if([IO.File]::Exists($counter)){[IO.File]::Delete($counter)};return [pscustomobject]$res}
    $res.Files=$fp.Files
    $ev=Tg-Evidence $root
    if([IO.File]::Exists($ev)){
        try{if(([IO.File]::ReadAllText($ev)|ConvertFrom-Json).Fingerprint -eq $fp.Fingerprint){$res.Status='VERIFIED';if([IO.File]::Exists($counter)){[IO.File]::Delete($counter)};return [pscustomobject]$res}}catch{}
    }
    $returns=0;if([IO.File]::Exists($counter)){try{$returns=[int](([IO.File]::ReadAllText($counter)|ConvertFrom-Json).Returns)}catch{}}
    if($returns -ge $script:maxReturns){
        [IO.File]::Delete($counter)
        $res.Status='UNVERIFIED';$res.Reason="Agent Ops: el turno termina sin pruebas verificadas tras $returns avisos; quedan cambios sin verificar en: $($fp.Files -join ', ')."
        return [pscustomobject]$res
    }
    [IO.File]::WriteAllText($counter,(@{Returns=$returns+1}|ConvertTo-Json),(New-Object Text.UTF8Encoding($false)))
    $shown=@($fp.Files|Select-Object -First 8);$more=$(if($fp.Files.Count -gt 8){" y $($fp.Files.Count-8) más"}else{''})
    $runner=Join-Path $root 'scripts/run-tests.ps1'
    $res.Decision='BLOCK';$res.Status='UNTESTED'
    $res.Reason="Agent Ops: hay cambios de código sin pruebas en verde de este estado: $($shown -join ', ')$more. Ejecuta las suites que los cubren con & `"$runner`" -ProjectPath `"$root`" -Suites <nombres> (o sin -Suites para todas) y vuelve a terminar. Si no puedes ejecutarlas, explícaselo al usuario."
    return [pscustomobject]$res
}

# --- Harness configuration (pilot: framework repository only) -------------------------------------------
function Tg-ToPlain($o){
    if($null -eq $o){return $null}
    if($o -is [Management.Automation.PSCustomObject]){$h=[ordered]@{};foreach($p in $o.PSObject.Properties){$h[$p.Name]=Tg-ToPlain $p.Value};return $h}
    if($o -is [Collections.IDictionary]){$h=[ordered]@{};foreach($k in $o.Keys){$h[$k]=Tg-ToPlain $o[$k]};return $h}
    if($o -is [Collections.IEnumerable] -and $o -isnot [string]){return ,@($o|ForEach-Object {Tg-ToPlain $_})}
    return $o
}
function Tg-Read([string]$path){if([IO.File]::Exists($path)){Tg-ToPlain ([IO.File]::ReadAllText($path)|ConvertFrom-Json)}else{[ordered]@{}}}
function Tg-Write([string]$path,$value){[IO.Directory]::CreateDirectory((Split-Path $path))|Out-Null;[IO.File]::WriteAllText($path,($value|ConvertTo-Json -Depth 12),(New-Object Text.UTF8Encoding($false)))}
function Tg-HasGate($list){@($list|Where-Object {($_|ConvertTo-Json -Depth 12 -Compress) -match 'turn-gate-hook\.ps1'}).Count -gt 0}

function Install-AgentOpsTurnGate {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectPath)
    $res=[ordered]@{Code=0;Status='NOT_PILOT';Files=@();Issues=@()}
    if(-not (Test-AgentOpsFrameworkRepository -ProjectPath $ProjectPath)){return [pscustomobject]$res}
    try{
        $root=(Resolve-Path -LiteralPath $ProjectPath).Path
        $hook=Join-Path $root 'scripts\turn-gate-hook.ps1'
        $win={param($h) "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$hook`" -Harness $h"}
        $changed=@()
        # Claude Code: personal project settings (not published); exec form with ${CLAUDE_PROJECT_DIR}.
        $p=Join-Path $root '.claude/settings.local.json';$c=Tg-Read $p
        if(-not $c.Contains('hooks')){$c['hooks']=[ordered]@{}}
        if(-not $c['hooks'].Contains('Stop')){$c['hooks']['Stop']=@()}
        if(-not (Tg-HasGate $c['hooks']['Stop'])){
            $c['hooks']['Stop']=@($c['hooks']['Stop'])+@([ordered]@{hooks=@([ordered]@{type='command';command='powershell.exe';args=@('-NoProfile','-ExecutionPolicy','Bypass','-File','${CLAUDE_PROJECT_DIR}/scripts/turn-gate-hook.ps1','-Harness','claude');timeout=60})})
            Tg-Write $p $c;$changed+=@($p)
        }
        # Codex: project hooks (trusted projects only; Codex asks to review them once).
        $p=Join-Path $root '.codex/hooks.json';$c=Tg-Read $p
        if(-not $c.Contains('hooks')){$c['hooks']=[ordered]@{}}
        if(-not $c['hooks'].Contains('Stop')){$c['hooks']['Stop']=@()}
        if(-not (Tg-HasGate $c['hooks']['Stop'])){
            $c['hooks']['Stop']=@($c['hooks']['Stop'])+@([ordered]@{hooks=@([ordered]@{type='command';command="pwsh -NoProfile -File `"$($hook -replace '\\','/')`" -Harness codex";commandWindows=(& $win 'codex');timeout=60})})
            Tg-Write $p $c;$changed+=@($p)
        }
        # Antigravity: workspace hooks, one named definition with Stop handlers directly under the event.
        $p=Join-Path $root '.agents/hooks.json';$c=Tg-Read $p
        if(-not $c.Contains('agent-ops-turn-gate')){
            $c['agent-ops-turn-gate']=[ordered]@{Stop=@([ordered]@{type='command';command=(& $win 'antigravity');timeout=60})}
            Tg-Write $p $c;$changed+=@($p)
        }
        $res.Files=$changed;$res.Status=$(if($changed.Count){'INSTALLED'}else{'UP_TO_DATE'})
    }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($_.Exception.Message)}
    return [pscustomobject]$res
}
Export-ModuleMember -Function Get-AgentOpsCodeFingerprint,Invoke-AgentOpsTestRun,Test-AgentOpsTurnGate,Install-AgentOpsTurnGate
