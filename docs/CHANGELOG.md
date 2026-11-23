# Changelog

Todos los cambios relevantes de Agent Ops Core se documentan en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el proyecto usa [Versionado Semántico](https://semver.org/lang/es/). Los cambios de cada skill pública se detallan en `docs/changelogs/<skill>.md`. El changelog, `VERSION` y los changelogs de skills viven en `docs/` porque las instalaciones existentes solo aceptan publicaciones dentro de su lista de rutas permitidas.

## [Unreleased]

## [3.6.0] - 2026-11-23
### Added
- Las reglas se citan con el texto literal de su línea `Regla:` (Protocolo 8): al confirmar una regla nueva, en reportes, relevos y commits, y en las enmiendas como antes → después. Quien trabaja en varios proyectos entiende a qué se refiere «R-008» sin abrir el archivo.
- `check-rules.ps1` devuelve `Warnings` con las reglas cuya línea `Regla:` supera 40 palabras. Es un aviso: no bloquea la compuerta.

## [3.5.1] - 2026-11-21

### Changed
- Actualiza la guía de entrada para reflejar los nueve protocolos, la recuperación de sesiones y el alcance real del marco 3.5.0.

### Fixed
- Evita crear un changelog raíz que oculte el historial existente en `docs/CHANGELOG.md` al migrar un proyecto.

## [3.5.0] - 2026-11-20
### Added
- **Reanudación desde cualquier arnés con terminal.** `checkpoint.ps1 -Request` guarda la petición literal del usuario (las 5 últimas) y `resume-session.ps1` la devuelve como `UserRequests`, así que retomar ya no depende de leer la conversación del arnés anterior.
- Lectura de conversaciones de **Antigravity/Gemini** en `resume-session.ps1` y `harvest-instructions.ps1`. Una conversación cuenta para el proyecto que más menciona entre sus carpetas hermanas; las dudosas se descartan. ChatGPT figura como no compatible y se explica el motivo: sus conversaciones solo están en el servidor.

### Fixed
- La lectura de conversaciones ya no falla con la sesión en curso del arnés, que sigue escribiendo en su archivo.
- `resume-session.ps1` solo lee las conversaciones modificadas desde el inicio de la sesión: en este equipo pasa de unos 20 s a menos de 2 s.

## [3.4.0] - 2026-11-20
### Added
- **Relevo resistente a cortes de sesión.** `checkpoint.ps1` guarda tras cada paso lo hecho y el siguiente paso exacto en `.context/checkpoint.json`, sin hacer commit. Si la sesión se agota por cuota o contexto, `resume-session.ps1` permite a otra herramienta retomar en ese punto: lo coteja con Git, señala el trabajo posterior al último punto y adjunta las últimas peticiones del usuario de Claude Code y Codex como datos. Protocolos 1 y 6 de la plantilla: reanudación en frío, punto de control por paso y MODO SALIDA MÍNIMO cuando la cuota visible baja de ~10 %.

### Fixed
- `harvest-instructions.ps1 -Since` fallaba siempre (`FAILED`) en lugar de filtrar por fecha.

## [3.3.0] - 2026-11-20
### Changed
- **Protocolo 3 en dos niveles.** Las skills críticas (`dev-tdd`, `dev-systematic-debugging` y las que declare cada proyecto en `reglas_proyecto.md`) vuelven al criterio del 1 %, sin excepciones salvo exención expresa del usuario. `dev-tdd` cubre cualquier cambio en algo que se ejecuta, también en código existente. Antes de cada commit, las suites afectadas deben estar en verde, con evidencia en `activeContext.md`. El resto de skills mantiene el criterio de dominio.

## [3.2.0] - 2026-11-20
### Changed
- **Protocolo 9 con varias perspectivas:** si el usuario citó varios profesionales, el agente aplica sin preguntar los que encajan con cada solicitud (hasta 4) y nombra los excluidos. Responde con una síntesis que señala dónde discrepan. La sugerencia inicial admite selección múltiple, y los cambios del panel rigen para el resto de la sesión.

## [3.1.0] - 2026-11-20
### Added
- **Protocolo 9, Recepción de Solicitudes:** ante una solicitud sustancial, el agente responde desde un profesional de clase mundial (el que el usuario ya citó, o uno que sugiere entre 2 y 3 opciones, con «sin perspectiva» siempre disponible) y ofrece una entrevista opcional con preguntas una a una, de opción múltiple y con respuesta libre. La elección vale toda la sesión; «siempre» o «nunca» se guarda como regla del proyecto.

## [3.0.0] - 2026-11-20
### Added
- **Aprendizaje gobernado, fase 1.** `capture-learning.ps1` guarda candidatas en la bandeja del hub (`proposals/inbox/`) sin tocar ninguna skill y rechaza las skills de terceros. `check-proposal.ps1` valida cada ficha antes de presentarla: destino, bloques aprobables por separado, SemVer creciente, tamaño, solapamientos, prueba antes y después con riesgo medio o alto, descripción de 300 caracteres como máximo y, para skills nuevas, las cuatro condiciones del umbral y el techo de 25 skills. `learning-queue.ps1` informa de lo pendiente.
- Protocolo 4 pasa a **Aprendizaje Gobernado de Skills**: capturar en el momento, llevar cada aprendizaje al destino más ligero, umbral de cuatro condiciones y techo de 25 skills para crear, y aplicar solo los bloques que el usuario aprueba. Protocolo 6 añade la captura y la presentación de fichas al cierre.
- Documento de diseño `docs/aprendizaje-gobernado-skills.md`: investigación comparada (Hermes, Devin, Letta, Cursor, SkillsBench, ACE) y propuesta de arquitectura para el aprendizaje gobernado de skills, con aprobación humana por bloques y controles contra la acumulación. Solo diseño; no cambia ningún comportamiento.

### Changed
- **BREAKING:** Protocolo 3: una skill es obligatoria cuando la tarea entra en el dominio que declara su descripción, ya no con «≥ 1 % de probabilidad». `dev-tdd` y `dev-systematic-debugging` siguen siendo obligatorias en su dominio.

## [2.1.0] - 2026-11-19
### Added
- Compuerta de reglas con **revisión semántica verificable**: `check-rules.ps1 -ReviewOut` genera la lista de reglas sin patrón para que la revise un contexto limpio, y `-ReviewVerdictPath` bloquea la entrega si alguna queda `PENDIENTE` o `FALLA`, o si el entregable o las reglas cambiaron después de revisarlos (`Huella`).
- Campo `- Ejemplo:` en las reglas: guarda el texto que se rechazó y el verificador comprueba que `Detectar` lo detecta, para que ninguna regla deje de dispararse.
- Protocolo 8: todo entregable se guarda como archivo antes de entregarlo, para que pase por la compuerta.
- `scripts/harvest-instructions.ps1`: extrae en solo lectura las indicaciones que el usuario dio en conversaciones de Claude Code y Codex y en las memorias de Claude Code, y las devuelve como reglas candidatas con su procedencia. Descarta texto inyectado (avisos del arnés, resultados de herramientas, contenido pegado, sesiones de subagentes) y las reglas ya registradas; nunca escribe en el proyecto.
- La evaluación de migración informa `HarnessInstructions`: líneas propias de `CLAUDE.md`, `GEMINI.md`, `.cursorrules`, `.windsurfrules` y `.github/copilot-instructions.md`, para que ninguna instrucción de otro arnés se pierda al sembrar reglas. Esos archivos no se modifican.

### Fixed
- El bloqueo del vigilante de skills es ahora uno por instalación (usuario + `StateDir`): otra instalación, como la de las pruebas, ya no choca con el vigilante en ejecución.
- La activación de una actualización espera hasta 10 s a que termine una sincronización en curso (el vigilante hace una completa cada 5 minutos) en lugar de fallar al instante. La migración hace lo mismo antes de responder `BUSY`.
- Si la sincronización en curso dura más que esa espera, la activación responde `BUSY` (código 3, reintentable) y conserva la candidata preparada y la aprobación del usuario, en lugar de marcarla como fallida y revocar la aprobación.

## [2.0.0] - 2026-11-19
### Added
- `AGENTS.md` con **bloque gestionado** (`<!-- agent-ops:begin version=… hash=… -->` … `<!-- agent-ops:end -->`): las actualizaciones del marco reemplazan solo el bloque y conservan byte a byte el texto del proyecto que está fuera.
- **Compuerta de conservación**: ninguna línea propia del `AGENTS.md` original puede faltar en el candidato salvo que figure en `-ApprovedRemovalsPath`; si falta, `AGENTS_RULES_MISSING` con `MissingLines` y sin escribir nada.
- `AgentsProposal`: la migración propone el `AGENTS.md` nuevo con cada línea propia del original bajo `## Reglas particulares del proyecto`. Un archivo antiguo hecho solo con texto de plantillas oficiales (`templates/agents-legacy-lines.txt`) se convierte sin revisión.
- Registro `.context/agent-ops.json` con la versión del marco que sigue cada proyecto; `Plan` informa `UpToDate` y `Deferred`.
- Reversión `-Mode Rollback -Journal <id>`, que restaura el estado exacto previo o no toca nada si hubo ediciones posteriores, y punto de restauración Git `refs/agent-ops/pre-migration/<id>`.
- `-Mode Defer` («no para esta versión»), recordado en el estado privado y nunca en el proyecto.
- MODO ENTRADA, Paso 0b: ofrece migrar el proyecto cuando no está al día, con resumen y garantía de reversión.

### Changed
- **BREAKING:** el candidato de `AGENTS.md` debe contener el bloque gestionado vigente sin modificar (partir de `AgentsProposal`); los candidatos con el formato anterior se rechazan sin escribir.
