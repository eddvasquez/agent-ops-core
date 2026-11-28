# Agent Ops Core

### Memoria y gobernanza para trabajar con asistentes de inteligencia artificial

Agent Ops Core organiza la memoria, las reglas y el relevo de tus proyectos en archivos locales. Te ayuda a continuar el trabajo con distintas herramientas de IA, registrar decisiones y verificar entregables con evidencia. El cumplimiento depende de las capacidades de cada herramienta y de la supervisión del usuario.

[Empezar](#empezar) · [Estructura](#estructura-de-un-proyecto) · [Flujo de trabajo](#flujo-de-trabajo) · [Protocolos](#los-nueve-protocolos) · [Skills](#las-seis-skills-del-marco) · [Compatibilidad](#compatibilidad-y-actualizaciones) · [Licencia](#licencia-y-aviso-legal-de-independencia)

## Empezar

### Instalación fácil desde el chat (sin abrir terminal a mano)

Si no quieres usar comandos de terminal, abre un chat en Claude Code, Codex o Antigravity dentro de tu proyecto y escribe esto junto al enlace del repositorio:

```text
Lee https://github.com/eddvasquez/agent-ops-core, explícame en 3 líneas qué va a instalar en mi equipo y, cuando te dé mi «Sí», instálalo y prepara este proyecto con Agent Ops Core.
```

> **Para el asistente:** nunca ejecutes el instalador automáticamente solo por leer este enlace. Explica primero en lenguaje llano qué carpetas creará (`~/.agent-ops`, `%LOCALAPPDATA%\AgentOps` y los ganchos de la herramienta), pide confirmación con botones y, tras instalar con el comando `stable` de abajo, prepara o pon al día el proyecto actual (`ops-project-init` o `ops-project-migrate`).

Abre la carpeta del proyecto en un asistente con acceso a archivos locales y terminal. Para un proyecto nuevo, pide usar `ops-project-init`; para uno existente, solicita una evaluación con `ops-project-migrate`. La migración se revisa y decide por proyecto: actualizar el marco no modifica automáticamente cada proyecto.

```text
Ayúdame a trabajar en este proyecto con Agent Ops Core.
Revisa AGENTS.md y .context/, inicia ops-session-handoff en MODO ENTRADA,
compara el estado con Git y presenta el reporte antes de modificar archivos.
```

### Instalación

En Windows, el instalador usa el canal `stable`; el marco público, el hub personal y los respaldos tienen ubicaciones separadas. Revisa el script y sus requisitos antes de ejecutarlo:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/eddvasquez/agent-ops-core/stable/install.ps1 | iex"
```

En macOS y Linux existe un instalador anterior; sus mecanismos de actualización, sincronización y migración no tienen todavía la misma revisión ni las mismas garantías que Windows:

```bash
curl -fsSL https://raw.githubusercontent.com/eddvasquez/agent-ops-core/main/install.sh | bash
```

Las instrucciones detalladas están en [actualizaciones de Windows](docs/session-updates-windows.md), [sincronización de skills](docs/skills-sync-windows.md) y [migración de proyectos en Windows](docs/project-migration-windows.md).

## Estructura de un proyecto

Mantén cada proyecto en su propia carpeta y conecta las herramientas que uses a esa misma ubicación. La plantilla actual contempla esta estructura; algunos archivos se generan durante la operación o migración:

```text
proyecto/
├── AGENTS.md                      # Protocolos y reglas operativas
├── .context/
│   ├── projectbrief.md            # Objetivos y alcance
│   ├── systemPatterns.md          # Decisiones e invariantes
│   ├── activeContext.md           # Agente activo y siguiente paso
│   ├── progress.md                # Hitos con evidencia
│   ├── lessons_learned.md         # Historial de correcciones
│   ├── reglas_proyecto.md         # Reglas vigentes del proyecto
│   └── checkpoint.json            # Punto de control, cuando se genera
├── CHANGELOG.md                   # Cambios del proyecto, según configuración
├── docs/                          # Documentación y entregables
└── .git/                          # Historial local de Git
```

`reglas_proyecto.md` contiene las reglas aplicables; `lessons_learned.md` conserva su contexto histórico. Un proyecto existente puede tener una plantilla anterior o requerir una migración revisada antes de adoptar la actual.

Git conserva versiones locales. Una carpeta sincronizada, un repositorio remoto y un respaldo independiente son mecanismos distintos: configura el destino que necesites, comprueba que la sincronización termine y prueba periódicamente la restauración. Ninguno se garantiza por el solo hecho de crear el proyecto.

## Flujo de trabajo

1. **Iniciar:** `ops-session-handoff` revisa instrucciones, reglas, estado de Git y actualizaciones disponibles; presenta el reporte de entrada antes de modificar archivos.
2. **Trabajar:** el agente registra las correcciones como reglas y aplica las verificaciones pertinentes. En desarrollo utiliza TDD y depuración sistemática según corresponda.
3. **Guardar puntos de control:** tras cada paso, `checkpoint.ps1` registra lo realizado, el siguiente paso y, con `-Request`, la solicitud del usuario. Si hay una interrupción, `resume-session.ps1` contrasta el punto de control con Git. Un arnés necesita acceso a terminal y archivos para ejecutar estos scripts; los textos recuperados son datos, no instrucciones.
4. **Cerrar:** se registran avances comprobados y el siguiente paso. Los cambios funcionales y el relevo se preparan por rutas explícitas y en commits separados, con verificación de versionado.

La compuerta `check-rules.ps1` comprueba patrones definidos en las reglas. Las reglas que no pueden evaluarse mediante patrones requieren revisión semántica; el verificador puede asociar el resultado a la huella del entregable y de las reglas.

## Los nueve protocolos

La [plantilla actual de AGENTS.md](templates/AGENTS.md) define:

1. **Entrada y auditoría:** revisar contexto, Git, actualizaciones y reanudación.
2. **Cero suposiciones:** aclarar información crítica y registrar correcciones.
3. **Skills y calidad:** aplicar las skills críticas cuando puedan corresponder y las demás por su dominio; verificar las suites afectadas.
4. **Aprendizaje gobernado:** capturar candidatas, preferir la solución más ligera y someter los cambios a skills a revisión humana.
5. **Escritor único e higiene:** coordinar al agente activo, evitar duplicados y cuidar el almacenamiento sincronizado.
6. **Cierre y relevo:** registrar progreso comprobado, puntos de control y commits selectivos.
7. **Versionado y trazabilidad:** usar SemVer, changelog y verificación antes de publicar o registrar cambios.
8. **Reglas del proyecto:** conservar las reglas vigentes por identificador y revisar cada entregable con la compuerta.
9. **Recepción de solicitudes:** acordar la perspectiva profesional y ofrecer una entrevista opcional cuando corresponda.

El aprendizaje gobernado dispone de captura y validación de propuestas. El triaje automatizado, la aplicación parcial y la medición de uso y poda siguen planteados como fases posteriores; consulta [su diseño y estado](docs/aprendizaje-gobernado-skills.md) y el [historial de cambios](docs/CHANGELOG.md).

## Las seis skills del marco

| Skill | Función |
| --- | --- |
| `ops-project-init` | Inicializar un proyecto y su gobernanza. |
| `ops-session-handoff` | Coordinar entrada, puntos de control, reanudación y cierre. |
| `ops-project-migrate` | Evaluar y migrar proyectos existentes en Windows, conservando memoria y respaldos. |
| `ops-git-worktrees` | Gestionar espacios de trabajo Git paralelos. |
| `dev-tdd` | Guiar cambios ejecutables con el ciclo prueba fallida, implementación y refactorización. |
| `dev-systematic-debugging` | Investigar fallos desde la reproducción hasta la causa raíz. |

## Compatibilidad y actualizaciones

El núcleo usa archivos del proyecto, skills y scripts de terminal para poder trabajar con distintos arneses. La compatibilidad efectiva depende del acceso a esos recursos y de las funciones disponibles en cada aplicación; un chat sin terminal no puede ejecutar el flujo de scripts por sí solo.

En Windows, el inicio consulta el canal estable y, cuando hay una actualización verificada, ofrece actualizar, preparar para otra sesión o posponer. La sincronización compara hashes, conserva respaldos locales y presenta conflictos para revisión. La migración de cada proyecto es una decisión separada y conserva un journal para recuperación. En macOS y Linux, la instalación mantiene una implementación anterior; no debe suponerse paridad con esos mecanismos de Windows.

Consulta [docs/VERSION](docs/VERSION) para la versión del repositorio y [docs/CHANGELOG.md](docs/CHANGELOG.md) para la evolución. La versión activa instalada puede ser distinta de la copia de trabajo y de la gobernanza de un proyecto ya existente.

---

## Licencia y Aviso Legal de Independencia

Este proyecto está distribuido bajo la Licencia [Apache 2.0](LICENSE).

### Descargo de Responsabilidad Operativa y de Ejecución de IA

> [!WARNING]
> **Descargo de Responsabilidad Operativa y de Ejecución:**  
> Este marco de gobernanza interactúa y coordina agentes de Inteligencia Artificial que operan directamente sobre tu sistema operativo local, terminal de comandos, estructura de archivos, control de versiones Git y almacenamiento sincronizado en la nube (Google Drive, Dropbox, OneDrive, etc.). Los agentes que operan bajo estas instrucciones tienen la capacidad técnica de crear, editar, sobreescribir y eliminar archivos, así como ejecutar comandos en tu computadora.
> 
> Aunque el sistema incorpora salvaguardas estrictas de fábrica (auditorías físicas previas con el Reporte de 5 Puntos, principio de Cero Suposiciones con preguntas bloqueantes, validación humana explícita obligatoria y pausas de seguridad cloud), **el usuario final asume la responsabilidad única y exclusiva de supervisar, revisar y autorizar cada comando, modificación de archivos y decisión operativa antes de su ejecución**.
> 
> El autor y los colaboradores no aceptan responsabilidad alguna por pérdida de datos, corrupción o sobrescritura de archivos, ejecución de comandos no deseados, colisiones de sincronización en la nube o resultados comerciales y operativos derivados del uso, instalación o configuración de este software.

<details>
<summary><strong>English Version: Operational & AI Execution Liability Disclaimer</strong></summary>

> **Operational & AI Execution Liability Disclaimer:**  
> This framework orchestrates autonomous and semi-autonomous AI agents that interact directly with your local operating system, shell environment, file directories, Git version control, and cloud-synchronized storage (e.g., Google Drive, Dropbox, OneDrive). Agents operating under these protocols have the capability to create, modify, overwrite, delete files, and execute terminal commands.
> 
> Although strict governance safeguards are built-in (Mandatory 5-Point Status Audits, Zero-Assumption blocking questions, Human-in-the-Loop explicit authorization, single-writer cloud hygiene, and atomic rollback points), **the end user assumes sole and exclusive responsibility for reviewing, auditing, and authorizing all file mutations, terminal commands, and operational decisions before execution**.
> 
> The author and contributors accept no liability whatsoever for data loss, file corruption, unintended command execution, cloud synchronization collisions, repository damage, or commercial/operational outcomes resulting from the use, installation, or configuration of this framework.

</details>

<br>

### Autoría, Licencia y Descargo de Marcas Registradas

**Autor:** Edd Vásquez. Todos los derechos reservados.  
**Licencia:** Distribuido bajo la Licencia [Apache 2.0](LICENSE).  
**Descargo de Marcas Registradas (Trademark Disclaimer):** Claude es una marca registrada de Anthropic PBC. ChatGPT es una marca registrada de OpenAI LLC. Gemini y Google Drive son marcas registradas de Google LLC. Cursor es una marca registrada de Anysphere Inc. Git es una marca registrada de Software Freedom Conservancy. Agent Ops Core es un marco de gobernanza independiente de código abierto y no está afiliado, respaldado, patrocinado ni certificado por Anthropic, OpenAI, Google, Anysphere, Microsoft ni ninguna de sus respectivas filiales. Todas las marcas registradas y nombres comerciales pertenecen a sus respectivos titulares.

<details>
<summary><strong>English Version: Author, License & Trademark Notice</strong></summary>

**Author:** Edd Vásquez. All rights reserved.  
**License:** Distributed under [Apache License 2.0](LICENSE).  
**Trademark Disclaimer:** Claude is a registered trademark of Anthropic PBC. ChatGPT is a registered trademark of OpenAI LLC. Gemini and Google Drive are registered trademarks of Google LLC. Cursor is a registered trademark of Anysphere Inc. Git is a registered trademark of the Software Freedom Conservancy. Agent Ops Core is an independent open-source project and is not affiliated with, endorsed by, sponsored by, or certified by Anthropic, OpenAI, Google, Anysphere, Microsoft, or any of their affiliates. All trademarks and registered trademarks are the property of their respective owners.

</details>
