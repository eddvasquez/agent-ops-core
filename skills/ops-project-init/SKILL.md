---
name: ops-project-init
description: Inicializa un nuevo proyecto con arquitectura de gobernanza universal, .context/, docs/, AGENTS.md, Git local protegido y validación de respaldo en Google Drive o nube.
triggers:
  - "ops-project-init"
  - "ops-crear-proyecto"
  - "init project"
  - "crear nuevo proyecto"
  - "inicializar proyecto"
---

# Skill: Inicializador de Proyecto con Gobernanza Universal (`ops-project-init`)

## FASE 1: CUESTIONARIO BLOQUEANTE
Detente y formula ÚNICAMENTE estas 4 preguntas antes de crear archivos o generar código:
1. **Nombre del proyecto (formato `kebab-case`):**
2. **Objetivo principal y entregable esperado:**
3. **Stack o tecnologías clave (A: Ecosistema/Plataformas | B: Entregable Técnico | C: "Por definir"):**
4. **¿Incluye Analítica Web, GTM o Tráfico Pago? (Sí / No):**

---

## FASE 2: APROVISIONAMIENTO Y AUDITORÍA DE RESPALDO

### 1. Resolución de Rutas Multiplataforma
- **Directorio Raíz de Proyectos (`$WorkspaceRoot`):**
  - Si `$env:WORKSPACE_ROOT` existe, usarla.
  - En Windows: `Join-Path $env:USERPROFILE "Documents\ChatGPT"` (o directorio de trabajo activo).
  - En macOS/Linux: `$HOME/Documents/ChatGPT` (o `$HOME/Projects`).
- **Ruta del Proyecto (`$ProjectPath`):** `Join-Path $WorkspaceRoot "<nombre-del-proyecto>"`
- **Ruta del Núcleo de Gobernanza (`$CorePath`):**
  - Si existe `$HOME\.agent-ops`, tomar plantillas desde `$HOME\.agent-ops\templates\`.
  - Si existe `_ai-skills-hub`, mantener compatibilidad de referencia.

### 2. Auditoría Preventiva de Respaldo Cloud (Google Drive / Nube)
Antes de inicializar, validar la seguridad ante pérdida de hardware:
- **En Windows:** Verificar si `$ProjectPath` reside dentro de la unidad de Google Drive (`G:\`), en `Documents\ChatGPT` sincronizado, o en `%UserProfile%\Google Drive`.
- **En macOS:** Verificar si reside dentro de `~/Library/CloudStorage/GoogleDrive-*` o carpeta sincronizada de iCloud/Drive.
- **En Linux:** Verificar cliente cloud o repositorio remoto Git.
- **Acción ante ruta desprotegida:** Si la ruta elegida es local sin respaldo en la nube, emitir advertencia al usuario recomendando moverla al árbol de Google Drive o vincular un repositorio remoto de GitHub (`gh repo create --private --source=. --push`).

### 3. Cero Duplicidad de Skills Locales
- Crear dentro de `$ProjectPath` ÚNICAMENTE las carpetas `.context/` y `docs/`.
- **ESTRICTAMENTE PROHIBIDO crear una carpeta `skills/` dentro del proyecto.** Las skills son globales y se gestionan a través de los arneses de IA (`~/.gemini`, `~/.claude`, `~/.agents`).

### 4. Git Local Protegido
- Ejecutar `git init` en `$ProjectPath`.
- Aplicar optimizaciones de rendimiento:
  ```bash
  git config core.fscache true
  git config core.preloadindex true
  git config core.longpaths true
  ```
- Crear `.gitignore` excluyendo dependencias masivas y archivos temporales (`.env`, `node_modules/`, `.venv/`, `*.log`, `.DS_Store`, `Thumbs.db`, `desktop.ini`).

### 5. Inyección de `.context/`, `docs/` y `AGENTS.md`
- Inyectar los 5 archivos base de `.context/`:
  - `projectbrief.md`: Con las respuestas de las Preguntas 1, 2 y 3.
  - `systemPatterns.md`: Con los mandatos de TDD (`dev-tdd`) y Depuración Sistemática (`dev-systematic-debugging`). Si la Pregunta 3 fue "Por definir", marcar `[BLOQUEO ACTIVO]`.
  - `activeContext.md`: Con el agente actual y el siguiente paso ejecutable.
  - `progress.md`: Con el hito de inicialización marcado.
  - `lessons_learned.md`: Con la regla de fidelidad a los 6 protocolos.
- Inyectar `docs/README.md` (desde plantilla) para guiar al equipo sobre qué guardar en esa carpeta y permitir a Git versionarla de inmediato.
- Inyectar `AGENTS.md` con los 6 Protocolos Universales. Si la Pregunta 4 fue "Sí", generar `docs/sop_gtm_governance.md`.

### 6. Commit Atómico Inicial
- `git add .` -> esperar 1 segundo (higiene cloud) -> `git commit -m "chore: initialize project with universal agent governance"`.
