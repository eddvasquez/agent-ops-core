Set-StrictMode -Version 2
# Governed session distillation: turns session corrections and failure->fix cycles into the lightest
# destination (project rule, code check, low-risk skill patch or weekly inbox candidate) with zero
# noise on quiet sessions and mandatory secret blocking + anonymization before leaving the project.
Import-Module (Join-Path $PSScriptRoot 'LearningProposals.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'InstructionHarvest.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'ActivityLog.psm1') -Force

function Invoke-SessionDistill {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)][string]$ProjectPath,
        [string]$HubPath='',
        [string]$StateDir=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'}),
        [Nullable[datetime]]$Since=$null,
        [string[]]$RedactTerms=@(),
        [string]$ClaudeProjectsRoot=(Join-Path $env:USERPROFILE '.claude/projects'),
        [string]$CodexSessionsRoot=(Join-Path $env:USERPROFILE '.codex/sessions'),
        [string]$AntigravityBrainRoot=(Join-Path $env:USERPROFILE '.gemini/antigravity/brain'),
        [switch]$CaptureToInbox
    )
    $res=[ordered]@{Code=0;Status='QUIET';Project='';Since=$null;Findings=@();LowRiskReview=@();DeferredToWeekly=@();Captured=@();Blocked=@();Issues=@()}
    try{
        $root=[IO.Path]::GetFullPath($ProjectPath).TrimEnd('\','/')
        $projName=Split-Path -Leaf $root
        $res.Project=$projName
        if(-not [IO.Directory]::Exists($root)){return @{Code=1;Status='FAILED';Project=$projName;Since=$null;Findings=@();LowRiskReview=@();DeferredToWeekly=@();Captured=@();Blocked=@();Issues=@("Proyecto no encontrado: $root")}}
        if($null -eq $Since){
            $cp=Join-Path $root '.context/checkpoint.json'
            if([IO.File]::Exists($cp)){
                try{
                    $c=[IO.File]::ReadAllText($cp,[Text.Encoding]::UTF8)|ConvertFrom-Json
                    if($c.PSObject.Properties['StartedAt'] -and $c.StartedAt){
                        $Since=$(if($c.StartedAt -is [datetime]){$c.StartedAt}else{[datetime]::Parse([string]$c.StartedAt,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind)})
                    }
                }catch{}
            }
            if($null -eq $Since){$Since=(Get-Date).AddHours(-4)}
        }
        $sinceUtc=([datetime]$Since).ToUniversalTime()
        $res.Since=$sinceUtc.ToString('o')

        $terms=New-Object Collections.Generic.List[string]
        foreach($t in $RedactTerms){if(-not [string]::IsNullOrWhiteSpace($t)){$terms.Add($t.Trim())}}
        $ptFile=Join-Path $root '.context/private_terms.txt'
        if([IO.File]::Exists($ptFile)){
            foreach($l in [IO.File]::ReadAllLines($ptFile,[Text.Encoding]::UTF8)){
                $lt=$l.Trim();if($lt -and -not $lt.StartsWith('#')){$terms.Add($lt)}
            }
        }
        $termArr=@($terms|Select-Object -Unique)

        $harvest=Invoke-InstructionHarvest -ProjectPath $root -ClaudeProjectsRoot $ClaudeProjectsRoot -CodexSessionsRoot $CodexSessionsRoot -AntigravityBrainRoot $AntigravityBrainRoot -Since $sinceUtc
        $activity=Get-AgentOpsActivitySummary -StateDir $StateDir -ProjectPath $root -Since $sinceUtc

        $skillMeta=@{}
        if($HubPath -and [IO.Directory]::Exists($HubPath)){
            foreach($sk in (Get-LearningHubSkills $HubPath)){
                $fm=Read-SkillFrontmatter (Join-Path $HubPath "$sk/SKILL.md")
                $tokText=($sk -replace '-',' ')+' '+$fm.Description+' '+($fm.Triggers -join ' ')
                $skillMeta[$sk]=@(Get-SkillSemanticTokens $tokText)
            }
        }

        $findings=New-Object Collections.ArrayList
        $lowRisk=New-Object Collections.ArrayList
        $deferred=New-Object Collections.ArrayList
        $captured=New-Object Collections.ArrayList
        $blocked=New-Object Collections.ArrayList

        foreach($cand in @($harvest.Candidates)){
            $rawText=[string]$cand.Text
            if(Test-LearningSecretContent $rawText){
                [void]$blocked.Add([pscustomobject]@{Kind='directive';Reason='SECRET_BLOCKED';Text='[REDACTED_SECRET]'})
                continue
            }
            $san=(ConvertTo-SanitizedLearningText -Text $rawText -RedactTerms $termArr).Text
            $cTokens=@(Get-SkillSemanticTokens $san)
            $bestSkill='';$bestScore=0
            foreach($sk in ($skillMeta.Keys|Sort-Object)){
                if($san -match [regex]::Escape($sk)){$bestSkill=$sk;$bestScore=99;break}
                $inter=@($cTokens|Where-Object {$skillMeta[$sk] -contains $_}).Count
                if($inter -gt $bestScore){$bestScore=$inter;$bestSkill=$sk}
            }
            $dest='2';$kind='regla_proyecto';$risk='bajo'
            if($bestSkill -and $bestScore -ge 2){$dest='3';$kind='parche_skill'}
            $item=[pscustomobject]@{Destination=$dest;Kind=$kind;Risk=$risk;Skill=$bestSkill;Summary=$san;Evidence="Directiva de sesion ($($cand.Occurrences)x)"}
            [void]$findings.Add($item)
            if($dest -eq '3'){
                [void]$lowRisk.Add($item)
                if($CaptureToInbox -and $HubPath -and [IO.Directory]::Exists($HubPath)){
                    $cap=New-LearningCandidate -HubPath $HubPath -Signal 'correccion' -Project $projName -Harness 'session-distill' -Summary $san -Evidence $item.Evidence -Skill $bestSkill -RedactTerms $termArr
                    if($cap.Code -eq 0){[void]$captured.Add($cap)}
                    elseif($cap.Status -eq 'SECRET_BLOCKED'){[void]$blocked.Add($cap)}
                }
            }
        }

        if($activity.TestFailures -gt 0){
            $filesTxt=if(@($activity.Files).Count){($activity.Files|Select-Object -First 6) -join ', '}else{'(sin archivos)'}
            $sum="Ciclo de fallo en pruebas resuelto o editado ($($activity.TestFailures) fallo(s) en $filesTxt)"
            $sanSum=(ConvertTo-SanitizedLearningText -Text $sum -RedactTerms $termArr).Text
            $item=[pscustomobject]@{Destination='2b';Kind='comprobacion_codigo';Risk='bajo';Skill='';Summary=$sanSum;Evidence="ActivityLog: $($activity.TestRuns) ejecucion(es), $($activity.TestFailures) fallo(s)"}
            [void]$findings.Add($item)
            [void]$deferred.Add($item)
        }

        $res.Findings=$findings.ToArray()
        $res.LowRiskReview=$lowRisk.ToArray()
        $res.DeferredToWeekly=$deferred.ToArray()
        $res.Captured=$captured.ToArray()
        $res.Blocked=$blocked.ToArray()
        if($res.Findings.Count -or $res.Blocked.Count){$res.Status='SIGNAL_FOUND'}
    }catch{$res.Code=1;$res.Status='FAILED';$res.Issues=@($_.Exception.Message)}
    return [pscustomobject]$res
}

Export-ModuleMember -Function Invoke-SessionDistill