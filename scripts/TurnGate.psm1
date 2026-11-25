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
# Which suites cover the uncommitted code: a suite file itself; for a script or module, every suite that loads
# it directly or through modules that import it. Shared test helpers, CI or anything unresolved select all.
function Get-AgentOpsSuitesForChanges {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectPath)
    $root=(Resolve-Path -LiteralPath $ProjectPath).Path
    $suites=@(Get-ChildItem (Join-Path $root 'tests') -Filter '*.tests.ps1' -ErrorAction SilentlyContinue)
    $all=@($suites|ForEach-Object {$_.Name -replace '\.tests\.ps1$',''}|Sort-Object)
    $changed=@((Get-AgentOpsCodeFingerprint -ProjectPath $root).Files)
    $res=[ordered]@{Suites=@();All=$false;Files=$changed}
    if(-not $changed.Count){return [pscustomobject]$res}
    $code=@(Get-ChildItem (Join-Path $root 'scripts') -File -ErrorAction SilentlyContinue)
    $text=@{};foreach($f in @($code)+@($suites)){$text[$f.FullName]=[IO.File]::ReadAllText($f.FullName)}
    $picked=@()
    foreach($path in $changed){
        if($path -match '^tests/([^/]+)\.tests\.ps1$'){$picked+=$Matches[1];continue}
        if($path -match '^(tests|\.github)/'){$res.All=$true;break}
        # Closure: the changed file plus every script/module that references a name already in the set.
        $names=@([IO.Path]::GetFileName($path));$grew=$true
        while($grew){
            $grew=$false
            foreach($f in $code){
                if($names -contains $f.Name){continue}
                foreach($n in $names){if($text[$f.FullName].IndexOf($n,[StringComparison]::OrdinalIgnoreCase) -ge 0){$names+=$f.Name;$grew=$true;break}}
            }
        }
        $cover=@($suites|Where-Object {$s=$text[$_.FullName];@($names|Where-Object {$s.IndexOf($_,[StringComparison]::OrdinalIgnoreCase) -ge 0}).Count}|ForEach-Object {$_.Name -replace '\.tests\.ps1$',''})
        if(-not $cover.Count){$res.All=$true;break}
        $picked+=$cover
    }
    $res.Suites=$(if($res.All){$all}else{@($picked|Sort-Object -Unique)})
    return [pscustomobject]$res
}

