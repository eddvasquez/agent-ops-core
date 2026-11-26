# After-action hook adapter: records the action in the project's activity log and answers each harness in its format
# (Antigravity expects {}; Claude Code and Codex run it in the background and expect nothing). Never fails the action.
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('claude','codex','antigravity')][string]$Harness)
$ErrorActionPreference='Stop'
$utf8=New-Object Text.UTF8Encoding($false)
$out='{}'
try{
    Import-Module (Join-Path $PSScriptRoot 'ActivityLog.psm1') -Force
    $file=$env:AGENT_OPS_HOOK_INPUT_FILE
    $json=$(if($file -and [IO.File]::Exists($file)){$utf8.GetString([IO.File]::ReadAllBytes($file))}else{$b=New-Object IO.MemoryStream;[Console]::OpenStandardInput().CopyTo($b);$utf8.GetString($b.ToArray())})
    $state=$(if($env:AGENT_OPS_STATE_DIR){$env:AGENT_OPS_STATE_DIR}else{Join-Path $env:LOCALAPPDATA 'AgentOps'})
    Add-AgentOpsActivity -StateDir $state -Harness $Harness -Event $json
    if($Harness -ne 'antigravity'){
        try{
            $ev=$json.TrimStart([char]0xFEFF)|ConvertFrom-Json
            if($ev.PSObject.Properties['tool_name'] -and [string]$ev.tool_name -eq 'Skill' -and $ev.PSObject.Properties['tool_input'] -and $ev.tool_input.PSObject.Properties['skill']){
                $sk=[string]$ev.tool_input.skill
                $hub=$(if($env:AGENT_OPS_HUB_DIR){$env:AGENT_OPS_HUB_DIR}else{$wc=Join-Path $state 'watch-config.json';if([IO.File]::Exists($wc)){(Get-Content -LiteralPath $wc -Raw|ConvertFrom-Json).HubDir}else{''}})
                if($sk -and $hub -and [IO.Directory]::Exists($hub)){
                    Import-Module (Join-Path $PSScriptRoot 'LearningProposals.psm1') -Force
                    $cwd=if($ev.PSObject.Properties['cwd'] -and $ev.cwd){Split-Path -Leaf ([string]$ev.cwd)}else{'(sin proyecto)'}
                    $sid=if($ev.PSObject.Properties['session_id']){[string]$ev.session_id}else{''}
                    Register-SkillUsage -HubPath $hub -Skill $sk -Project $cwd -SessionId $sid -Harness $Harness -Source 'hook' -Outcome 'used'|Out-Null
                }
            }
        }catch{}
    }
    if($Harness -eq 'antigravity'){
        $e=$json.TrimStart([char]0xFEFF)|ConvertFrom-Json
        $dir=$(if($e.PSObject.Properties['workspacePaths']){[string](@($e.workspacePaths)|Select-Object -First 1)}else{''})
        if($dir -and [IO.Directory]::Exists((Join-Path $dir '.context/test-runs')) -and @(Get-ChildItem -LiteralPath (Join-Path $dir '.context/test-runs') -Filter '*.json' -ErrorAction SilentlyContinue).Count){
            Import-Module (Join-Path $PSScriptRoot 'TurnGate.psm1') -Force
            if(Get-AgentOpsActiveTestRun -ProjectPath $dir){
                $out=(@{hookSpecificOutput=@{hookEventName='PostToolUse';additionalContext='R-018: Hay pruebas corriendo en segundo plano. No esperes pasivamente; ofrece ahora al usuario con botones que siguiente tarea o diseno adelantar en paralelo (usa ops-git-worktrees si toca codigo).'}}|ConvertTo-Json -Compress -Depth 4)
            }
        }
    }
}catch{}
if($Harness -eq 'antigravity'){$o=[Console]::OpenStandardOutput();$bytes=$utf8.GetBytes($out);$o.Write($bytes,0,$bytes.Length);$o.Flush()}
exit 0
