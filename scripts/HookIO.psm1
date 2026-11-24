Set-StrictMode -Version 2
# Shared by the harness hook adapters. Harnesses exchange UTF-8 JSON: stdin and stdout are handled as raw
# UTF-8 bytes, never through the console code page (Windows PowerShell would garble accents and break JSON).
$script:utf8=New-Object Text.UTF8Encoding($false)

function Read-AgentOpsHookInput{
    $buffer=New-Object IO.MemoryStream;[Console]::OpenStandardInput().CopyTo($buffer)
    return $script:utf8.GetString($buffer.ToArray()).TrimStart([char]0xFEFF)
}
function Write-AgentOpsHookOutput([string]$Text){
    if(-not $Text){return}
    $bytes=$script:utf8.GetBytes($Text);$out=[Console]::OpenStandardOutput();$out.Write($bytes,0,$bytes.Length);$out.Flush()
}
function Write-AgentOpsHookNote([string]$Text){
    $bytes=$script:utf8.GetBytes($Text+"`n");$err=[Console]::OpenStandardError();$err.Write($bytes,0,$bytes.Length);$err.Flush()
}
# JSON settings files of the harnesses, read as ordered dictionaries so they can be merged and written back.
function ConvertTo-AgentOpsPlain($o){
    if($null -eq $o){return $null}
    if($o -is [Management.Automation.PSCustomObject]){$h=[ordered]@{};foreach($p in $o.PSObject.Properties){$h[$p.Name]=ConvertTo-AgentOpsPlain $p.Value};return $h}
    if($o -is [Collections.IDictionary]){$h=[ordered]@{};foreach($k in $o.Keys){$h[$k]=ConvertTo-AgentOpsPlain $o[$k]};return $h}
    if($o -is [Collections.IEnumerable] -and $o -isnot [string]){return ,@($o|ForEach-Object {ConvertTo-AgentOpsPlain $_})}
    return $o
}
function Read-AgentOpsJsonFile([string]$Path){if([IO.File]::Exists($Path)){ConvertTo-AgentOpsPlain ([IO.File]::ReadAllText($Path)|ConvertFrom-Json)}else{[ordered]@{}}}
function Write-AgentOpsJsonFile([string]$Path,$Value){[IO.Directory]::CreateDirectory((Split-Path $Path))|Out-Null;[IO.File]::WriteAllText($Path,($Value|ConvertTo-Json -Depth 12),$script:utf8)}
Export-ModuleMember -Function Read-AgentOpsHookInput,Write-AgentOpsHookOutput,Write-AgentOpsHookNote,ConvertTo-AgentOpsPlain,Read-AgentOpsJsonFile,Write-AgentOpsJsonFile