# Runs suites as separate processes sharing this console (some suites start git or PowerShell that need one),
# up to -Parallel at a time (each suite has its own temp folder and lock
# namespace, so they do not collide). Evidence is recorded only if all are green and the code did not change.
# Parts to run at once with -Parallel 0, from the machine's real capacity and with no fixed ceiling (R-012): half the
# logical cores (measured on 8: 4 parts fastest; 6 no faster and timing-sensitive tests failed, since every part also
# runs Git and the antivirus scans its files) and 250 MB of free memory per part.
function Get-AgentOpsTestSlots {
    [CmdletBinding()]
    param([int]$Cores=[Environment]::ProcessorCount,[int]$FreeMB=-1)
    if($FreeMB -lt 0){try{$FreeMB=[int]((Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).FreePhysicalMemory/1KB)}catch{$FreeMB=1024}}
    $slots=[Math]::Floor($Cores/2)
    $slots=[Math]::Min($slots,[Math]::Floor($FreeMB/250))
    return [int][Math]::Max(1,$slots)
}
function Tg-AcceptsShard([string]$file){
    $tokens=$null;$errors=$null
    $ast=[Management.Automation.Language.Parser]::ParseFile($file,[ref]$tokens,[ref]$errors)
    return [bool]($ast.ParamBlock -and @($ast.ParamBlock.Parameters|Where-Object {$_.Name.VariablePath.UserPath -eq 'Shard'}).Count)
}
function Invoke-AgentOpsTestRun {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ProjectPath,[string[]]$Suites=@(),[int]$Parallel=1,[switch]$Changed)
    $res=[ordered]@{Code=1;Status='RED';Fingerprint=$null;Results=@();Evidence=$null;Issues=@()}
    $temp=@()
    try{
        $root=(Resolve-Path -LiteralPath $ProjectPath).Path
        $before=Get-AgentOpsCodeFingerprint -ProjectPath $root;$res.Fingerprint=$before.Fingerprint
        if($Changed){
            $names=@((Get-AgentOpsSuitesForChanges -ProjectPath $root).Suites)
            if(-not $names.Count){$res.Code=0;$res.Status='NOTHING_TO_RUN';return [pscustomobject]$res}
        }elseif($Suites.Count){$names=$Suites}
        else{$names=@(Get-ChildItem (Join-Path $root 'tests') -Filter '*.tests.ps1'|ForEach-Object {$_.Name -replace '\.tests\.ps1$',''})}
        $engine=(Get-Process -Id $PID).Path;$slots=if($Parallel -le 0){Get-AgentOpsTestSlots}else{$Parallel}
        # With -Parallel N, a suite that accepts -Shard runs as N parts at once (its slowest part sets the pace).
        # Split suites are the slow ones: their parts go first so the run does not end waiting on them.
        $queue=New-Object Collections.Queue;$parts=@{};$split=@();$whole=@()
        foreach($n in $names){
            $file=Join-Path $root "tests/$n.tests.ps1"
            $parts[$n]=New-Object Collections.ArrayList
            if($slots -gt 1 -and [IO.File]::Exists($file) -and (Tg-AcceptsShard $file)){$split+=@(1..$slots|ForEach-Object {[pscustomobject]@{Suite=$n;File=$file;Shard="$_/$slots"}})}
            else{$whole+=@([pscustomobject]@{Suite=$n;File=$file;Shard=''})}
        }
        foreach($job in @($split)+@($whole)){$queue.Enqueue($job)}
        $running=@()
        while($queue.Count -or $running.Count){
            while($queue.Count -and $running.Count -lt $slots){
                $job=$queue.Dequeue()
                if(-not [IO.File]::Exists($job.File)){[void]$parts[$job.Suite].Add([pscustomobject]@{Exit=-1;Summary='no existe';Shard=''});continue}
                $out=[IO.Path]::GetTempFileName();$err=[IO.Path]::GetTempFileName();$temp+=@($out,$err)
                $arguments=@('-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$($job.File)`"");if($job.Shard){$arguments+=@('-Shard',$job.Shard)}
                $proc=Start-Process -FilePath $engine -ArgumentList $arguments -RedirectStandardOutput $out -RedirectStandardError $err -NoNewWindow -PassThru
                $null=$proc.Handle  # keeps the exit code available after the process ends
                $running+=@([pscustomobject]@{Job=$job;Process=$proc;Out=$out})
            }
            $finished=@($running|Where-Object {$_.Process.HasExited})
            if(-not $finished.Count){$null=$running[0].Process.WaitForExit(250);continue}
            foreach($r in $finished){
                $r.Process.WaitForExit()
                $lines=@([IO.File]::ReadAllLines($r.Out)|Where-Object {$_.Trim()})
                [void]$parts[$r.Job.Suite].Add([pscustomobject]@{Exit=$r.Process.ExitCode;Summary=$(if($lines.Count){$lines[-1].Trim()}else{''});Shard=$r.Job.Shard})
                $r.Process.Dispose()
            }
            $running=@($running|Where-Object {$finished -notcontains $_})
        }
        $res.Results=@($names|ForEach-Object {
            $p=@($parts[$_]|Sort-Object Shard)
            $exit=0;foreach($x in $p){if($x.Exit -ne 0){$exit=$x.Exit}}
            $summary=if($p.Count -eq 1 -and -not $p[0].Shard){$p[0].Summary}else{($p|ForEach-Object {"[$($_.Shard)] $($_.Summary)"}) -join ' | '}
            [pscustomobject]@{Suite=$_;Exit=$exit;Summary=$summary}
        })
        $after=Get-AgentOpsCodeFingerprint -ProjectPath $root
        if(@($res.Results|Where-Object {$_.Exit -ne 0}).Count){return [pscustomobject]$res}
        if($after.Fingerprint -ne $before.Fingerprint){$res.Issues=@('El código cambió mientras corrían las pruebas; vuelve a ejecutarlas.');return [pscustomobject]$res}
        $edition=$PSVersionTable.PSEdition
        $evidence=[ordered]@{SchemaVersion=1;Fingerprint=$before.Fingerprint;Files=$before.Files;Suites=@($res.Results|ForEach-Object {"$($_.Suite) ($edition): $($_.Summary)"});At=[datetime]::UtcNow.ToString('o')}
        $path=Tg-Evidence $root;[IO.Directory]::CreateDirectory((Split-Path $path))|Out-Null
        [IO.File]::WriteAllText($path,($evidence|ConvertTo-Json -Depth 5),(New-Object Text.UTF8Encoding($false)))
        $res.Code=0;$res.Status='GREEN';$res.Evidence=$path
    }catch{$res.Issues=@($_.Exception.Message)}
    finally{foreach($f in $temp){Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue}}
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
Export-ModuleMember -Function Get-AgentOpsCodeFingerprint,Get-AgentOpsSuitesForChanges,Get-AgentOpsTestSlots,Invoke-AgentOpsTestRun,Test-AgentOpsTurnGate,Install-AgentOpsTurnGate
