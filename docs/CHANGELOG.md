# Changelog

Todos los cambios relevantes de Agent Ops Core se documentan en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el proyecto usa [Versionado Semántico](https://semver.org/lang/es/). Los cambios de cada skill pública se detallan en `docs/changelogs/<skill>.md`. El changelog, `VERSION` y los changelogs de skills viven en `docs/` porque las instalaciones existentes solo aceptan publicaciones dentro de su lista de rutas permitidas.

## [Unreleased]

## [3.16.0] - 2026-11-24
### Changed
- La protección de credenciales ya no frena al agente en las acciones normales. Claude Code solo la lanza cuando la ruta o el comando contienen algo sospechoso (un filtro `if` por patrón); el lanzador responde él mismo, sin cargar módulos, a lo que no lo parece; Codex solo la consulta para comandos, parches y herramientas MCP. Reinstalar con `install-secret-guard.ps1` sustituye la configuración anterior sin duplicarla.
- El lanzador de hooks anota cada invocación (hora, hook y arnés; nunca rutas ni contenido) en `%LOCALAPPDATA%\AgentOps\hooks\invocations.log`, limitado a 256 KB.

### Added
- Pruebas mucho más rápidas: `run-tests.ps1 -Changed` ejecuta solo las suites que cubren el código sin guardar (las que cargan cada script o módulo, directa o indirectamente; si cambia algo común, como el flujo de GitHub o un auxiliar de pruebas, todas). Un cambio típico pasó de 10-20 minutos a menos de 1. `-Parallel N` ejecuta N suites a la vez; queda desactivado por defecto. Cada suite comparte la consola del ejecutor, porque algunas lanzan Git o PowerShell y sin consola fallaban.
## [3.15.0] - 2026-11-24
### Added
- Protección de credenciales antes de cada acción del agente: cuando una herramienta va a leer, editar o mostrar un archivo de credenciales (.env, claves .pem/.key, credentials/secrets de datos, google-ads.yaml, .npmrc…), Claude Code y Antigravity preguntan al usuario y Codex, que no permite preguntar, la bloquea y el agente explica qué necesita. Solo cuentan rutas y comandos, nunca el texto que se escribe. Se instala una vez por usuario con scripts/install-secret-guard.ps1 y protege todos los proyectos; un lanzador estable usa siempre la versión activa. hook.PreToolUse pasa a «aprovechada» en los tres arneses.

### Fixed
- La prueba de recuperación tras un cierre brusco da 60 s (antes 20) al proceso simulado: con el equipo cargado fallaba sin que hubiera error.

## [3.14.0] - 2026-11-24
### Added
- Sensor de higiene del proyecto (`scripts/project-hygiene.ps1`, solo lectura): al empezar la sesión avisa de copias de skills del hub dentro del proyecto (idénticas o distintas), archivos provisionales con más de 7 días en `scratch/`, `tmp/` o `.tmp/` y gobernanza sin guardar en el historial. Nunca borra ni cambia nada; la decisión es del usuario en cada proyecto.

## [3.13.1] - 2026-11-24
### Fixed
- Las pruebas ya no comparten los bloqueos de sistema con la instalación real del equipo: cada suite usa su propio espacio de nombres (AGENT_OPS_LOCK_NAMESPACE, fijado por 	ests/TestFixtures.ps1), así que ni las pruebas fallan ni la instalación responde «ocupado» mientras corren. Los procesos reales conservan exactamente los mismos nombres.
- La comprobación al terminar el turno lee y escribe UTF-8 directamente: en Windows PowerShell 5.1 los acentos del aviso salían rotos y una entrada con marca BOM hacía que dejara terminar sin comprobar.

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
