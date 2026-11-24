# Repository hygiene: traps that broke releases or agent work on Windows PowerShell 5.1.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
$failures=New-Object Collections.Generic.List[string];$passed=0
$tracked=@(& git -C $source -c core.quotepath=false ls-files)

# 1. Windows PowerShell 5.1 reads BOM-less scripts as ANSI: non-ASCII code must carry a UTF-8 BOM.
foreach($f in @($tracked|Where-Object {$_ -match '\.(ps1|psm1)$'})){
    $bytes=[IO.File]::ReadAllBytes((Join-Path $source $f))
    $bom=$bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
    if(-not $bom -and @($bytes|Where-Object {$_ -gt 127}).Count){$failures.Add("$f has non-ASCII characters without a UTF-8 BOM")}
}
if(-not $failures.Count){$passed++;Write-Host 'PASS every PowerShell file is ASCII or UTF-8 with BOM'}

# 2. Agent instructions must not tell agents to compose commits by hand (quotes break on 5.1; no fail-fast).
$before=$failures.Count
$instructions=@($tracked|Where-Object {($_ -match '^(skills|templates)/.*\.md$') -or $_ -eq 'README.md'})
foreach($f in $instructions){
    $n=0
    foreach($line in [IO.File]::ReadAllLines((Join-Path $source $f),[Text.Encoding]::UTF8)){
        $n++
        # Lines that forbid the pattern are fine ("Prohibido `git add .`", "No ejecutar `git add -A`").
        if($line -match '(?i)prohib|no ejecutar|nunca|never|do not|don''t'){continue}
        if($line -match 'git\s+commit\s+-m\b'){$failures.Add("${f}:$n instructs 'git commit -m'; use scripts/commit.ps1")}
        if($line -match 'git\s+add\s+(\.|-A|--all)(\s|`|$)'){$failures.Add("${f}:$n instructs 'git add .'/'-A'; stage explicit paths through scripts/commit.ps1")}
        if($line -match 'git\s+tag\s+-a\b'){$failures.Add("${f}:$n instructs 'git tag -a'; use scripts/commit.ps1 -Tag")}
    }
}
if($failures.Count -eq $before){$passed++;Write-Host 'PASS agent instructions delegate commits and tags to scripts/commit.ps1'}

# 3. Suites clean up after themselves: 711 leftover aoc-* folders (1,2 GB) once filled the disk mid-run.
$before=$failures.Count
foreach($suite in @(Get-ChildItem (Join-Path $source 'tests') -Filter '*.tests.ps1')){
    $text=[IO.File]::ReadAllText($suite.FullName)
    if($text -notmatch "GetTempPath\(\)\)\s*\(\s*'aoc-"){continue}
    if($text -notmatch "\.\s*\(Join-Path\s+\`$PSScriptRoot\s+'TestFixtures\.ps1'\)"){$failures.Add("tests/$($suite.Name) creates an aoc-* folder in %TEMP% but does not load tests/TestFixtures.ps1")}
    if($text -notmatch 'Remove-TestFixtures\s'){$failures.Add("tests/$($suite.Name) never calls Remove-TestFixtures, so its aoc-* folder stays in %TEMP%")}
    # Text is not enough: inside a function the helper vanishes when the function returns, and a folder
    # created per call has no single root to remove. Both must sit at the top level of the suite.
    $ast=[Management.Automation.Language.Parser]::ParseInput($text,[ref]$null,[ref]$null)
    $inFunction={param($node) for($p=$node.Parent;$p;$p=$p.Parent){if($p -is [Management.Automation.Language.FunctionDefinitionAst]){return $true}};return $false}
    $loads=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.CommandAst] -and $n.InvocationOperator -eq 'Dot' -and $n.Extent.Text -match 'TestFixtures\.ps1'},$true))
    if(@($loads|Where-Object {& $inFunction $_}).Count -or -not @($loads|Where-Object {-not (& $inFunction $_)}).Count){$failures.Add("tests/$($suite.Name) must load TestFixtures.ps1 at the top level, not inside a function")}
    $command={param($node) for($p=$node.Parent;$p;$p=$p.Parent){if($p -is [Management.Automation.Language.CommandAst]){return $p}};return $null}
    $roots=@($ast.FindAll({param($n) $n -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $n.Member.Extent.Text -eq 'GetTempPath'},$true)|Where-Object {$c=& $command $_;$c -and $c.Extent.Text -match "'aoc-"})
    if(@($roots|Where-Object {& $inFunction $_}).Count){$failures.Add("tests/$($suite.Name) creates its aoc-* folder inside a function; create one root at the top level and put each case in a subfolder")}
}
if($failures.Count -eq $before){$passed++;Write-Host 'PASS every suite that creates fixtures in %TEMP% removes them'}

