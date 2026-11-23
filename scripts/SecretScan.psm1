Set-StrictMode -Version 2
# Credential pattern for the pre-commit review: private keys and well-known token prefixes (GitHub, Google API, sk-).
# UpdateCoordinator.psm1 (stable bootstrap, no new imports) keeps the same literal; a test fails if they drift.
$script:pattern='-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AIza[A-Za-z0-9_-]{30,}|sk-[A-Za-z0-9_-]{24,}'

function Test-AgentOpsSecret {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Text)
    return [bool]($Text -match $script:pattern)
}
Export-ModuleMember -Function Test-AgentOpsSecret
