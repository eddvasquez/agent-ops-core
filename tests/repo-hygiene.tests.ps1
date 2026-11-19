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

if($failures.Count){$failures|ForEach-Object {Write-Host "FAIL $_"};Write-Host "Repository hygiene: $passed passed, $($failures.Count) failures.";exit 1}
Write-Host "Repository hygiene: $passed passed."
