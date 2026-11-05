# Agent Ops Core: Framework Universal de Gobernanza para Agentes de IA

Framework agnóstico, determinista y multiplataforma (Windows, macOS, Linux) para operar equipos de agentes de Inteligencia Artificial (Claude Code, Antigravity/Gemini CLI, OpenAI Codex, ChatGPT Desktop) bajo arquitectura estricta de relevos, desarrollo guiado por pruebas (TDD), depuración sistemática y respaldo continuo en la nube.

---

## 🚀 Instalación Rápida en 1 Línea

Ejecuta el comando correspondiente en tu terminal. En menos de 5 segundos tus arneses de IA (`~/.gemini`, `~/.claude`, `~/.agents`) tendrán instaladas las skills operativas:

### En Windows (PowerShell):
```powershell
irm https://raw.githubusercontent.com/eddvasquez/agent-ops-core/main/install.ps1 | iex
```

### En macOS y Linux (Bash / Zsh):
```bash
curl -fsSL https://raw.githubusercontent.com/eddvasquez/agent-ops-core/main/install.sh | bash
```

---

## 🧠 Filosofía y Neutralidad Multiagente

Este framework se basa en una premisa inquebrantable: **Ningún arnés de IA ni proveedor (Google, Anthropic, OpenAI) debe ser dueño de tu arquitectura de desarrollo.**

```
                               ┌─────────────────────────────────┐
                               │        agent-ops-core           │
                               │      (GitHub Repository)        │
                               └────────────────┬────────────────┘
                                                │
                 ┌──────────────────────────────┼──────────────────────────────┐
                 │ Distribuye en paralelo       │                              │
                 ▼                              ▼                              ▼
      ┌────────────────────┐         ┌────────────────────┐         ┌────────────────────┐
      │  ~/.gemini/skills/ │         │  ~/.claude/skills/ │         │  ~/.agents/skills/ │
      │  (Antigravity /    │         │  (Claude Code /    │         │  (OpenAI Codex /   │
      │   Gemini CLI)      │         │   Claude Desktop)  │         │   Agent Standard)  │
      └──────────┬─────────┘         └──────────┬─────────┘         └──────────┬─────────┘
                 │                              │                              │
                 └──────────────────────────────┼──────────────────────────────┘
                                                │
                                                ▼
                               ┌─────────────────────────────────┐
                               │   Cualquier IA que ejecute un   │
                               │ proyecto lee el MISMO protocolo │
                               │  AGENTS.md y las MISMAS skills  │
                               └─────────────────────────────────┘
```

---

## 🛡️ Arquitectura en 2 Capas (Núcleo Público + Bóveda Privada)

El framework separa formalmente la metodología operativa de tus secretos comerciales:

1. **Capa 1: Núcleo de Gobernanza (`agent-ops-core` en GitHub):**
   - Protocolo universal `AGENTS.md`.
   - Inicializador de proyectos (`ops-crear-proyecto`).
   - Gestión de relevos y handoff (`ops-gestion-relevo`).
   - Migración de proyectos (`ops-migrar-proyecto`).
   - Aislamiento paralelo con worktrees (`ops-git-worktrees`).
   - Metodología TDD (`dev-tdd`) y Depuración Sistemática (`dev-systematic-debugging`).

2. **Capa 2: Bóveda Privada de Negocio (`_ai-skills-hub` en Google Drive):**
   - Habilidades propietarias (copys comerciales, metodologías de venta, credenciales, optimizadores de anuncios).
   - Vive en tu almacenamiento privado y **nunca se publica en repositorios públicos**.
   - Los demonios locales unifican ambas capas en los arneses de IA en tiempo real.

---

## 🔄 Auto-Actualización Periódica (Cada 24 Horas)

No tienes que preocuparte por recordar actualizar el framework:
1. **En cada inicio de sesión:** Al ejecutar `ops-gestion-relevo` (MODO ENTRADA), el agente comprueba si han transcurrido más de 24 horas desde la última verificación. Si hay una nueva versión en GitHub, se actualiza silenciosamente vía `git pull --ff-only`.
2. **Tarea Programada Opcional:** El instalador puede registrar una tarea diaria en segundo plano (Programador de Tareas en Windows, `launchd` en macOS, o `cron` en Linux).

---

## ☁️ Respaldo Automático a Prueba de Desastres

`ops-crear-proyecto` audita automáticamente si la carpeta de destino cuenta con sincronización activa (Google Drive en Windows/Mac o repositorio remoto Git configurado). Si intentas crear un proyecto en una ruta sin respaldo, emite una advertencia preventiva para proteger tu trabajo ante pérdida física o daño del equipo.

---

## 📋 Los 6 Protocolos Universales de AGENTS.md

Todo proyecto creado con este framework cuenta con gobernanza estricta en su archivo raíz `AGENTS.md`:

1. **Protocolo 1 (Inicio de Turno / Auditoría Git):** Prevalece la evidencia física de Git (`git status -s`, `git diff`) sobre cualquier registro en texto. Reporte de 5 puntos obligatorio antes de tocar código.
2. **Protocolo 2 (Cero Suposiciones y Memoria Cruda):** Prohibido adivinar dependencias o requerimientos. Registro obligatorio de correcciones en `.context/lessons_learned.md`.
3. **Protocolo 3 (Invocación Mandatoria y Anti-Racionalización):** Prohibido eludir skills. Toda depuración de bugs exige `dev-systematic-debugging` (Causa Raíz); todo código nuevo exige `dev-tdd` (Red-Green-Refactor).
4. **Protocolo 4 (Destilación a Skill General):** Los aprendizajes maduros se extraen a skills reutilizables.
5. **Protocolo 5 (Escritor Único e Higiene Cloud):** Un solo agente activo a la vez; cero archivos con sufijos de versionado (`_v1`, `_final`); commits atómicos con pausa para liberar bloqueos en nube.
6. **Protocolo 6 (Cierre de Turno / Relevo):** Auditoría objetiva de pruebas en verde antes de marcar hitos en `.context/progress.md` y commit de relevo.
