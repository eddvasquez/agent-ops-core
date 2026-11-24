# Shared by the test suites (dot-sourced). Deletes a suite's fixtures folder once the suite has passed.
# Safety: only an aoc-* folder directly under %TEMP% is ever removed; anything else is left untouched.
function Remove-TestFixtures([string]$Path){
    if(-not $Path){return}
    $temp=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')
    $full=[IO.Path]::GetFullPath($Path).TrimEnd('\')
    if((Split-Path -Parent $full) -ne $temp -or (Split-Path -Leaf $full) -notlike 'aoc-*' -or -not [IO.Directory]::Exists($full)){return}
    # Git marks pack files read-only; clear that so the folder can go.
    Get-ChildItem -LiteralPath $full -Recurse -Force -File -ErrorAction SilentlyContinue|ForEach-Object {if($_.IsReadOnly){$_.IsReadOnly=$false}}
    Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction SilentlyContinue
}

# Leftovers kept by failed runs are useful only while the failure is being investigated: after 48 h they go.
# Runs in progress are recent, so they are never touched; nothing without the aoc- prefix is touched either.
function Clear-StaleTestFixtures([int]$OlderThanHours=48){
    $limit=(Get-Date).AddHours(-$OlderThanHours)
    foreach($d in @(Get-ChildItem -LiteralPath ([IO.Path]::GetTempPath()) -Directory -Filter 'aoc-*' -ErrorAction SilentlyContinue)){
        if($d.CreationTime -lt $limit -and $d.LastWriteTime -lt $limit){Remove-TestFixtures $d.FullName}
    }
}
Clear-StaleTestFixtures