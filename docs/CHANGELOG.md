# Changelog

Todos los cambios relevantes de Agent Ops Core se documentan en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el proyecto usa [Versionado Semántico](https://semver.org/lang/es/). Los cambios de cada skill pública se detallan en `docs/changelogs/<skill>.md`. El changelog, `VERSION` y los changelogs de skills viven en `docs/` porque las instalaciones existentes solo aceptan publicaciones dentro de su lista de rutas permitidas.

## [Unreleased]

## [3.26.0] - 2026-11-28
### Added
- Plantilla de plugin para Claude Code (`templates/claude-plugin/`) y lanzador `scripts/plugin-bootstrap-hook.ps1` para arranque desde el enlace del repositorio con guía de instalación asistida si falta el runtime local.
- Guía de instalación asistida desde el chat en `README.md` (con permiso explícito antes de ejecutar `install.ps1`).
- Oferta automática de inicialización (`ops-project-init`) en `SessionStart.psm1` para carpetas sin gobierno cuando existe instalación activa, con exclusión de rutas del sistema y opt-out por proyecto (`DeferProjectInit` en `Integrations.psm1` / `integrations.ps1` -> `uninitialized-defer.json`).

### Changed
- `SessionStart.psm1`: avisa en lenguaje llano cuando un proyecto gobernado tiene un `AGENTS.md` desactualizado (`ops-project-migrate`) y recuerda explicar `AGENTS_REVIEW_REQUIRED` sin tecnicismos antes de decidir.

## [3.25.0] - 2026-11-27
### Added
- `ops-session-handoff` `2.15.0`: documenta `session-distill.ps1` en `references/aprendizaje.md`.
- Mecanismo de destilación gobernada de sesión (`SessionDistill.psm1`, `session-distill.ps1`): observa correcciones y ciclos fallo→solución durante la sesión mediante semilla silenciosa en `SessionStart.psm1` / `PreCompact` y `templates/AGENTS.md`, permanece en silencio sin señal (`QUIET`), clasifica por destino más ligero y aplica barrera AppSec (`SecretScan` + anonimización de rutas, correos, query params y `.context/private_terms.txt`) en `New-LearningCandidate`.

### Fixed
- `LearningProposals.psm1` (`Invoke-LearningProposalApply`): inserta la nueva versión debajo de `## [Unreleased]` en `changelogs/<skill>.md` (orden Keep a Changelog) y normaliza `CRLF`/`LF` al aplicar bloques `Antes:` → `Después:`.

## [3.24.0] - 2026-11-26
### Added
- Aprendizaje gobernado, fase 3 (`record-usage.ps1`, `prune-skills.ps1`, `check-skill-catalog.ps1` en `LearningProposals.psm1`): telemetría híbrida Piso+Techo en `<hub>/proposals/usage.jsonl` con bloqueo Mutex y consolidación de copias `usage*.jsonl`, extractor en trazas (`Sync-SkillUsageFromTranscripts`), poda con guarda de arranque en frío y detección `hurt`, destinos `6` (`archivar` en `proposals/archived/`) y `7` (`fusionar`), e inspector dual (`Jaccard` + contención) con parser YAML multilínea entre hub y skills núcleo.
- Aprendizaje gobernado, fase 2 (`triage-learnings.ps1`, `apply-proposal.ps1` en `LearningProposals.psm1`): triaje por recurrencia entre proyectos/sesiones, descarte con motivo, aplicación parcial por bloques aprobados, actualización de SemVer y changelog de skill.

### Changed
- `ops-session-handoff` `2.14.0`: documenta en `references/aprendizaje.md` el registro híbrido de uso (`record-usage.ps1`), la poda sin borrado (`prune-skills.ps1`) y el inspector de catálogo (`check-skill-catalog.ps1`).
- Sensores de uso y catálogo: `SessionStart.psm1` (`PostToolUse` `Skill` async en Claude Code), `post-tool-hook.ps1` (registro no bloqueante de uso), `TurnGate.psm1` (vigilancia de `skills/*/SKILL.md` → `repo-hygiene`) y `repo-hygiene.tests.ps1` (validación estructural estricta del catálogo núcleo).

## [3.23.0] - 2026-11-25
### Added
- Sensor inmediato `R-018` en `post-tool-hook.ps1` y `TurnGate.psm1` (`Get-AgentOpsActiveTestRun`): detecta pruebas vivas en `.context/test-runs/` e inyecta aviso para no esperar pasivamente y ofrecer tareas en paralelo con botones (`ops-git-worktrees` si toca código); `templates/AGENTS.md` lo hereda a todos los proyectos.
- Flujo seguro `.env` para pedir credenciales fuera del chat (`EnvRequest.psm1`, `request-env.ps1`): `Prepare` crea/completa `.env.example` y `.env` (solo si `.gitignore` ignora `.env`), y `Check` verifica qué claves tienen valor sin leer ni mostrar secretos.
- Sensor de higiene (`ProjectHygiene.psm1`): avisa cuando se acumulan más de 25 referencias internas de Codex en `refs/codex/turn-diffs/`.
- Detección automática de escritor único (Protocolo 5): `ActivityLog.psm1` (`Get-AgentOpsConcurrentWriters`) y `SessionStart.psm1` avisan al iniciar sesión si otro arnés escribió recientemente en el mismo proyecto (últimos 15 min) sin crear archivos extra en `.context/`.

### Fixed
- `run-tests.ps1 -Changed` (`Get-AgentOpsSuitesForChanges`) ahora incluye automáticamente `repo-hygiene` cuando cambia cualquier `.ps1` o `.psm1` bajo `scripts/`.

## [3.22.0] - 2026-11-25
### Changed
- Privacidad del repositorio público: anonimizados los ejemplos y fixtures de pruebas (`commit.tests.ps1`, `project-migration.tests.ps1`, `antigravity-permissions.tests.ps1`) y añadida comprobación permanente en `repo-hygiene.tests.ps1` para impedir correos personales, rutas locales o nombres de proyectos privados en archivos versionados.

### Added
- Controles OWASP WSTG-CONF-03 de defensa en capas: análisis AppSec en `docs/analisis-owasp-wstg-conf-03.md`; cobertura de `.tfstate`, `.tfvars`, `.kdbx`, `.htpasswd` y respaldos de secretos en `SecretGuard.psm1` y `templates/antigravity-plugin/rules/credenciales.md`; bloqueo de rutas staged sensibles, respaldos y volcados en `PreCommitCheck.psm1` (respetando migraciones SQL legítimas); detección pasiva de copias olvidadas en `ProjectHygiene.psm1`; y nueva auditoría pre-despliegue de solo lectura (`DeployAudit.psm1`, `check-deploy.ps1`).

## [3.21.0] - 2026-11-25
### Changed
- `plugin.hooks` de Codex queda «esperando»: Codex no ofrece orden de terminal para instalar plugins locales (solo desde la app / `/plugins`); se mantienen las entradas sueltas en `~/.codex/hooks.json`.
- `browser.allowlist` de Antigravity queda «descartada»: el navegador ya pregunta por defecto antes de abrir sitios o descargar archivos, y la lista de sitios permitidos la decide cada usuario desde Settings > Browser.

### Added
- Plugin de Agent Ops Core para Claude Code (`ClaudePlugin.psm1`, integrado en `Integrations.psm1`): empaqueta los hooks del marco (`SessionStart`, `PreCompact`, `PostToolUse`, `SubagentStop` y `PreToolUse` de credenciales) en un marketplace local (`agent-ops-core@agent-ops`), lo valida e instala con `claude plugin` y solo entonces retira las entradas sueltas de `~/.claude/settings.json`, conservando `permissions.ask` y los hooks propios del usuario. `plugin.hooks` pasa a «aprovechada» en Claude Code (8 de 8).
- Permisos nativos de Antigravity para carpetas de credenciales (`AntigravityPermissions.psm1`, integrado en `Integrations.psm1` y `session-start-hook.ps1`): tras pedir permiso una sola vez al usuario y guardar copia de respaldo, añade reglas `ask` en `~/.gemini/config/config.json` para las carpetas de credenciales existentes (`.ssh`, `gcloud`, `.aws`, `.azure`, `.kube`, `.docker`, `.git-credentials`, `.netrc`, `.npmrc`), respetando las decisiones previas del usuario y pidiendo reiniciar Antigravity cuando hay cambios. `permissions.deny` pasa a «aprovechada» en Antigravity (6 de 8).

## [3.20.1] - 2026-11-25
### Fixed
- La prueba del resumen de actividad ya no falla en máquinas cuyo reloj avanza a saltos de ~15,6 ms (como las de GitHub): la primera edición queda siempre antes del momento de corte.

## [3.20.0] - 2026-11-25
### Added
- Skill `ops-session-handoff`: el MODO ENTRADA hace como mucho una pregunta de integración (permiso de Codex o arranque desactualizado), con botones y en lenguaje llano; si todo va bien, no dice nada.
- Cero configuración tras cada actualización (`Integrations.psm1`, `integrations.ps1`): al empezar la primera sesión con una versión nueva, y al instalar, el marco ajusta solo sus hooks, el plugin de Antigravity y los permisos de Claude Code en las herramientas que tienes, sin crear nada para las que no. Lo que cambia la configuración propia de una herramienta (hoy, el perfil de permisos de Codex) se pregunta una sola vez y se recuerda (`consents.json`); un «no» no se vuelve a preguntar. Si el arranque del marco está desactualizado, el agente ofrece actualizarlo él (`-Action UpdateBootstrap`, con el hub y los destinos reales y sin tocar la tarea programada). Con una carpeta de estado que no es la real (pruebas), nunca toca la carpeta de usuario real.
- El vigilante de skills ya no puede quedarse apagado sin que se note: al empezar cada sesión, si la instalación lo quiere activo y nadie lo apagó a propósito, se reactiva y se avisa al agente. Nunca durante una activación de versiones ni sobre una tarea de otra instalación. Apagarlo a propósito con `manage-skills-watcher.ps1 -Action Disable` queda registrado (`watcher-intent.json`) y se respeta. En este PC había quedado desactivado del 2026-11-20 al 2026-11-25.
- Plugin de Agent Ops Core para Antigravity (`install-antigravity-plugin.ps1`): reúne en `~/.gemini/config/plugins/agent-ops-core` el aviso al empezar la sesión, la protección de credenciales y el registro de actividad, más dos reglas nativas: una siempre activa con lo esencial del marco (MODO ENTRADA, reglas del proyecto, aceptación y esperas) y otra que se activa sola al tocar archivos de credenciales. Se valida con `agy plugin validate --strict` y solo entonces sustituye a las entradas sueltas de `hooks.json`; los demás instaladores ya no las vuelven a añadir. `plugin.hooks` pasa a «aprovechada» en Antigravity (5 de 8).

### Fixed
- El ajuste automático de integraciones reconoce de verdad la instalación real: antes se creía aislado siempre y no ajustaba nada. Sus mensajes quedan en ASCII para Windows PowerShell 5.1.
- Las pruebas ya no fallan cuando el vigilante de skills real está sincronizando: si la instalación real ya retiene su bloqueo, la prueba lo da por bueno en lugar de esperar 30 s a que lo suelte.

## [3.19.0] - 2026-11-25
### Added
- Petición de permiso en Codex (`PermissionRequest`): cuando Codex va a pedir aprobación (por ejemplo, para salir del aislamiento) y la orden o el parche nombra credenciales, se niega con la misma explicación que antes de cada acción. Así una salida del aislamiento no puede esquivar el perfil que niega leer claves privadas. En cualquier otro caso no decide: sigue tu aprobación normal, y nunca aprueba por ti. `hook.PermissionRequest` pasa a «aprovechada» en Codex (5 de 8).
- El canal local se niega (`BOOTSTRAP_TOO_OLD`) si el arranque que comprueba cada sesión no entiende versiones locales, y explica cómo actualizarlo desde `stable` con `install.ps1`; antes la instalación salía bien pero cada sesión respondía FAILED. El actualizador declara la capacidad con la línea `# capability: local-channel-v1`.
- Al terminar un subagente (Claude Code, `SubagentStop`): si un revisor de aceptación editó el entregable durante la revisión o marcó puntos como cumplidos sin citarlo, se le devuelve a trabajar (R-017); una revisión pendiente no frena a subagentes de otras tareas y nunca entra en bucle. `hook.SubagentStop` pasa a «aprovechada» en Claude Code (7 de 8).
- Registro de actividad «después de cada acción» en Claude Code, Codex y Antigravity: en un proyecto que sigue Agent Ops Core, cada acción que escribe o ejecuta queda anotada fuera del repositorio (herramienta, rutas relativas y, en las órdenes, solo si ejecutó pruebas y su resultado; nunca el texto de la orden ni el contenido). En Claude Code y Codex corre en segundo plano; Antigravity recibe respuesta al momento. Tras una sesión cortada, el aviso de inicio dice qué archivos tocó y cuántas pruebas lanzó desde su último punto de control. `hook.PostToolUse` pasa a «aprovechada» en los tres arneses.
- Revisión de aceptación (R-016, R-017): `acceptance.ps1` fija antes de trabajar la petición literal del usuario, sus criterios y lo que no se toca (promesa, precio, garantía, tono… con patrón comprobable cuando se puede), y antes de entregar prepara una hoja para un revisor en contexto limpio que trae siempre las reglas, las fuentes y el contrato del proyecto. El revisor solo juzga, con una cita, y nunca cambia la oferta; una invariante perdida falla sola; como mucho tres rondas. La comprobación al terminar el turno no deja cerrar con una revisión empezada sin superar.
- Mientras ya corren las pruebas de un estado, la comprobación al terminar el turno deja terminar (`RUNNING`) en lugar de devolver al agente a ejecutarlas, y le recuerda ofrecer al usuario esperar o adelantar algo que no dependa del resultado (R-015). Cada ejecución marca el proyecto mientras corre (`.context/test-runs/`); una marca solo cuenta si su proceso sigue vivo.
- Permisos nativos para credenciales, sin lanzar ningún proceso. Claude Code: reglas «preguntar» para leer o editar `.env` (no los ejemplos), claves (.pem, .key, .pfx, .p12, id_rsa…), `google-ads.yaml`, `.npmrc`, `.tfstate`/`.tfvars` y similares; conservan las reglas propias del usuario. Codex: un perfil de permisos `agent-ops` que parte de `:workspace` y niega solo las claves privadas (el aislamiento también se lo impide a los programas que Codex ejecuta, por eso no incluye `.env` ni `google-ads.yaml`, que siguen con la protección actual); guarda copia de `config.toml` y no lo toca si ya define su propio aislamiento. `-Uninstall` lo deja exactamente como estaba. Antigravity queda «esperando»: sus permisos de archivos no admiten patrones.

### Changed
- El canal local ya no exige guardar los cambios para probar o instalar: lo instalado sale solo del último commit, así que los cambios sin guardar se avisan y se dejan fuera, y se puede seguir trabajando mientras corre la prueba.
- `hook.PreInvocation` de Antigravity queda «esperando»: se dispara antes de cada llamada al modelo y arrancar el hook cuesta ~0,5-1 s (medido), para un beneficio raro.

### Fixed
- Las pruebas del actualizador reintentan la comprobación de sesión cuando su plazo de 5 s para consultar el remoto se agota con el equipo cargado (respondía «sin red» sin fallo real); las que simulan estar sin red siguen terminando así.
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

### Changed
- El canal local ya no exige guardar los cambios para probar o instalar: lo instalado sale solo del último commit, así que los cambios sin guardar se avisan y se dejan fuera, y se puede seguir trabajando mientras corre la prueba.
- `hook.PreInvocation` de Antigravity queda «esperando»: se dispara antes de cada llamada al modelo y arrancar el hook cuesta ~0,5-1 s (medido), para un beneficio raro.

### Fixed
- La prueba del vigilante del actualizador daba 6 s a un PowerShell nuevo para arrancar y dar señal de vida: con el equipo cargado no llegaba y la prueba fallaba sin error real. Ahora espera hasta 60 s y termina en cuanto llega la señal.
- La prueba de «sincronización más larga que la espera» del actualizador mantenía el bloqueo un tiempo fijo (13 s): con el equipo cargado se soltaba dentro de la espera y la prueba fallaba sin haber error. Ahora lo mantiene hasta que la prueba lo suelta.

## [3.17.0] - 2026-11-24
### Added
- Las suites lentas se reparten en partes que corren a la vez: con `run-tests.ps1 -Parallel N`, una suite que acepta `-Shard k/n` se ejecuta en N procesos, sus partes arrancan primero y el resultado se junta en uno (rojo si falla cualquier parte). La del actualizador pasó de 390 s a 155 s en un equipo de 8 núcleos.
- `run-tests.ps1` elige por defecto cuántas a la vez según la capacidad real de la máquina, sin tope fijo (R-012): la mitad de los núcleos lógicos y 250 MB libres por parte (`-Parallel 1` las ejecuta de una en una). La tanda completa bajó de unos 10 min a 6,4 min.
- Las pruebas de GitHub corren en 4 trabajos en paralelo por versión de PowerShell (dos mitades del actualizador, integración y gobernanza). Las comprobaciones que exige `stable` conservan su nombre y solo pasan si pasaron todas las partes: un trabajo saltado ya no puede contar como verde.

### Changed
- El canal local ya no exige guardar los cambios para probar o instalar: lo instalado sale solo del último commit, así que los cambios sin guardar se avisan y se dejan fuera, y se puede seguir trabajando mientras corre la prueba.
- `hook.PreInvocation` de Antigravity queda «esperando»: se dispara antes de cada llamada al modelo y arrancar el hook cuesta ~0,5-1 s (medido), para un beneficio raro.

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

### Changed
- El canal local ya no exige guardar los cambios para probar o instalar: lo instalado sale solo del último commit, así que los cambios sin guardar se avisan y se dejan fuera, y se puede seguir trabajando mientras corre la prueba.
- `hook.PreInvocation` de Antigravity queda «esperando»: se dispara antes de cada llamada al modelo y arrancar el hook cuesta ~0,5-1 s (medido), para un beneficio raro.

### Fixed
- La prueba de recuperación tras un cierre brusco da 60 s (antes 20) al proceso simulado: con el equipo cargado fallaba sin que hubiera error.
