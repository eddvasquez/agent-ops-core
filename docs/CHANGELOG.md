# Changelog

Todos los cambios relevantes de Agent Ops Core se documentan en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el proyecto usa [Versionado Semántico](https://semver.org/lang/es/). Los cambios de cada skill pública se detallan en `docs/changelogs/<skill>.md`. El changelog, `VERSION` y los changelogs de skills viven en `docs/` porque las instalaciones existentes solo aceptan publicaciones dentro de su lista de rutas permitidas.

## [Unreleased]

## [3.13.0] - 2026-11-24
### Added
- Comprobación al terminar el turno (piloto en el repositorio del marco): un hook Stop común a Claude Code, Codex y Antigravity devuelve al agente a trabajar si hay cambios de código sin pruebas en verde de ese mismo estado. La evidencia la registra scripts/run-tests.ps1, no el agente; como mucho dos devoluciones seguidas por sesión. Se instala con scripts/install-turn-gate.ps1 en archivos locales que no se publican. Primera capacidad de la tabla de arneses que pasa a «aprovechada».
- .gitignore excluye la configuración local de los arneses (.claude/settings.local.json, .codex/, .agents/).

## [3.12.0] - 2026-11-24
### Added
- Radar de arneses, tercera fase: `-Action Evaluate` prepara en `docs/radar/` el informe de cada novedad (fuentes oficiales y capacidades relacionadas); `-Action Ack -Report` solo la cierra con un veredicto válido (APROVECHAR, ESPERAR, DESCARTAR o YA CUBIERTO) y lo registra; `-Action Coverage` muestra cuántas capacidades de cada arnés se aprovechan; las novedades sin decisión durante más de 14 días lo dicen en su aviso.

### Fixed
- La promoción a `stable` reintenta (hasta 6 veces, cada 10 s) solo cuando GitHub aún ve las pruebas «en curso» justo después de terminar; esa carrera hizo fallar la 3.9.1 y la 3.11.0. Cualquier otro rechazo falla al instante.

## [3.11.0] - 2026-11-24
### Added
- Limpieza obligatoria y automática de las pruebas (R-011): cada suite del marco borra su carpeta temporal al terminar en verde, la conserva si falla y, al empezar, barre las de más de 48 horas (	ests/TestFixtures.ps1). 
epo-hygiene analiza la estructura de cada suite y exige la limpieza a cualquier suite nueva.
- Protocolo 3 de AGENTS.md: las pruebas de cada proyecto crean sus archivos temporales en una carpeta propia y la borran al terminar en verde; si fallan, la conservan para revisar el fallo y se borra sola después.

## [3.10.0] - 2026-11-24
### Added
- Radar de arneses, segunda fase: vigila también las páginas oficiales de hooks, ajustes y plugins de Claude Code, Codex y Antigravity (huella del texto visible: el ruido de la página no cuenta) y las versiones instaladas en el equipo (`claude`, `codex`, `agy`). Así Antigravity, que no publica versiones en GitHub, queda cubierto. Los cambios de documentación se marcan como vistos con `-Action Ack -Harness <id> -Source <página>`.

### Fixed
- El radar lee siempre las páginas como UTF-8 y sigue las redirecciones permanentes (308): Windows PowerShell 5.1 y PowerShell 7 obtienen la misma huella y ninguna página mudada queda sin leer.

## [3.9.1] - 2026-11-23
### Fixed
- El radar de arneses solo avisa dentro del repositorio de Agent Ops Core, a quien lo mantiene (R-010). En cualquier otro proyecto responde `NOT_MAINTAINER`, sin consultar la red ni mostrar nada.

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
