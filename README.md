# Agent Ops Core ⚡
### El Sistema Operativo de Gobernanza que Evita que tus Agentes de IA Destruyan tu Base de Código.

> **La realidad incómoda:** Los modelos de IA no alucinan código por falta de inteligencia; alucinan por **ausencia total de gobernanza operativa**.
> 
> Sin protocolos físicos, un agente de IA actúa como un becario complaciente: aplica parches a ciegas (*shotgun debugging*), reporta que "todo funciona" sin correr una sola prueba, olvida las decisiones tomadas en el turno anterior y te ata al monopolio de un solo proveedor.
> 
> **Agent Ops Core** es el framework agnóstico y determinista que impone rigor de ingeniería, desarrollo guiado por pruebas (TDD), memoria persistente y handoffs quirúrgicos en **Claude Code**, **Antigravity (Gemini)** y **OpenAI Codex**.

---

## 🚀 Instalación Inmediata en 1 Línea (Cero Fricción)

En menos de 5 segundos, tus arneses de IA (`~/.gemini`, `~/.claude`, `~/.agents`) tendrán instaladas las skills operativas:

### En Windows (PowerShell):
```powershell
irm https://raw.githubusercontent.com/eddvasquez/agent-ops-core/main/install.ps1 | iex
```

### En macOS y Linux (Bash / Zsh):
```bash
curl -fsSL https://raw.githubusercontent.com/eddvasquez/agent-ops-core/main/install.sh | bash
```

---

## 🛑 Los 4 Dolores Operativos que Este Framework Destruye

### 1. El Parche Ciego (*Shotgun Debugging*)
- **El Dolor:** La IA encuentra un error, altera 5 variables al azar, inserta un bloque `try/catch` vacío para silenciar la excepción y asegura que está resuelto, rompiendo tres módulos adyacentes.
- **La Solución (`dev-systematic-debugging`):** Mandato obligatorio de 4 fases: reproducción aislada demostrable, rastreo de estado hacia la causa raíz, formulación de hipótesis única y cambio quirúrgico. Cero conjeturas.

### 2. La Complacencia del "Ya Quedó Listo" (*Fake Progress*)
- **El Dolor:** El agente marca hitos como terminados basándose en su propia autocomplacencia, dejándote código roto que descubres horas después al compilar.
- **La Solución (`dev-tdd` y Protocolo 6):** Prohibido escribir código de producción sin una prueba roja previa. Prohibido marcar un hito en `progress.md` sin evidencia física y objetiva de pruebas ejecutadas en verde.

### 3. La Amnesia de Contexto y el Secuestro de Plataforma (*Vendor Lock-in*)
- **El Dolor:** Abres una nueva sesión o cambias de modelo y la IA arranca desde cero, perdiendo el hilo o contradiciendo directrices previas. Además, tus reglas quedan atrapadas en la interfaz propietaria de una sola empresa.
- **La Solución (Arquitectura en 2 Capas + `activeContext.md`):** Tu proyecto conserva memoria viva mediante archivos Markdown nativos. Si Claude se satura o colapsa, abres Gemini o Codex y continúan la misma línea de trabajo bajo el mismo protocolo `AGENTS.md`.

### 4. La Fragilidad ante Pérdida de Equipo o Colisión en Nube
- **El Dolor:** Trabajas en rutas locales temporales y una falla de disco destruye semanas de desarrollo, o archivos duplicados con sufijos de versión (`_v2`, `_final`) corrompen la sincronización.
- **La Solución (`ops-crear-proyecto` + Protocolo 5):** Auditoría preventiva obligatoria de Google Drive/Cloud, prohibición taxativa de duplicados y commits atómicos con pausas para liberar bloqueos de sincronización.

---

## 📊 Matriz de Impacto: Sin Gobernanza vs. Con Agent Ops Core