# 4. The cleanup helper only ever deletes aoc-* folders directly under %TEMP%.
$before=$failures.Count
try{
    . (Join-Path $PSScriptRoot 'TestFixtures.ps1')
    $temp=[IO.Path]::GetTempPath()
    $mine=Join-Path $temp ('aoc-hygiene-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory((Join-Path $mine 'repo/.git'))|Out-Null
    $readOnly=Join-Path $mine 'repo/.git/pack.idx';[IO.File]::WriteAllText($readOnly,'x');(Get-Item $readOnly).IsReadOnly=$true
    $other=Join-Path $temp ('no-borrar-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($other)|Out-Null
    $outside=Join-Path $source ('aoc-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($outside)|Out-Null
    try{
        Remove-TestFixtures $mine;Remove-TestFixtures $other;Remove-TestFixtures $outside;Remove-TestFixtures ''
        if(Test-Path -LiteralPath $mine){$failures.Add('Remove-TestFixtures left an aoc-* folder (with read-only files) in %TEMP%')}
        if(-not (Test-Path -LiteralPath $other)){$failures.Add('Remove-TestFixtures deleted a %TEMP% folder without the aoc- prefix')}
        if(-not (Test-Path -LiteralPath $outside)){$failures.Add('Remove-TestFixtures deleted an aoc-* folder outside %TEMP%')}
    }finally{
        foreach($d in @($other,$outside)){if(Test-Path -LiteralPath $d){Remove-Item -LiteralPath $d -Recurse -Force}}
    }
}catch{$failures.Add("TestFixtures.ps1: $($_.Exception.Message)")}
if($failures.Count -eq $before){$passed++;Write-Host 'PASS the cleanup helper only deletes aoc-* folders directly under %TEMP%'}

# 5. Leftovers of failed runs do not stay forever: aoc-* folders older than 48 h are swept at the start of any suite.
$before=$failures.Count
try{
    . (Join-Path $PSScriptRoot 'TestFixtures.ps1')
    $temp=[IO.Path]::GetTempPath()
    $old=Join-Path $temp ('aoc-hygiene-old-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($old)|Out-Null
    $recent=Join-Path $temp ('aoc-hygiene-new-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($recent)|Out-Null
    $foreign=Join-Path $temp ('ajena-'+[guid]::NewGuid().ToString('N'));[IO.Directory]::CreateDirectory($foreign)|Out-Null
    foreach($d in @($old,$foreign)){$i=Get-Item $d;$i.CreationTime=(Get-Date).AddDays(-3);$i.LastWriteTime=(Get-Date).AddDays(-3)}
    try{
        Clear-StaleTestFixtures
        if(Test-Path -LiteralPath $old){$failures.Add('Clear-StaleTestFixtures kept an aoc-* folder older than 48 h')}
        if(-not (Test-Path -LiteralPath $recent)){$failures.Add('Clear-StaleTestFixtures deleted a recent aoc-* folder (it may belong to a run in progress)')}
        if(-not (Test-Path -LiteralPath $foreign)){$failures.Add('Clear-StaleTestFixtures deleted an old %TEMP% folder without the aoc- prefix')}
    }finally{foreach($d in @($recent,$foreign,$old)){if(Test-Path -LiteralPath $d){Remove-Item -LiteralPath $d -Recurse -Force}}}
    $loader=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'TestFixtures.ps1'))
    if($loader -notmatch '(?m)^Clear-StaleTestFixtures\s*$'){$failures.Add('TestFixtures.ps1 must run Clear-StaleTestFixtures when loaded, so every suite sweeps old leftovers')}
}catch{$failures.Add("Clear-StaleTestFixtures: $($_.Exception.Message)")}
if($failures.Count -eq $before){$passed++;Write-Host 'PASS leftovers older than 48 h are swept automatically; recent and foreign folders are kept'}

# 6. Promoting to stable races GitHub: right after the tests finish, branch protection can still report
#    "Required status check ... is in progress" for a few seconds (3.9.1 and 3.11.0 failed that way).
#    The push must retry on exactly that rejection, a bounded number of times, and fail on anything else.
$before=$failures.Count
$workflow=[IO.File]::ReadAllText((Join-Path $source '.github/workflows/windows-tests.yml'))
$promote=[regex]::Match($workflow,'(?s)- name: Promote only this tested SHA.*$').Value
if($promote -notmatch 'for attempt in [0-9 ]+; do'){$failures.Add('promote: the push to stable must be retried a bounded number of times')}
if($promote -notmatch "grep -q 'is in progress'"){$failures.Add('promote: only the "is in progress" rejection may be retried')}
if($promote -notmatch 'sleep [1-9][0-9]*'){$failures.Add('promote: retries must wait between attempts')}
if($promote -match '(?m)^\s*git push origin "\$GITHUB_SHA:refs/heads/stable"\s*$'){$failures.Add('promote: a single unretried push to stable is still present')}
if($failures.Count -eq $before){$passed++;Write-Host 'PASS promotion to stable retries only while GitHub still reports the tests in progress'}

if($failures.Count){$failures|ForEach-Object {Write-Host "FAIL $_"};Write-Host "Repository hygiene: $passed passed, $($failures.Count) failures.";exit 1}
Write-Host "Repository hygiene: $passed passed."
