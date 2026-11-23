# Changelog

Todos los cambios relevantes de Agent Ops Core se documentan en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el proyecto usa [Versionado Semántico](https://semver.org/lang/es/). Los cambios de cada skill pública se detallan en `docs/changelogs/<skill>.md`. El changelog, `VERSION` y los changelogs de skills viven en `docs/` porque las instalaciones existentes solo aceptan publicaciones dentro de su lista de rutas permitidas.

## [Unreleased]

## [3.9.0] - 2026-11-23
### Added
- Radar de arneses (primera fase): `scripts/harness-radar.ps1` revisa una vez al día las versiones nuevas de Codex y Claude Code en sus fuentes oficiales y deja un aviso de una línea («Novedad de arnés: … Pide "evalúa …"») que se puede marcar como visto. Una fuente caída nunca bloquea y el texto descargado se trata como datos.
- Tabla de capacidades de los arneses (`scripts/harness-capabilities.json`): qué ofrece cada uno, con enlace a su documentación, fecha de verificación, estado (aprovechada, pendiente, esperando o descartada) y respaldo, para que lo obligatorio no dependa de un solo arnés. Se valida con `harness-radar.ps1 -Action Validate`.
- Detector de arneses (`harness-radar.ps1 -Action Detect`): informa qué arneses usa el proyecto y cuáles están instalados.
- Análisis ampliado (`docs/analisis-harness-engineering.md`): aprovechar todo lo de cada arnés con «piso y techo», y el ciclo del radar.

## [3.8.0] - 2026-11-23
### Added
- Revisión automática al guardar (hook `pre-commit` de Git): cada commit, también los hechos a mano, se frena si falta su línea en el changelog o si añade una contraseña o clave, y el aviso explica cómo arreglarlo. La migración la instala en cada proyecto con Git, con respaldo y reversión; nunca sustituye un hook de otra herramienta. Nuevos `scripts/pre-commit-check.ps1`, `scripts/install-git-hook.ps1`, `PreCommitCheck.psm1` y `SecretScan.psm1`; pruebas en `tests/pre-commit.tests.ps1`.
- Análisis de harness engineering (`docs/analisis-harness-engineering.md`): contraste del marco con OpenAI, Anthropic, LangChain y Endor Labs, tabla de mecanismos comunes a Codex, Antigravity y Claude Code (hooks `SessionStart`, `PreToolUse`, `PostToolUse` y `Stop`) y oportunidades de mejora priorizadas para pasar del cumplimiento por buena fe al automático.

## [3.7.0] - 2026-11-23
### Added
- Lenguaje según la persona (Protocolo 9): el marco pregunta una sola vez a cada usuario a qué se dedica, si le resultan familiares términos como «commit» o «push» y cuánto detalle quiere, y le habla en consecuencia. Por defecto, lenguaje llano con el término técnico entre paréntesis solo cuando le sirve. El perfil se guarda en el equipo, no en el proyecto, y vale para todos sus proyectos.
- `scripts/user-profile.ps1` (`UserProfile.psm1`) consulta y guarda ese perfil; pruebas en `tests/user-profile.tests.ps1`.

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
