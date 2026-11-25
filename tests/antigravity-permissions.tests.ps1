# Antigravity permissions: Antigravity keeps its permission lists in ~/.gemini/config/config.json
# (userSettings.globalPermissionGrants: allow, ask, deny). The framework adds "ask" rules for the credential folders
# that exist on the machine, so Antigravity asks before reading them. It never touches the user's own rules, keeps a
# copy before every change and does nothing when Antigravity has no configuration yet. Changes apply when Antigravity
# starts again.
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$source=Split-Path -Parent $PSScriptRoot
Import-Module (Join-Path $source 'scripts/AntigravityPermissions.psm1') -Force
$script:base=Join-Path ([IO.Path]::GetTempPath()) ('aoc-agperm-'+[guid]::NewGuid().ToString('N'))
. (Join-Path $PSScriptRoot 'TestFixtures.ps1')
[IO.Directory]::CreateDirectory($script:base)|Out-Null
$script:passed=0;$script:failed=0
$utf8=New-Object Text.UTF8Encoding($false)
function Assert($c,$m){if(-not $c){throw $m}}
# A user rule with an accented letter (o with acute accent), written as a code so this file stays ASCII.
$script:accented='conexi'+[char]0x00F3+'n'
function Test($n,[scriptblock]$b){try{& $b;$script:passed++;Write-Host "PASS $n"}catch{$script:failed++;Write-Host "FAIL $n : $_"}}
# A fake user folder with some credential folders and an Antigravity configuration holding the user's own rules.
function Profile([string[]]$creds=@('.ssh','AppData/Roaming/gcloud','.npmrc'),[string]$config='default'){
    $h=Join-Path $script:base ('h-'+[guid]::NewGuid().ToString('N').Substring(0,6))
    [IO.Directory]::CreateDirectory((Join-Path $h '.gemini/config'))|Out-Null
    foreach($c in $creds){
        $p=Join-Path $h $c
        if($c -like '.*rc' -or $c -like '*credentials'){[IO.Directory]::CreateDirectory((Split-Path $p))|Out-Null;[IO.File]::WriteAllText($p,'x',$utf8)}
        else{[IO.Directory]::CreateDirectory($p)|Out-Null}
    }
    $json=$(switch($config){
        'default'{'{"plugins":{"canva":{"enabled":true}},"userSettings":{"themeMode":"dark","globalPermissionGrants":{"allow":["read_url(ACCENTED.org)","command(git)","execute_url(localhost)"]},"useAiCredits":true}}'}
        'user-rules'{'{"userSettings":{"globalPermissionGrants":{"allow":["read_file(/Users/me/.npmrc)"],"deny":["read_file(/Users/me/.ssh)"],"ask":["command(rm)"]}}}'}
        'none'{$null}
    })
    if($json){$json=$json.Replace('/Users/me',(Convert-AgentOpsAntigravityPath $h)).Replace('ACCENTED',$script:accented);[IO.File]::WriteAllText((Join-Path $h '.gemini/config/config.json'),$json,$utf8)}
    return @{Home=$h;Config=(Join-Path $h '.gemini/config/config.json');Backups=(Join-Path $h 'backups')}
}
function Grants($p){([IO.File]::ReadAllText($p.Config)|ConvertFrom-Json).userSettings.globalPermissionGrants}
function Install($p){Install-AgentOpsAntigravityPermissions -ConfigPath $p.Config -HomeDir $p.Home -BackupDir $p.Backups}

