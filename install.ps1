# install.ps1 - Instalador Universal de Agent Ops Core (Windows)
[CmdletBinding()]
param(
    [string]$RepoUrl = "https://github.com/eddvasquez/agent-ops-core.git",
    [switch]$SkipTask
)

$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "  Agent Ops Core - Instalador de Gobernanza para IA (Win) " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$TargetDir = Join-Path $HOME ".agent-ops"

# 1. Clonar o Actualizar el Repositorio Central
if (Test-Path (Join-Path $TargetDir ".git")) {
    Write-Host "[*] Repositorio detectado en $TargetDir. Actualizando..." -ForegroundColor Yellow
    Push-Location $TargetDir
    git pull --ff-only
    Pop-Location
} else {
    Write-Host "[*] Clonando Agent Ops Core en $TargetDir..." -ForegroundColor Green
    if (Test-Path $TargetDir) {
        Remove-Item -Path $TargetDir -Recurse -Force
    }
    git clone $RepoUrl $TargetDir
}

# 2. Registrar Timestamp Inicial
$TimestampFile = Join-Path $TargetDir ".last_update_check"
Set-Content -Path $TimestampFile -Value (Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ") -Encoding UTF8

# 3. Detectar Estado de Respaldo en la Nube (Google Drive)
Write-Host "[*] Verificando presencia de Google Drive / Respaldo Cloud..." -ForegroundColor Cyan
$GoogleDriveFound = $false
$DrivePaths = @(
    "G:\",
    (Join-Path $HOME "Google Drive"),
    (Join-Path $HOME "Documents\ChatGPT")
)

foreach ($dp in $DrivePaths) {
    if (Test-Path $dp) {
        $GoogleDriveFound = $true
        Write-Host "  [+] Respaldo detectado en: $dp" -ForegroundColor Green
    }
}

if (-not $GoogleDriveFound) {
    Write-Host "  [!] ATENCION: No se detecto unidad activa de Google Drive en G:\ ni en Documents\ChatGPT." -ForegroundColor Yellow
    Write-Host "      Se recomienda ejecutar proyectos dentro de una carpeta sincronizada para proteccion contra perdida de datos." -ForegroundColor Yellow
}

# 4. Replicar Skills a los Arneses de IA Locales
Write-Host "[*] Desplegando skills a los arneses de IA (~/.gemini, ~/.claude, ~/.agents)..." -ForegroundColor Cyan

$HarnessTargets = @(
    (Join-Path $HOME ".gemini\config\skills"),
    (Join-Path $HOME ".claude\skills"),
    (Join-Path $HOME ".agents\skills")
)

$SkillsSource = Join-Path $TargetDir "skills"
$Skills = Get-ChildItem -Directory $SkillsSource

foreach ($harness in $HarnessTargets) {
    if (-not (Test-Path $harness)) {
        New-Item -ItemType Directory -Path $harness -Force | Out-Null
    }
    foreach ($skill in $Skills) {
        $dest = Join-Path $harness $skill.Name
        robocopy $skill.FullName $dest /MIR /XO /R:1 /W:1 /NJH /NJS /NDL /NC /NS | Out-Null
    }
    Write-Host "  [+] Skills instaladas en: $harness" -ForegroundColor Green
}

# 5. Configurar Tarea Programada de Auto-Actualizacion (Diaria)
if (-not $SkipTask) {
    Write-Host "[*] Registrando tarea programada de actualizacion diaria..." -ForegroundColor Cyan
    $TaskName = "AgentOpsDailyUpdate"
    $UpdateScript = Join-Path $TargetDir "update.ps1"
    
    try {
        $Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-WindowStyle Hidden -ExecutionPolicy Bypass -File `"$UpdateScript`""
        $Trigger = New-ScheduledTaskTrigger -Daily -At 9am
        $Principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive
        $Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
        
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force | Out-Null
        Write-Host "  [+] Tarea programada '$TaskName' creada (ejecucion diaria a las 9:00 AM)." -ForegroundColor Green
    } catch {
        Write-Host "  [-] Nota: No se pudo registrar la tarea programada automatica (se requiere permiso de usuario). El relevo diario mantendra el sistema actualizado igualmente." -ForegroundColor Gray
    }
}

Write-Host "==========================================================" -ForegroundColor Green
Write-Host "  ¡Instalacion completada con exito!                      " -ForegroundColor Green
Write-Host "  Skills operativas disponibles en todos tus arneses de IA." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
