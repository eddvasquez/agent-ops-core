# Windows PowerShell 5.1 / PowerShell 7. No external dependencies.
Set-StrictMode -Version 2
$script:CoreSkills = @('dev-systematic-debugging','dev-tdd','ops-git-worktrees','ops-project-init','ops-project-migrate','ops-session-handoff')
$script:Missing = '-'

function ConvertTo-SyncMap($Value) {
    if ($null -eq $Value) { return $null }
    # Pipeline-wrapped JSON strings can also satisfy -is [pscustomobject].
    # Preserve scalar values before inspecting their PowerShell properties.
    if ($Value -is [string] -or $Value.GetType().IsValueType) { return $Value }
    if ($Value -is [Collections.IDictionary]) {
        $map = @{}; foreach ($k in $Value.Keys) { $map[$k] = ConvertTo-SyncMap $Value[$k] }; return $map
    }
    if ($Value -is [pscustomobject]) {
        $map = @{}; foreach ($p in $Value.PSObject.Properties) { $map[$p.Name] = ConvertTo-SyncMap $p.Value }; return $map
    }
    if ($Value -is [array]) { return ,@($Value | ForEach-Object { ConvertTo-SyncMap $_ }) }
    return $Value
}
function Get-SyncHash([string]$Path) {
    $stream = [IO.File]::Open($Path, 'Open', 'Read', 'Read')
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose(); $stream.Dispose() }
}
function Get-SyncId([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text.ToLowerInvariant())))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Assert-SyncNoLink([string]$Path) {
    $current = [IO.Path]::GetFullPath($Path)
    while ($current) {
        try { $attributes=[IO.File]::GetAttributes($current) }
        catch [IO.FileNotFoundException] { $attributes=0 }
        catch [IO.DirectoryNotFoundException] { $attributes=0 }
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "Link/reparse point not allowed: $current" }
        $parent = [IO.Path]::GetDirectoryName($current.TrimEnd('\','/'))
        if ($parent -eq $current) { break }; $current = $parent
    }
}
function Get-SyncRoot([string]$Path) {
    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Empty root path.' }
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\','/')
    if ($full -eq [IO.Path]::GetPathRoot($full).TrimEnd('\','/')) { throw "Drive root not allowed: $full" }
    foreach ($protected in @($env:USERPROFILE, $env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)})) {
        if ($protected -and ($protected -eq $full -or $protected.StartsWith($full + '\', [StringComparison]::OrdinalIgnoreCase))) { throw "Protected root: $full" }
    }
    Assert-SyncNoLink $full
    if ([IO.File]::Exists($full)) { throw "Root is a file: $full" }
    return $full
}
function Get-SyncChild([string]$Root, [string]$Key) {
    if ([string]::IsNullOrWhiteSpace($Key) -or $Key -match '(^|[/\\])\.\.([/\\]|$)' -or $Key -match '[:\x00]' -or [IO.Path]::IsPathRooted($Key)) { throw "Invalid relative path: $Key" }
    $full = [IO.Path]::GetFullPath((Join-Path $Root $Key))
    if (-not $full.StartsWith($Root + '\', [StringComparison]::OrdinalIgnoreCase)) { throw "Path escapes root: $Key" }
    Assert-SyncNoLink $full
    return $full
}
function Test-SyncExcluded([string]$Key) {
    return ($Key -match '(^|/)(\.git|\.migration_archive|__pycache__)(/|$)' -or $Key -match '\.py[co]$' -or $Key -match '(^|/)(desktop\.ini|Thumbs\.db|\.DS_Store)$')
}
function Get-SkillSyncConfiguration {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$HubDir, [Parameter(Mandatory=$true)][string[]]$Targets,
          [Parameter(Mandatory=$true)][string]$StateDir, [string]$FrameworkDir='')
    $HubDir=Get-SyncRoot $HubDir; $StateDir=Get-SyncRoot $StateDir
    $roots=@(@{Id='hub';Path=$HubDir;Role='hub'}); $canonicalTargets=@()
    foreach ($target in $Targets) {
        $canonical=Get-SyncRoot $target; $canonicalTargets+=$canonical
        $roots+=@{Id=(Get-SyncId $canonical);Path=$canonical;Role='replica'}
    }
    if ($FrameworkDir) {
        $FrameworkDir=Get-SyncRoot $FrameworkDir
        $roots+=@{Id='framework';Path=(Get-SyncRoot (Join-Path $FrameworkDir 'skills'));Role='framework'}
    }
    $allPaths=@($roots|Where-Object {$_.Role -ne 'framework'}|ForEach-Object {$_.Path})+@($StateDir)
    if($FrameworkDir){$allPaths+=@($FrameworkDir)}
    for($i=0;$i -lt $allPaths.Count;$i++) {
        for($j=$i+1;$j -lt $allPaths.Count;$j++) {
            if($allPaths[$i] -eq $allPaths[$j] -or $allPaths[$i].StartsWith($allPaths[$j]+'\',[StringComparison]::OrdinalIgnoreCase) -or $allPaths[$j].StartsWith($allPaths[$i]+'\',[StringComparison]::OrdinalIgnoreCase)) {throw 'Roots must be distinct and non-overlapping, including state.'}
        }
    }
    return @{HubDir=$HubDir;Targets=$canonicalTargets;StateDir=$StateDir;FrameworkDir=$FrameworkDir;Roots=$roots}
}
function Save-SkillSyncConfiguration {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param([string]$HubDir,[string[]]$Targets,[string]$StateDir,[string]$FrameworkDir='')
    $c=Get-SkillSyncConfiguration -HubDir $HubDir -Targets $Targets -StateDir $StateDir -FrameworkDir $FrameworkDir
    $path=Get-SyncChild $c.StateDir 'watch-config.json'
    if($PSCmdlet.ShouldProcess($path,'Save validated synchronization configuration')){
        Write-SyncJson $path @{HubDir=$c.HubDir;Targets=$c.Targets;StateDir=$c.StateDir;FrameworkDir=$c.FrameworkDir}
    }
    return $path
}
function Write-SyncJson([string]$Path, $Value) {
    Assert-SyncNoLink $Path
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    $tmp = $Path + '.aoc-' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $bytes=[Text.Encoding]::UTF8.GetBytes(($Value|ConvertTo-Json -Depth 40))
        $stream=[IO.File]::Open($tmp,'CreateNew','Write','None')
        try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        if ([IO.File]::Exists($Path)) {
            # PS 5.1 marshals $null string arguments as empty strings. Use a real
            # sibling backup rather than relying on a null File.Replace argument.
            $previous = $Path + '.previous-' + [guid]::NewGuid().ToString('N')
            for($attempt=0;;$attempt++){
                try{[IO.File]::Replace($tmp,$Path,$previous);break}
                catch [IO.IOException]{
                    $cause=$_.Exception;while($cause.InnerException){$cause=$cause.InnerException}
                    if(($cause.HResult -band 65535) -notin @(32,33) -or $attempt -ge 19){throw}
                    Start-Sleep -Milliseconds 25
                }
            }
            # Replacement has committed. Cleanup failure must not turn that into
            # a false write failure; retain an owned metadata backup if in use.
            try{[IO.File]::Delete($previous)}catch [IO.IOException]{}
        }
        else { [IO.File]::Move($tmp, $Path) }
    } finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
}
function Save-SyncBlob([string]$StateDir, [string]$Source, [string]$Expected) {
    if ($Expected -notmatch '^[a-f0-9]{64}$') { throw 'Invalid blob hash.' }
    Assert-SyncNoLink $Source
    $path = Get-SyncChild $StateDir ('blobs/' + $Expected)
    if ([IO.File]::Exists($path)) {
        if ((Get-SyncHash $path) -ne $Expected) { throw "Corrupt backup blob: $Expected" }
        # Recheck the source even if its blob already exists.
        if ((Get-SyncHash $Source) -ne $Expected) { throw "Source changed during rescue: $Source" }
        return $path
    }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    $tmp = $path + '.aoc-' + [guid]::NewGuid().ToString('N') + '.tmp'
    try {
        $src = [IO.File]::Open($Source, 'Open', 'Read', 'Read')
        try {
            $dest = [IO.File]::Open($tmp, 'CreateNew', 'Write', 'None')
            try { $src.CopyTo($dest); $dest.Flush($true) } finally { $dest.Dispose() }
        } finally { $src.Dispose() }
        if ((Get-SyncHash $tmp) -ne $Expected) { throw "Source changed during rescue: $Source" }
        [IO.File]::Move($tmp, $path)
    } finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
    return $path
}
function Get-SyncInventory($Root, $KnownSkills, $Issues, $SkillNames, $Directories) {
    $files = @{}
    if (-not [IO.Directory]::Exists($Root.Path)) {
        if($Root.Role -eq 'framework'){$Issues.Add("Framework directory missing: $($Root.Path)")}
        return $files
    }
    $skills = @{}
    if ($Root.Role -eq 'framework') {
        foreach ($name in $script:CoreSkills) {
            if ($SkillNames.Count -and $name -notin $SkillNames) { continue }
            if (-not [IO.File]::Exists((Join-Path $Root.Path "$name/SKILL.md"))) { $Issues.Add("Framework skill missing: $name") }
            $skills[$name] = $true
        }
    } else {
        foreach ($name in $KnownSkills) { $skills[$name] = $true }
        foreach ($dir in [IO.Directory]::EnumerateDirectories($Root.Path)) {
            if (([IO.File]::GetAttributes($dir) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $Issues.Add("Unresolved link: $dir -> $((Get-Item -LiteralPath $dir -Force).Target -join ',')"); continue }
            if ([IO.File]::Exists((Join-Path $dir 'SKILL.md'))) { $skills[[IO.Path]::GetFileName($dir)] = $true }
        }
    }
    foreach ($name in $skills.Keys) {
        if ($SkillNames.Count -and $name -notin $SkillNames) { continue }
        $folder = Get-SyncChild $Root.Path $name
        if (-not [IO.Directory]::Exists($folder)) { continue }
        $stack = New-Object 'Collections.Generic.Stack[string]'; $stack.Push($folder)
        while ($stack.Count) {
            $dir = $stack.Pop()
            $Directories.Add(@{Root=$Root.Path;Key=$dir.Substring($Root.Path.Length+1).Replace('\','/');Attributes=[int][IO.File]::GetAttributes($dir)})
            try {
                foreach ($path in [IO.Directory]::EnumerateFileSystemEntries($dir)) {
                    $relative = $path.Substring($Root.Path.Length + 1).Replace('\','/')
                    $attributes = [IO.File]::GetAttributes($path)
                    if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $Issues.Add("Unresolved link: $path -> $((Get-Item -LiteralPath $path -Force).Target -join ',')"); continue }
                    if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) { $stack.Push($path); continue }
                    # Only engine-owned temporary files are omitted from inventory.
                    if ([IO.Path]::GetFileName($path) -match '^\.aoc-[a-f0-9]{32}\.tmp$') { continue }
                    try {
                        $files[$relative] = @{ Key=$relative; RootId=$Root.Id; Path=$path; Hash=(Get-SyncHash $path); Length=([IO.FileInfo]$path).Length; Attributes=[int]$attributes }
                    } catch { $Issues.Add("Unreadable file $path : $($_.Exception.Message)") }
                }
            } catch { $Issues.Add("Unreadable directory $dir : $($_.Exception.Message)") }
        }
    }
    return $files
}
function Set-SyncFile($Action, [string]$StateDir, [string]$RunId, $Backups) {
    $path = Get-SyncChild $Action.Root $Action.Key
    $before = if ([IO.File]::Exists($path)) { Get-SyncHash $path } else { $script:Missing }
    if ($before -ne $Action.Before) { throw "Destination changed since scan: $path" }
    if ($before -ne $script:Missing) { Save-SyncBlob $StateDir $path $before | Out-Null }
    if ($Action.Hash -eq $script:Missing) {
        # Explicit prune only. Atomically capture the actual file on its own
        # volume before removing it; never use recursive deletion.
        if ($before -ne $script:Missing) {
            [IO.File]::Move($path,$Action.BackupPath)
            $actual=Get-SyncHash $Action.BackupPath
            $Backups.Add(@{Key=$Action.Key;Root=$Action.Root;Hash=$actual;Path=$Action.BackupPath})
            Save-SyncBlob $StateDir $Action.BackupPath $actual|Out-Null
            if($actual -ne $before){throw 'Concurrent edit captured during prune; backup retained for review.'}
        }
        return
    }
    $blob = Get-SyncChild $StateDir ('blobs/' + $Action.Hash)
    if ((Get-SyncHash $blob) -ne $Action.Hash) { throw 'Backup integrity check failed.' }
    [IO.Directory]::CreateDirectory((Split-Path -Parent $path)) | Out-Null
    Assert-SyncNoLink $path
    $tmp = Join-Path (Split-Path -Parent $path) ('.aoc-' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $stream = [IO.File]::Open($blob, 'Open', 'Read', 'Read')
        try {
            $out = [IO.File]::Open($tmp, 'CreateNew', 'Write', 'None')
            try { $stream.CopyTo($out); $out.Flush($true) } finally { $out.Dispose() }
        } finally { $stream.Dispose() }
        if ((Get-SyncHash $tmp) -ne $Action.Hash) { throw 'Staged file integrity check failed.' }
        Assert-SyncNoLink $path
        $now = if ([IO.File]::Exists($path)) { Get-SyncHash $path } else { $script:Missing }
        if ($now -ne $before) { throw "Destination changed before replacement: $path" }
        if ($before -eq $script:Missing) { [IO.File]::Move($tmp, $path) }
        else {
            $backup = $Action.BackupPath
            [IO.File]::Replace($tmp, $path, $backup)
            $actual = Get-SyncHash $backup
            $Backups.Add(@{Key=$Action.Key; Root=$Action.Root; Hash=$actual; Path=$backup})
            Save-SyncBlob $StateDir $backup $actual | Out-Null
            if ($actual -ne $before) { throw "Concurrent edit preserved in backup; review required: $backup" }
        }
        if ((Get-SyncHash $path) -ne $Action.Hash) { throw "Post-copy verification failed: $path" }
        if ($Action.ContainsKey('Attributes')) { [IO.File]::SetAttributes($path, [IO.FileAttributes]($Action.Attributes -band 39)) }
    } finally { if ([IO.File]::Exists($tmp)) { [IO.File]::Delete($tmp) } }
}

function Invoke-SkillSync {
    [CmdletBinding(SupportsShouldProcess=$true, ConfirmImpact='Low')]
    param(
        [string]$HubDir = (Join-Path $env:USERPROFILE '.agent-ops-hub'),
        [string[]]$Targets = @((Join-Path $env:USERPROFILE '.gemini/config/skills'), (Join-Path $env:USERPROFILE '.claude/skills'), (Join-Path $env:USERPROFILE '.agents/skills')),
        [string]$StateDir = (Join-Path $env:LOCALAPPDATA 'AgentOps'),
        [string]$FrameworkDir = '',
        [ValidateSet('Plan','Apply','Verify','Resolve','Prune','Restore')][string]$Mode = 'Plan',
        [string]$Key = '', [string]$VersionHash = '',
        [string[]]$SkillNames = @()
    )
    $result = [ordered]@{Code=0; Mode=$Mode; Copied=0; Removed=0; DirectoriesCreated=0; Actions=@(); Conflicts=@(); Deletions=@(); Issues=@(); Backups=@(); RescueManifest=$null; Journal=$null}
    $mutex = $null; $locked = $false; $journal = $null; $journalPath = $null
    try {
        foreach ($name in $SkillNames) { if ($name -match '[/\\:]|^\.{1,2}$' -or [string]::IsNullOrWhiteSpace($name)) { throw 'Invalid skill scope.' } }
        $configuration=Get-SkillSyncConfiguration -HubDir $HubDir -Targets $Targets -StateDir $StateDir -FrameworkDir $FrameworkDir
        $HubDir=$configuration.HubDir; $StateDir=$configuration.StateDir; $roots=$configuration.Roots
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $mutex = New-Object Threading.Mutex($false, ('Local\AgentOpsSkillsSync-' + $identity))
        try { $locked = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked = $true }
        if (-not $locked) { $result.Code=3; return [pscustomobject]$result }
        $statePath = Get-SyncChild $StateDir 'state.json'
        $state = @{SchemaVersion=1; Entries=@{}; Roots=@{}; Reviews=@{Conflicts=@(); Deletions=@()}}
        if ([IO.File]::Exists($statePath)) {
            $state = ConvertTo-SyncMap (ConvertFrom-Json ([IO.File]::ReadAllText($statePath)))
            if ($state.SchemaVersion -ne 1 -or $state.Entries -isnot [hashtable] -or $state.Roots -isnot [hashtable] -or $state.Reviews -isnot [hashtable]) { throw 'Invalid state schema; restore state from a verified backup before writing.' }
            foreach ($entryKey in $state.Entries.Keys) {
                Get-SyncChild $HubDir $entryKey | Out-Null
                $entry = $state.Entries[$entryKey]
                if ($entry -isnot [hashtable] -or $entry.Baselines -isnot [hashtable] -or $entry.Accepted -notmatch '^(-|[a-f0-9]{64})$') { throw "Invalid state entry: $entryKey" }
                foreach($baseline in $entry.Baselines.Values){if($baseline -notmatch '^(-|[a-f0-9]{64})$'){throw "Invalid baseline: $entryKey"}}
            }
        }
        $known = @($state.Entries.Keys | ForEach-Object { ($_ -split '/')[0] } | Sort-Object -Unique)
        $issues = New-Object 'Collections.Generic.List[string]'
        $inventories = @{}; $keys = @{}; $directories=New-Object 'Collections.Generic.List[object]'
        foreach ($root in $roots) {
            $inventories[$root.Id] = Get-SyncInventory $root $known $issues $SkillNames $directories
            foreach ($fileKey in $inventories[$root.Id].Keys) { $keys[$fileKey]=$true }
        }
        foreach ($fileKey in $state.Entries.Keys) { if (-not $SkillNames.Count -or ($fileKey -split '/')[0] -in $SkillNames) { $keys[$fileKey]=$true } }
        $writing = $Mode -notin @('Plan','Verify') -and -not $WhatIfPreference
        $runId = [datetime]::UtcNow.ToString('yyyyMMddTHHmmssfff') + '-' + [guid]::NewGuid().ToString('N')
        if ($writing -and $PSCmdlet.ShouldProcess($HubDir, "$Mode skills (verified backup first)")) {
            $manifest = @{SchemaVersion=1; RunId=$runId; CreatedUtc=[datetime]::UtcNow.ToString('o'); Complete=$false; SkillScope=@($SkillNames); Roots=@($roots); Files=@(); Directories=@($directories.ToArray()); Issues=@()}
            $result.RescueManifest = Get-SyncChild $StateDir ("rescues/$runId.json")
            # Write incomplete status first: interruption can never leave a false complete rescue.
            Write-SyncJson $result.RescueManifest $manifest
            foreach ($root in $roots) {
                foreach ($file in $inventories[$root.Id].Values) {
                    try {
                        Save-SyncBlob $StateDir $file.Path $file.Hash | Out-Null
                        $manifest.Files += @{Root=$root.Path; Role=$root.Role; Key=$file.Key; Hash=$file.Hash; Length=$file.Length; Attributes=$file.Attributes}
                    } catch { $issues.Add($_.Exception.Message) }
                }
            }
            $manifest.Issues=@($issues.ToArray()); $manifest.Complete=($issues.Count -eq 0)
            Write-SyncJson $result.RescueManifest $manifest
        } else { $writing=$false }
        if ($issues.Count) { $result.Code=1; $result.Issues=@($issues.ToArray()); return [pscustomobject]$result }
        if ($Mode -in @('Resolve','Prune','Restore')) {
            if (-not $Key -or -not $keys.ContainsKey($Key)) { throw 'Operation requires an existing managed -Key.' }
            Get-SyncChild $HubDir $Key | Out-Null
            if ($Mode -ne 'Prune' -and $VersionHash -notmatch '^[a-fA-F0-9]{64}$') { throw 'Operation requires -VersionHash (SHA-256).' }
            $VersionHash = $VersionHash.ToLowerInvariant()
        }
        $plans = @(); $conflicts = @(); $deletions = @(); $updates = @{}; $reviewed=@{}
        foreach ($fileKey in @($keys.Keys | Sort-Object)) {
            if (Test-SyncExcluded $fileKey) { continue }
            if ($Mode -in @('Resolve','Prune','Restore') -and $fileKey -ne $Key) { continue }
            $reviewed[$fileKey]=$true
            $entry = if ($state.Entries.ContainsKey($fileKey)) { $state.Entries[$fileKey] } else { $null }
            $observed = @{}; $versions = @{}; $changes = @{}; $missingChange=$false
            foreach ($root in $roots) {
                $hash = if ($inventories[$root.Id].ContainsKey($fileKey)) { $inventories[$root.Id][$fileKey].Hash } else { $script:Missing }
                $observed[$root.Id]=$hash
                if ($hash -ne $script:Missing) { $versions[$hash]=$true }
                if ($entry) {
                    $base = if ($entry.Baselines.ContainsKey($root.Id)) { $entry.Baselines[$root.Id] } else { $script:Missing }
                    if ($base -ne $hash) {
                        if ($hash -eq $script:Missing) { $missingChange=$true }
                        else {
                            $changes[$hash]=$true
                            # Upstream updates must not erase a previously customized core file.
                            if ($root.Role -eq 'framework' -and $base -ne $script:Missing -and $entry.Accepted -ne $base -and $entry.Accepted -ne $hash -and $entry.Accepted -ne $script:Missing) { $changes[$entry.Accepted]=$true }
                        }
                    }
                }
            }
            $candidate = $null; $reason=$null
            if ($Mode -eq 'Prune') {
                if (-not $entry -or -not $missingChange -or @($versions.Keys | Where-Object { $_ -ne $entry.Accepted }).Count) { $reason='UnsafePrune' }
                else { $candidate=$script:Missing }
            } elseif ($Mode -eq 'Resolve') {
                if (-not $versions.ContainsKey($VersionHash)) { throw 'Selected resolution is no longer present; re-plan the conflict.' }
                $candidate=$VersionHash
            } elseif ($Mode -eq 'Restore') {
                $blob = Get-SyncChild $StateDir ('blobs/' + $VersionHash)
                if (-not [IO.File]::Exists($blob) -or (Get-SyncHash $blob) -ne $VersionHash) { throw 'Restore blob missing or corrupt.' }
                # A saved manifest must associate this blob with this key.
                $associated=$false
                $rescueDir=Join-Path $StateDir 'rescues'
                if ([IO.Directory]::Exists($rescueDir)) {
                    foreach ($mf in [IO.Directory]::EnumerateFiles($rescueDir, '*.json')) {
                        $saved=ConvertFrom-Json ([IO.File]::ReadAllText($mf))
                        if (@($saved.Files | Where-Object { $_.Key -eq $fileKey -and $_.Hash -eq $VersionHash }).Count) { $associated=$true; break }
                    }
                }
                if (-not $associated) { throw 'Blob does not belong to the requested key.' }
                $candidate=$VersionHash
            } elseif ($missingChange) {
                $deletions += @{Key=$fileKey; Versions=@($versions.Keys); Observed=$observed}; continue
            } elseif (-not $entry) {
                if ($versions.Count -eq 1) { $candidate=@($versions.Keys)[0] } elseif ($versions.Count -gt 1) { $reason='InitialDivergence' }
            } elseif ($changes.Count -gt 1) { $reason='DivergentEdits' }
            elseif ($changes.Count -eq 1) { $candidate=@($changes.Keys)[0] }
            else { $candidate=$entry.Accepted }
            if ($reason) { $conflicts += @{Key=$fileKey; Reason=$reason; Versions=@($versions.Keys); Observed=$observed}; continue }
            if ($null -eq $candidate) { continue }
            $newBase=@{}
            $attributes=0
            foreach ($root in $roots) {
                if ($inventories[$root.Id].ContainsKey($fileKey) -and $inventories[$root.Id][$fileKey].Hash -eq $candidate) { $attributes=$inventories[$root.Id][$fileKey].Attributes }
            }
            foreach ($root in $roots) {
                if ($root.Role -eq 'framework') { $newBase[$root.Id]=$observed[$root.Id]; continue }
                $newBase[$root.Id]=$candidate
                if ($observed[$root.Id] -ne $candidate) { $plans += @{Key=$fileKey; Root=$root.Path; RootId=$root.Id; Before=$observed[$root.Id]; Hash=$candidate; Attributes=$attributes} }
            }
            $updates[$fileKey]=@{Accepted=$candidate; Baselines=$newBase}
        }
        $result.Actions=@($plans); $result.Conflicts=@($conflicts); $result.Deletions=@($deletions)
        if ($conflicts.Count -or $deletions.Count) { $result.Code=2 }
        if ($Mode -eq 'Verify' -and $plans.Count) { $result.Code=2 }
        if ($writing) {
            foreach($action in $plans){if($action.Before -ne $script:Missing){$action.BackupPath=Join-Path (Split-Path -Parent (Get-SyncChild $action.Root $action.Key)) ('.aoc-'+[guid]::NewGuid().ToString('N')+'.tmp')}}
            $journalPath = Get-SyncChild $StateDir ("journals/$runId.json")
            $journal=@{SchemaVersion=1; RunId=$runId; Status='Pending'; Actions=@($plans); Completed=0; Backups=@(); Error=$null}
            $result.Journal=$journalPath
            Write-SyncJson $journalPath $journal
            $backups=New-Object 'Collections.Generic.List[object]'
            foreach ($action in $plans) {
                Set-SyncFile $action $StateDir $runId $backups
                if ($action.Hash -eq $script:Missing) { $result.Removed++ } else { $result.Copied++ }
                $journal.Completed++; $journal.Backups=@($backups.ToArray()); Write-SyncJson $journalPath $journal
                if($action.ContainsKey('BackupPath') -and [IO.File]::Exists($action.BackupPath)) {
                    Assert-SyncNoLink $action.BackupPath
                    if((Get-SyncHash $action.BackupPath) -ne $action.Before){throw 'Backup changed after replacement; retained for review.'}
                    [IO.File]::Delete($action.BackupPath)
                }
            }
            if($Mode -notin @('Resolve','Prune','Restore')) {
                foreach($directory in $directories) {
                    if(Test-SyncExcluded $directory.Key){continue}
                    foreach($root in @($roots|Where-Object {$_.Role -ne 'framework'})) {
                        $path=Get-SyncChild $root.Path $directory.Key
                        if(-not [IO.Directory]::Exists($path)){[IO.Directory]::CreateDirectory($path)|Out-Null;$result.DirectoriesCreated++}
                    }
                }
            }
            # A source can change after its snapshot. Do not commit a baseline
            # until every participating path still matches the planned version.
            foreach($fileKey in $updates.Keys) {
                foreach($root in $roots) {
                    $path=Get-SyncChild $root.Path $fileKey
                    $actual=if([IO.File]::Exists($path)){Get-SyncHash $path}else{$script:Missing}
                    if($actual -ne $updates[$fileKey].Baselines[$root.Id]){throw "File changed during reconciliation: $path"}
                }
            }
            foreach ($fileKey in $updates.Keys) { $state.Entries[$fileKey]=$updates[$fileKey] }
            foreach ($root in $roots) { $state.Roots[$root.Id]=@{Path=$root.Path; Role=$root.Role} }
            # Retain reviews outside an incremental or manually selected scope.
            $previousConflicts=@($state.Reviews.Conflicts | Where-Object { -not $reviewed.ContainsKey($_.Key) })
            $previousDeletions=@($state.Reviews.Deletions | Where-Object { -not $reviewed.ContainsKey($_.Key) })
            $state.Reviews=@{Conflicts=@($previousConflicts)+@($conflicts); Deletions=@($previousDeletions)+@($deletions)}
            # Keep the preceding state in the run journal for manual recovery.
            if ([IO.File]::Exists($statePath)) { $oldHash=Get-SyncHash $statePath; Save-SyncBlob $StateDir $statePath $oldHash | Out-Null; $journal.PreviousState=$oldHash }
            Write-SyncJson $statePath $state
            $journal.Status='Complete'; Write-SyncJson $journalPath $journal
            $result.Backups=@($backups.ToArray())
        }
    } catch {
        $result.Code=1; $result.Issues += $_.Exception.Message
        if ($journal -and $journalPath) {
            try { $journal.Status='Interrupted'; $journal.Error=$_.Exception.Message; $journal.Backups=@($backups.ToArray()); Write-SyncJson $journalPath $journal } catch { $result.Issues += $_.Exception.Message }
        }
    } finally {
        if ($locked -and $mutex) { $mutex.ReleaseMutex() }; if ($mutex) { $mutex.Dispose() }
    }
    return [pscustomobject]$result
}
function Restore-SkillRescue {
    [CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='Low')]
    param([Parameter(Mandatory=$true)][string]$ManifestPath,
          [Parameter(Mandatory=$true)][string]$SourceRoot,
          [Parameter(Mandatory=$true)][string]$Destination)
    $result=[ordered]@{Code=0;Copied=0;PlannedFiles=0;Report=$null;Issues=@()}
    $mutex=$null;$owned=$false;$report=$null
    try {
        $ManifestPath=[IO.Path]::GetFullPath($ManifestPath);Assert-SyncNoLink $ManifestPath
        $stateDir=Get-SyncRoot (Split-Path -Parent (Split-Path -Parent $ManifestPath))
        if((Split-Path -Parent $ManifestPath) -ne (Join-Path $stateDir 'rescues')){throw 'Select an original manifest inside the state rescues directory.'}
        $saved=ConvertFrom-Json ([IO.File]::ReadAllText($ManifestPath))
        if($saved.SchemaVersion -ne 1 -or -not $saved.Complete){throw 'Manifest is incomplete or unsupported; review its issues before restoring.'}
        $Destination=Get-SyncRoot $Destination
        if(Test-Path -LiteralPath $Destination){throw 'Restore requires a new destination; existing folders are never overwritten.'}
        foreach($root in @($saved.Roots)+@(@{Path=$stateDir})) {
            $rootPath=[IO.Path]::GetFullPath($root.Path).TrimEnd('\','/')
            if($Destination -eq $rootPath -or $Destination.StartsWith($rootPath+'\',[StringComparison]::OrdinalIgnoreCase) -or $rootPath.StartsWith($Destination+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Restore destination overlaps live roots or backup state.'}
        }
        $SourceRoot=[IO.Path]::GetFullPath($SourceRoot).TrimEnd('\','/')
        if(-not @($saved.Roots|Where-Object Path -eq $SourceRoot).Count){throw 'Selected source root is not in this manifest.'}
        $files=@($saved.Files|Where-Object Root -eq $SourceRoot)
        $dirs=@($saved.Directories|Where-Object Root -eq $SourceRoot)
        $result.PlannedFiles=$files.Count
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $mutex=New-Object Threading.Mutex($false,('Local\AgentOpsSkillsSync-'+$identity))
        try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
        if(-not $owned){$result.Code=3;return [pscustomobject]$result}
        foreach($dir in $dirs){Get-SyncChild $Destination $dir.Key|Out-Null}
        foreach($file in $files) {
            Get-SyncChild $Destination $file.Key|Out-Null
            if($file.Hash -notmatch '^[a-f0-9]{64}$'){throw 'Invalid manifest hash.'}
            $blob=Get-SyncChild $stateDir ('blobs/'+$file.Hash)
            if((Get-SyncHash $blob) -ne $file.Hash){throw "Missing/corrupt blob: $($file.Hash)"}
        }
        if($PSCmdlet.ShouldProcess($Destination,'Restore entire rescued tree, including caches')) {
            $result.Report=Get-SyncChild $stateDir ('restores/'+[guid]::NewGuid().ToString('N')+'.json')
            $report=@{Complete=$false;Manifest=$ManifestPath;SourceRoot=$SourceRoot;Destination=$Destination;Copied=0;Error=$null}
            Write-SyncJson $result.Report $report
            [IO.Directory]::CreateDirectory($Destination)|Out-Null
            foreach($dir in $dirs){[IO.Directory]::CreateDirectory((Get-SyncChild $Destination $dir.Key))|Out-Null}
            $backups=New-Object 'Collections.Generic.List[object]'
            foreach($file in $files) {
                $action=@{Root=$Destination;Key=$file.Key;Hash=$file.Hash;Before=$script:Missing;Attributes=$file.Attributes}
                Set-SyncFile $action $stateDir 'restore' $backups
                $result.Copied++;$report.Copied=$result.Copied
            }
            $report.Complete=$true;Write-SyncJson $result.Report $report
        }
    }catch{
        $result.Code=1;$result.Issues+= $_.Exception.Message
        if($report){try{$report.Error=$_.Exception.Message;Write-SyncJson $result.Report $report}catch{$result.Issues+=$_.Exception.Message}}
    }finally{if($owned){$mutex.ReleaseMutex()};if($mutex){$mutex.Dispose()}}
    return [pscustomobject]$result
}
Export-ModuleMember -Function Invoke-SkillSync,Get-SkillSyncConfiguration,Save-SkillSyncConfiguration,Restore-SkillRescue