Test 'paths are written the way Antigravity reads them on Windows' {
    Assert ((Convert-AgentOpsAntigravityPath 'C:\Users\PC\.ssh') -eq '/Users/PC/.ssh') (Convert-AgentOpsAntigravityPath 'C:\Users\PC\.ssh')
    Assert ((Convert-AgentOpsAntigravityPath 'D:\x\y\') -eq '/x/y') 'Trailing separator or drive kept'
}
Test 'only the credential folders that exist get an ask rule; the user rules stay as they were' {
    $p=Profile;$before=Grants $p
    $r=Install $p
    $h=Convert-AgentOpsAntigravityPath $p.Home
    $g=Grants $p
    Assert ($r.Code -eq 0 -and $r.Status -eq 'UPDATED') ($r|ConvertTo-Json -Depth 4)
    $want=@("read_file($h/.ssh)","read_file($h/AppData/Roaming/gcloud)","read_file($h/.npmrc)")
    Assert ((@($g.ask) -join '|') -eq ($want -join '|')) ('Ask rules: '+(@($g.ask) -join '|'))
    Assert ((@($g.allow) -join '|') -eq (@($before.allow) -join '|')) 'User allow rules changed'
    Assert (-not $g.PSObject.Properties['deny']) 'A deny list was created'
    $all=[IO.File]::ReadAllText($p.Config)|ConvertFrom-Json
    Assert ($all.userSettings.themeMode -eq 'dark' -and $all.userSettings.useAiCredits -eq $true -and $all.plugins.canva.enabled -eq $true) 'Other settings changed'
    Assert (@($g.allow) -contains "read_url($script:accented.org)") 'Accented text was not preserved'
}
Test 'a second run changes nothing' {
    $p=Profile;Install $p|Out-Null;$t=[IO.File]::ReadAllText($p.Config)
    $r=Install $p
    Assert ($r.Code -eq 0 -and $r.Status -eq 'UP_TO_DATE' -and -not @($r.Added).Count) ($r|ConvertTo-Json -Depth 4)
    Assert ([IO.File]::ReadAllText($p.Config) -eq $t) 'The file was rewritten'
}
Test 'a folder the user already decided about (allow, ask or deny) is left to the user' {
    $p=Profile -config 'user-rules';$h=Convert-AgentOpsAntigravityPath $p.Home
    $r=Install $p;$g=Grants $p
    Assert ((@($r.Added) -join '|') -eq "read_file($h/AppData/Roaming/gcloud)") ('Added: '+(@($r.Added) -join '|'))
    Assert ((@($g.deny) -join '|') -eq "read_file($h/.ssh)" -and (@($g.allow) -join '|') -eq "read_file($h/.npmrc)") 'User decisions changed'
    Assert ((@($g.ask) -join '|') -eq "command(rm)|read_file($h/AppData/Roaming/gcloud)") ('Ask: '+(@($g.ask) -join '|'))
}
Test 'a copy of the configuration is kept before every change' {
    $p=Profile;$orig=[IO.File]::ReadAllText($p.Config)
    $r=Install $p
    Assert ($r.Backup -and [IO.File]::Exists($r.Backup) -and [IO.File]::ReadAllText($r.Backup) -eq $orig) ('Backup: '+$r.Backup)
    Assert (-not (Install $p).Backup) 'A copy was made with nothing to change'
}
Test 'without an Antigravity configuration nothing is created' {
    $p=Profile -config 'none'
    $r=Install $p
    Assert ($r.Code -eq 0 -and $r.Status -eq 'NO_CONFIG' -and -not [IO.File]::Exists($p.Config)) ($r|ConvertTo-Json -Depth 4)
}
Test 'with no credential folders on the machine nothing changes' {
    $p=Profile -creds @();$t=[IO.File]::ReadAllText($p.Config)
    $r=Install $p
    Assert ($r.Status -eq 'UP_TO_DATE' -and [IO.File]::ReadAllText($p.Config) -eq $t) ($r|ConvertTo-Json -Depth 4)
}
Test 'an unreadable configuration is reported and left untouched' {
    $p=Profile;[IO.File]::WriteAllText($p.Config,'{roto',$utf8)
    $r=Install $p
    Assert ($r.Code -eq 1 -and $r.Status -eq 'FAILED' -and [IO.File]::ReadAllText($p.Config) -eq '{roto') ($r|ConvertTo-Json -Depth 4)
}
Write-Host "Antigravity permissions: $script:passed passed, $script:failed failed. Fixtures: $script:base"
if(-not $script:failed){Remove-TestFixtures $script:base}
if($script:failed){exit 1}
