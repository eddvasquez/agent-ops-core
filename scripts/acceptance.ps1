# Acceptance review (R-016, R-017), JSON for the assistant.
#   -Action New    -Request <file with the literal request> -Criteria <a,b> [-Invariants <"text | regex",...>] [-Sources <paths>]
#   -Action Review -Id <id> -Deliverable <paths>   (writes the sheet for a clean-context reviewer: judge only, never rewrite)
#   -Action Verify -Id <id>                        (0 accepted; 1 failed or delivered with gaps; 2 pending, invalid or stale)
[CmdletBinding()]
param([Parameter(Mandatory=$true)][ValidateSet('New','Review','Verify')][string]$Action,
      [string]$ProjectPath=(Get-Location).Path,[string]$Id='',[string]$Request='',
      [string[]]$Criteria=@(),[string[]]$Invariants=@(),[string[]]$Sources=@(),[string[]]$Deliverable=@())
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'Acceptance.psm1') -Force
# Through `powershell -File`, a list arrives as one string: accept "a,b" as well as an array (not for -Criteria, which may contain commas).
$Deliverable=@($Deliverable|ForEach-Object {$_ -split ','}|ForEach-Object {$_.Trim()}|Where-Object {$_})
$Sources=@($Sources|ForEach-Object {$_ -split ','}|ForEach-Object {$_.Trim()}|Where-Object {$_})
switch($Action){
    'New'{
        if(-not $Request -or -not [IO.File]::Exists($Request)){throw 'Pass -Request <file> with the literal request (a file keeps quotes and accents intact).'}
        $r=New-AgentOpsAcceptance -ProjectPath $ProjectPath -Request ([IO.File]::ReadAllText($Request,[Text.Encoding]::UTF8).Trim()) -Criteria $Criteria -Invariants $Invariants -Sources $Sources
    }
    'Review'{$r=New-AgentOpsAcceptanceReview -ProjectPath $ProjectPath -Id $Id -Deliverable $Deliverable}
    'Verify'{$r=Test-AgentOpsAcceptance -ProjectPath $ProjectPath -Id $Id}
}
$r|ConvertTo-Json -Depth 5
exit $r.Code
