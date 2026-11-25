Set-StrictMode -Version 2
# Activity log (after each action). In a project governed by Agent Ops Core, every action that writes or runs is
# appended outside the repository: tool, relative paths and, for a command, only whether it ran tests and its exit
# code. Never command text, patch content or file content (they may hold credentials). A cut session can then be
# resumed from facts, not from what the agent remembered to note. No module dependencies: Antigravity waits for it.
$script:max=262144
$script:utf8=New-Object Text.UTF8Encoding($false)
$script:writes=@('Edit','Write','MultiEdit','NotebookEdit','apply_patch','write_to_file','replace_file_content','multi_replace_file_content')
$script:shells=@('Bash','PowerShell','run_command','shell','exec_command')
$script:testPattern='(?i)run-tests\.ps1|\.tests\.ps1|\bpytest\b|\bnpm\s+(run\s+)?test\b|\bdotnet\s+test\b|\bvitest\b|\bjest\b|\bgo\s+test\b'

function Al-Sha([string]$t){$h=[Security.Cryptography.SHA256]::Create();try{([BitConverter]::ToString($h.ComputeHash($script:utf8.GetBytes($t)))).Replace('-','').ToLowerInvariant()}finally{$h.Dispose()}}
function Al-Prop($o,[string]$n){if($null -ne $o -and $o.PSObject.Properties[$n]){$o.$n}else{$null}}
function Al-Root([string]$dir){
    if(-not $dir){return $null}
    try{$d=[IO.Path]::GetFullPath($dir).TrimEnd('\','/')}catch{return $null}
    while($d){
        $agents=Join-Path $d 'AGENTS.md'
        if([IO.File]::Exists($agents)){if([IO.File]::ReadAllText($agents) -match 'MODO ENTRADA'){return $d};return $null}
        $p=[IO.Path]::GetDirectoryName($d);if(-not $p -or $p -eq $d){break};$d=$p
    }
    return $null
}
function Al-Rel([string]$root,[string]$path){
    if(-not $path){return $null}
    $f=$(if([IO.Path]::IsPathRooted($path)){$path}else{Join-Path $root $path})
    try{$f=[IO.Path]::GetFullPath($f)}catch{return $null}
    if($f.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){return $f.Substring($root.Length+1).Replace('\','/')}
    return $null
}

function Get-AgentOpsActivityPath([string]$StateDir,[string]$ProjectPath){
    $root=[IO.Path]::GetFullPath($ProjectPath).TrimEnd('\','/')
    return (Join-Path $StateDir ('activity/'+(Al-Sha $root.ToLowerInvariant()).Substring(0,16)+'.jsonl'))
}

function Add-AgentOpsActivity {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$StateDir,[Parameter(Mandatory=$true)][string]$Harness,[Parameter(Mandatory=$true)][string]$Event)
    $e=$Event.TrimStart([char]0xFEFF)|ConvertFrom-Json
    if($Harness -eq 'antigravity'){$dir=[string](@(Al-Prop $e 'workspacePaths')|Select-Object -First 1);$call=Al-Prop $e 'toolCall';$tool=[string](Al-Prop $call 'name');$in=Al-Prop $call 'args'}
    else{$dir=[string](Al-Prop $e 'cwd');$tool=[string](Al-Prop $e 'tool_name');$in=Al-Prop $e 'tool_input'}
    $root=Al-Root $dir;if(-not $root){return}
    $line=[ordered]@{At=[datetime]::UtcNow.ToString('o');Harness=$Harness;Tool=$tool;Files=@();Tests=$false;Exit=$null}
    if($script:writes -contains $tool){
        $paths=@()
        foreach($k in 'file_path','notebook_path','TargetFile','AbsolutePath','path'){$v=Al-Prop $in $k;if($v){$paths+=[string]$v}}
        $patch=[string]$(if($tool -eq 'apply_patch'){$x=Al-Prop $in 'command';if(-not $x){$x=Al-Prop $in 'patch'};if(-not $x -and $in -is [string]){$x=$in};$x}else{''})
        foreach($m in [regex]::Matches($patch,'(?m)^\*\*\* (?:Update|Add|Delete) File:\s*(.+?)\s*$')){$paths+=$m.Groups[1].Value}
        $line.Files=@($paths|ForEach-Object {Al-Rel $root $_}|Where-Object {$_}|Select-Object -Unique)
        if(-not $line.Files.Count){return}
    }elseif($script:shells -contains $tool){
        $cmd=[string]$(if($in -is [string]){$in}else{$c=Al-Prop $in 'command';if(-not $c){$c=Al-Prop $in 'CommandLine'};$c})
        $line.Tests=[bool]($cmd -match $script:testPattern)
        $resp=$(if($Harness -eq 'antigravity'){$null}else{Al-Prop $e 'tool_response'})
        foreach($k in 'exitCode','exit_code','returnCode'){$v=Al-Prop $resp $k;if($null -ne $v){$line.Exit=[int]$v;break}}
        if($null -eq $line.Exit -and $Harness -eq 'antigravity'){$err=[string](Al-Prop $e 'error');$line.Exit=$(if($err){1}else{0})}
    }else{return}
    $path=Get-AgentOpsActivityPath -StateDir $StateDir -ProjectPath $root
    [IO.Directory]::CreateDirectory((Split-Path $path))|Out-Null
    if([IO.File]::Exists($path) -and (New-Object IO.FileInfo $path).Length -gt $script:max){[IO.File]::Copy($path,"$path.1",$true);[IO.File]::WriteAllText($path,'')}
    [IO.File]::AppendAllText($path,(($line|ConvertTo-Json -Compress)+"`n"),$script:utf8)
}

function Get-AgentOpsActivitySummary {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$StateDir,[Parameter(Mandatory=$true)][string]$ProjectPath,[datetime]$Since=[datetime]::MinValue)
    $res=[ordered]@{Files=@();Commands=0;TestRuns=0;TestFailures=0}
    $path=Get-AgentOpsActivityPath -StateDir $StateDir -ProjectPath $ProjectPath
    if(-not [IO.File]::Exists($path)){return [pscustomobject]$res}
    $since=$Since.ToUniversalTime();$files=New-Object Collections.Generic.List[string]
    foreach($raw in [IO.File]::ReadAllLines($path)){
        if(-not $raw.Trim()){continue}
        try{$l=$raw|ConvertFrom-Json}catch{continue}
        # PowerShell 7 turns ISO strings into DateTime while reading JSON; turning it back into text would lose the zone.
        $at=$(if($l.At -is [datetime]){$l.At.ToUniversalTime()}else{[datetime]::Parse([string]$l.At,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime()})
        if($at -lt $since){continue}
        foreach($f in @($l.Files)){if($f -and -not $files.Contains([string]$f)){$files.Add([string]$f)}}
        if($script:shells -contains [string]$l.Tool){$res.Commands++;if($l.Tests){$res.TestRuns++;if($null -ne $l.Exit -and [int]$l.Exit -ne 0){$res.TestFailures++}}}
    }
    $res.Files=@($files)
    return [pscustomobject]$res
}
Export-ModuleMember -Function Get-AgentOpsActivityPath,Add-AgentOpsActivity,Get-AgentOpsActivitySummary
