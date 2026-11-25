# Changelog

Todos los cambios relevantes de Agent Ops Core se documentan en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el proyecto usa [Versionado Semántico](https://semver.org/lang/es/). Los cambios de cada skill pública se detallan en `docs/changelogs/<skill>.md`. El changelog, `VERSION` y los changelogs de skills viven en `docs/` porque las instalaciones existentes solo aceptan publicaciones dentro de su lista de rutas permitidas.

## [Unreleased]
### Added
- Mientras ya corren las pruebas de un estado, la comprobación al terminar el turno deja terminar (`RUNNING`) en lugar de devolver al agente a ejecutarlas, y le recuerda ofrecer al usuario esperar o adelantar algo que no dependa del resultado (R-015). Cada ejecución marca el proyecto mientras corre (`.context/test-runs/`); una marca solo cuenta si su proceso sigue vivo.
- Permisos nativos para credenciales, sin lanzar ningún proceso. Claude Code: reglas «preguntar» para leer o editar `.env` (no los ejemplos), claves (.pem, .key, .pfx, .p12, id_rsa…), `google-ads.yaml`, `.npmrc`, `.tfstate`/`.tfvars` y similares; conservan las reglas propias del usuario. Codex: un perfil de permisos `agent-ops` que parte de `:workspace` y niega solo las claves privadas (el aislamiento también se lo impide a los programas que Codex ejecuta, por eso no incluye `.env` ni `google-ads.yaml`, que siguen con la protección actual); guarda copia de `config.toml` y no lo toca si ya define su propio aislamiento. `-Uninstall` lo deja exactamente como estaba. Antigravity queda «esperando»: sus permisos de archivos no admiten patrones.

### Fixed
- El canal local daba 5 s a cada llamada a Git de este PC: con el equipo cargado fallaba sin error real. Ahora 60 s (son operaciones locales, sin red).

## [3.18.0] - 2026-11-25
### Added
- Aviso al empezar cada sesión en Claude Code, Codex y Antigravity: en un proyecto que sigue Agent Ops Core, el arnés le dice al agente que haga el MODO ENTRADA antes de tocar nada, y le da un resumen local y sin red (archivos sin guardar, si la sesión anterior se cortó y si hay una actualización verificada pendiente). Nunca copia lo que dejó escrito la sesión anterior. Tras compactar la conversación (Claude Code y Codex) vuelve a darle las reglas activas del proyecto, literales (Protocolo 8). En otras carpetas no dice nada y, si algo falla, la sesión empieza igual. Se instala una vez por usuario con `scripts/install-session-start.ps1` y conserva los demás hooks de inicio. `hook.SessionStart` pasa a «aprovechada» en los tres arneses (3 de 8).
- Antes de compactar la conversación, Claude Code recibe instrucciones para el resumen: conservar literalmente las peticiones y correcciones del usuario, las reglas registradas, el plan con su siguiente paso exacto, qué archivos están sin guardar o sin publicar, las decisiones pendientes y los resultados de pruebas. Solo en proyectos que siguen Agent Ops Core; nunca impide la compactación. `hook.PreCompact` pasa a «aprovechada» en Claude Code (4 de 8). Codex ignora lo que se le diga en ese momento y Antigravity no lo tiene: a ambos se les vuelven a dar las reglas al empezar tras compactar.
- `run-tests.ps1 -Snapshot` ejecuta las pruebas sobre una copia del estado actual (el último commit más los cambios sin guardar), así que se puede seguir editando mientras corren; el resultado se anota para el estado copiado y la copia se borra siempre.
- `run-tests.ps1 -Changed` tras un resultado en verde solo prueba lo que cambió desde ese resultado, en esa misma versión de PowerShell y con el mismo commit, en lugar de todo lo pendiente desde el último commit.
- Canal local verificado (R-014): `publish-local.ps1`, ejecutado desde la versión instalada, prueba el último commit del repositorio del marco en una copia, con todas las suites en Windows PowerShell y PowerShell 7 más la revisión del paquete público, y si todo está en verde lo instala en este PC para todos los proyectos, sin esperar a GitHub. Solo acepta un estado guardado, del mismo repositorio y que descienda de la versión activa. Mientras GitHub va por detrás, la comprobación al empezar la sesión responde `LOCAL_AHEAD` y nunca ofrece la versión anterior; cuando GitHub confirma ese commit pasa a `stable`. `-Revert` vuelve a la última versión confirmada por GitHub.
- `scripts/wait-ci.ps1` espera el resultado de las pruebas de GitHub de un commit sin bloquear al agente (R-013): se lanza en segundo plano y avisa una sola vez, con el resultado y la duración de cada trabajo y si se promovió a `stable` (0 verde, 1 rojo, 2 tiempo agotado, 3 sin red). Solo lee la API pública y nunca repite textos de error, para que un token no pueda aparecer en su salida.
- Cuando una suite falla, `run-tests.ps1` dice qué pruebas fallaron (`Failures`, también por parte), en lugar de solo su última línea.

### Changed
- El lanzador común de hooks se instala desde `HookIO.psm1` (`Install-AgentOpsHookLauncher`), compartido por la protección de credenciales y el aviso de inicio; su contenido no cambia.

### Fixed
- La prueba del vigilante del actualizador daba 6 s a un PowerShell nuevo para arrancar y dar señal de vida: con el equipo cargado no llegaba y la prueba fallaba sin error real. Ahora espera hasta 60 s y termina en cuanto llega la señal.
- La prueba de «sincronización más larga que la espera» del actualizador mantenía el bloqueo un tiempo fijo (13 s): con el equipo cargado se soltaba dentro de la espera y la prueba fallaba sin haber error. Ahora lo mantiene hasta que la prueba lo suelta.

## [3.17.0] - 2026-11-24
### Added
- Las suites lentas se reparten en partes que corren a la vez: con `run-tests.ps1 -Parallel N`, una suite que acepta `-Shard k/n` se ejecuta en N procesos, sus partes arrancan primero y el resultado se junta en uno (rojo si falla cualquier parte). La del actualizador pasó de 390 s a 155 s en un equipo de 8 núcleos.
- `run-tests.ps1` elige por defecto cuántas a la vez según la capacidad real de la máquina, sin tope fijo (R-012): la mitad de los núcleos lógicos y 250 MB libres por parte (`-Parallel 1` las ejecuta de una en una). La tanda completa bajó de unos 10 min a 6,4 min.
- Las pruebas de GitHub corren en 4 trabajos en paralelo por versión de PowerShell (dos mitades del actualizador, integración y gobernanza). Las comprobaciones que exige `stable` conservan su nombre y solo pasan si pasaron todas las partes: un trabajo saltado ya no puede contar como verde.

### Fixed
- En GitHub, el paso que ejecutaba `rules-check` y `user-profile` solo comprobaba el resultado del segundo: un fallo de `rules-check` pasaba sin avisar. Ahora cuenta cada suite, y `repo-hygiene` exige que ninguna suite quede fuera, que cada resultado cuente y que se ejecuten todas las partes.
- La prueba de paralelo de `run-tests` fallaba a veces porque sus suites simuladas escribían a la vez en un mismo archivo y Windows rechazaba una escritura; ahora cada una escribe el suyo.
- Nueva prueba de que las rutas internas nunca salen de su carpeta ni atraviesan un enlace (`Get-SyncChild`).
- Dos entradas del changelog (3.13.1 y 3.11.0) tenían caracteres de control en lugar de las comillas de código.

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
- Las pruebas ya no comparten los bloqueos de sistema con la instalación real del equipo: cada suite usa su propio espacio de nombres (`AGENT_OPS_LOCK_NAMESPACE`, fijado por `tests/TestFixtures.ps1`), así que ni las pruebas fallan ni la instalación responde «ocupado» mientras corren. Los procesos reales conservan exactamente los mismos nombres.
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
- Limpieza obligatoria y automática de las pruebas (R-011): cada suite del marco borra su carpeta temporal al terminar en verde, la conserva si falla y, al empezar, barre las de más de 48 horas (`tests/TestFixtures.ps1`). `repo-hygiene` analiza la estructura de cada suite y exige la limpieza a cualquier suite nueva.
- Protocolo 3 de AGENTS.md: las pruebas de cada proyecto crean sus archivos temporales en una carpeta propia y la borran al terminar en verde; si fallan, la conservan para revisar el fallo y se borra sola después.

## [3.10.0] - 2026-11-24
### Added
- Radar de arneses, segunda fase: vigila también las páginas oficiales de hooks, ajustes y plugins de Claude Code, Codex y Antigravity (huella del texto visible: el ruido de la página no cuenta) y las versiones instaladas en el equipo (`claude`, `codex`, `agy`). Así Antigravity, que no publica versiones en GitHub, queda cubierto. Los cambios de documentación se marcan como vistos con `-Action Ack -Harness <id> -Source <página>`.

### Fixed
- El radar lee siempre las páginas como UTF-8 y sigue las redirecciones permanentes (308): Windows PowerShell 5.1 y PowerShell 7 obtienen la misma huella y ninguna página mudada queda sin leer.
