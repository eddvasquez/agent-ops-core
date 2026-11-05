# update.ps1 - Actualizador de Agent Ops Core (Windows)
[CmdletBinding()]
param(
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$RepoDir = Join-Path $HOME ".agent-ops"
$TimestampFile = Join-Path $RepoDir ".last_update_check"

if (-not (Test-Path $RepoDir)) {
    Write-Host "[!] No se encontro el directorio $RepoDir. Ejecute primero install.ps1." -ForegroundColor Yellow
    exit 0
}

# Verificacion de intervalo de 24 horas a menos que se use -Force
if (-not $Force -and (Test-Path $TimestampFile)) {
    $LastCheck = Get-Item $TimestampFile | Select-Object -ExpandProperty LastWriteTime
    if ((Get-Date) - $LastCheck -lt [TimeSpan]::FromHours(24)) {
        Write-Host "[-] Verificacion omitida: ya se actualizo hace menos de 24h ($LastCheck)." -ForegroundColor Gray
        exit 0
    }
}

Write-Host "[*] Comprobando actualizaciones de Agent Ops Core desde GitHub..." -ForegroundColor Cyan

try {
    Push-Location $RepoDir
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    git pull --ff-only
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP
    Pop-Location

    if ($exitCode -ne 0) {
        throw "git pull finalizo con codigo de error $exitCode"
    }

    # Registrar timestamp de verificacion
    Set-Content -Path $TimestampFile -Value (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") -Encoding UTF8

    $SkillsSource = Join-Path $RepoDir "skills"
    if (-not (Test-Path $SkillsSource)) {
        Write-Host "[-] No hay skills en $SkillsSource." -ForegroundColor Yellow
        exit 0
    }

    $Targets = @(
        (Join-Path $HOME ".gemini\config\skills"),
        (Join-Path $HOME ".claude\skills"),
        (Join-Path $HOME ".agents\skills")
    )

    $Skills = Get-ChildItem -Directory $SkillsSource
    foreach ($target in $Targets) {
        if (-not (Test-Path $target)) {
            New-Item -ItemType Directory -Path $target -Force | Out-Null
        }
        foreach ($skill in $Skills) {
            $dest = Join-Path $target $skill.Name
            robocopy $skill.FullName $dest /MIR /XO /R:1 /W:1 /NJH /NJS /NDL /NC /NS | Out-Null
        }
    }

    Write-Host "[+] Agent Ops Core verificado y sincronizado correctamente." -ForegroundColor Green
}
catch {
    Write-Host "[!] Advertencia: No se pudo conectar a GitHub o falló la actualizacion: $($_.Exception.Message)" -ForegroundColor Yellow
}