| Dimensión Operativa | Sin Gobernanza (El estándar de la industria) | Con Agent Ops Core |
| :--- | :--- | :--- |
| **Control de Errores** | Modificación especulativa hasta que "parezca que compila". | Protocolo de Causa Raíz (`dev-systematic-debugging`) con reproducción aislada obligatoria. |
| **Desarrollo de Funciones** | Generación masiva de código sin pruebas previas. | Ciclo estricto **Red-Green-Refactor** (`dev-tdd`). |
| **Cambio de Turno / Handoff** | *"Ayer estábamos haciendo algo con la API..."* (Amnesia). | Reporte auditado de 5 puntos contrastado físicamente contra `git status -s`. |
| **Independencia de IA** | Atrapado en el ecosistema o chat de un solo proveedor. | Neutral: Las mismas reglas corren idénticas en Claude, Gemini y Codex. |
| **Actualizaciones del Sistema** | Copiar y pegar archivos manualmente entre máquinas. | Auto-actualización silenciosa cada 24 horas vía GitHub. |

---

## 🏛️ Arquitectura de Neutralidad Multiagente

Ningún arnés de IA ni proveedor corporativo es dueño de tu arquitectura:

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

## 🛡️ Separación en 2 Capas (Núcleo Público + Bóveda Privada)

El framework aísla la metodología operativa de tus secretos comerciales:

1. **Capa 1: Núcleo Operativo (`agent-ops-core` en GitHub):**
   - Protocolo universal `AGENTS.md`.
   - Inicializador de proyectos (`ops-crear-proyecto`).
   - Gestión de relevos y handoff (`ops-gestion-relevo`).
   - Migración de proyectos legados (`ops-migrar-proyecto`).
   - Aislamiento paralelo con worktrees (`ops-git-worktrees`).
   - Metodología TDD (`dev-tdd`) y Depuración Sistemática (`dev-systematic-debugging`).

2. **Capa 2: Bóveda Privada de Negocio (`_ai-skills-hub` en Google Drive):**
   - Activos comerciales propietarios (copys de venta, ofertas high-ticket, optimizadores de pauta, credenciales).
   - Vive exclusivamente en tu almacenamiento local respaldado y **nunca se expone en repositorios públicos**.
   - Los servicios de sincronización en segundo plano integran ambas capas en los arneses de IA en tiempo real.

---

## 🔄 Auto-Actualización Periódica (Cada 24 Horas)

1. **En cada Inicio de Sesión (`ops-gestion-relevo` MODO ENTRADA):** El agente verifica el archivo local `~/.agent-ops/.last_update_check`. Si han transcurrido más de 24 horas, ejecuta silenciosamente `git pull --ff-only`.
2. **Tarea Programada en el Sistema:** El instalador registra una tarea silenciosa (Programador de Tareas en Windows, `launchd` en macOS o `cron` en Linux) que se ejecuta a las 9:00 AM para mantener el entorno al día.

---

## 📜 Los 6 Protocolos Universales de AGENTS.md

Todo proyecto creado con este framework cuenta con gobernanza estricta en su archivo raíz `AGENTS.md`:

1. **Protocolo 1 (Inicio de Turno / Auditoría Git):** Prevalece la evidencia física de Git (`git status -s`, `git diff`) sobre cualquier texto. Reporte de 5 puntos obligatorio antes de tocar código.
2. **Protocolo 2 (Cero Suposiciones y Memoria Cruda):** Prohibido adivinar dependencias o requerimientos. Registro obligatorio de correcciones en `.context/lessons_learned.md`.
3. **Protocolo 3 (Invocación Mandatoria y Anti-Racionalización):** Prohibido eludir skills. Toda depuración de bugs exige `dev-systematic-debugging` (Causa Raíz); todo código nuevo exige `dev-tdd` (Red-Green-Refactor).
4. **Protocolo 4 (Destilación a Skill General):** Los aprendizajes maduros se extraen a skills reutilizables.
5. **Protocolo 5 (Escritor Único e Higiene Cloud):** Un solo agente activo a la vez; cero archivos con sufijos de versionado (`_v1`, `_final`); commits atómicos con pausa para liberar bloqueos en nube.
6. **Protocolo 6 (Cierre de Turno / Relevo):** Auditoría objetiva de pruebas en verde antes de marcar hitos en `.context/progress.md` y commit de relevo.
