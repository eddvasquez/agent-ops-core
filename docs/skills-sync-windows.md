# Sincronización segura de skills en Windows

Requiere Git y Windows PowerShell 5.1 o PowerShell 7. El instalador registra las tareas con Windows PowerShell 5.1, disponible en Windows. Las versiones Unix de instalación y actualización conservan su implementación anterior; no ofrecen todavía estas garantías.

## Ubicaciones y privacidad

| Ubicación predeterminada | Contenido |
|---|---|
| `%USERPROFILE%\.agent-ops` | Bootstrap del marco público; las versiones activas se seleccionan por SHA |
| `%USERPROFILE%\.agent-ops-hub` | Skills personales y generales, fuera del checkout |
| `%LOCALAPPDATA%\AgentOps` | Estado, respaldos, manifiestos, configuración y registros |
| `.gemini/config/skills`, `.claude/skills`, `.agents/skills` del usuario | Copias utilizadas por las herramientas |

El catálogo del marco incluye exclusivamente las seis skills generales existentes. Las skills especializadas presentes en un checkout de desarrollo se conservan localmente y quedan excluidas por la lista permitida de `.gitignore`. La sincronización no ejecuta `git add`, `commit` ni `push`, ni importa skills personales al checkout público.

Los respaldos son locales: no equivalen a un respaldo en la nube ni protegen por sí solos frente a una falla del disco. No se eliminan automáticamente. Conviene vigilar el espacio ocupado en `AgentOps` y respaldarlo externamente.

## Primera revisión e instalación

Desde la raíz de este repositorio:

```powershell
# Inspeccionar sin modificar skills, estado ni respaldos.
.\scripts\sync-skills.ps1 -Mode Plan -Json
.\scripts\sync-skills.ps1 -Mode Apply -WhatIf -Json

# Aplicar con rescate íntegro previo.
.\scripts\sync-skills.ps1 -Mode Apply -Json
```

`install.ps1` instala desde `stable`, registra el vigilante al iniciar sesión y una comprobación diaria a las 09:00, hora local de Windows. Las actualizaciones se ofrecen al iniciar MODO ENTRADA; la tarea diaria no las activa. Consulta [Actualizaciones verificadas](session-updates-windows.md) para decisiones, versiones aisladas y recuperación. `-SkipTask` omite ambas tareas; `-DisableWatcher` conserva la consulta diaria y desactiva el vigilante. `-RepoUrl`, `-TargetDir`, `-HubDir`, `-Targets`, `-StateDir` y `-RuntimeDir` permiten personalizar la instalación. Los destinos, el runtime y el estado deben estar fuera del checkout, ser distintos y no estar anidados.

Una instalación con el motor nuevo requiere que ese código exista en la rama que se clona. Una carpeta existente sin Git nunca se elimina para instalar. Las ediciones rastreadas o preparadas en Git detienen la actualización automática. No se hace stash ni reset.

Para migrar una instalación antigua, vuelve a ejecutar el instalador actualizado. Si existía un vigilante anterior arrancado mediante `WatchSkillsHub.vbs`, retira ese acceso de Inicio y cierra su instancia antes de activar el nuevo. El instalador no termina procesos ajenos por coincidencias en su línea de comandos. Los archivos locales originales se conservan: verifica los manifiestos antes de cualquier limpieza manual.

## Qué se conserva y cómo se compara

Cada carpeta con `SKILL.md` es una skill. Se recorre su contenido, incluidos archivos ocultos, scripts, documentación, binarios, adjuntos y cachés. El rescate guarda archivos por SHA-256, sin transformar sus bytes, y un manifiesto con rutas relativas, atributos, directorios vacíos y origen. Esto permite deduplicar respaldos idénticos.

La distribución omite solamente `.git`, `.migration_archive`, `__pycache__`, `.pyc`, `.pyo`, `desktop.ini`, `Thumbs.db` y `.DS_Store`. El rescate íntegro sí los conserva. `scripts/`, `README.md`, `.gitignore`, `.ps1`, `.bat`, `.cmd` y `.exe` dentro de una skill no se excluyen de la distribución por su nombre o extensión. Ningún script rescatado se ejecuta.

Los enlaces y junctions no se recorren automáticamente. Se informa su ubicación y destino y el rescate queda incompleto. Errores de lectura o hashes incoherentes también impiden declarar éxito. La garantía cubre los archivos inventariados y su estructura; no es una imagen del sistema de archivos ni conserva ACL, streams alternativos NTFS o una instantánea simultánea de programas que siguen escribiendo.

La última versión sincronizada permite distinguir cambios unilaterales de conflictos. Dos ediciones distintas no se resuelven mediante fecha u orden de fuentes. Las actualizaciones del marco tampoco sobrescriben automáticamente una personalización anterior de un archivo general. Las raíces son tratadas como ubicaciones de confianza del usuario, no como una frontera de seguridad frente a otro proceso hostil con sus mismos permisos.

## Operaciones manuales

Para adaptar proyectos existentes, usar [Migración de proyectos](project-migration-windows.md). `-ImportSources` añade orígenes temporales que nunca se modifican ni se guardan como réplicas. `-Mode Rescue` guarda un manifiesto completo y los blobs sin propagar cambios ni aceptar nuevas versiones. Ambos reutilizan las validaciones del motor.

`-Mode Plan -Json` devuelve acciones, conflictos y borrados pendientes. `-Mode Verify` verifica sin escribir y devuelve `2` si hay diferencias pendientes. `-Key` siempre es una ruta relativa, por ejemplo `mi-skill/scripts/calcular.py`. Los hashes disponibles se encuentran en `Conflicts[].Versions`, los manifiestos y los registros.

```powershell
# Sustituye el hash por una versión presente en el conflicto actual.
.\scripts\sync-skills.ps1 -Mode Resolve -Key 'mi-skill/SKILL.md' -VersionHash 'HASH_SHA256'

# Restaurar un archivo desde una versión respaldada para esa misma ruta.
.\scripts\sync-skills.ps1 -Mode Restore -Key 'mi-skill/SKILL.md' -VersionHash 'HASH_SHA256'

# Propagar un borrado revisado. Se rechaza si otra copia tiene una edición pendiente.
.\scripts\sync-skills.ps1 -Mode Prune -Key 'mi-skill/archivo.txt'
```

`Resolve`, `Restore` y `Prune` actúan únicamente sobre la ruta elegida. `Prune` elimina un archivo administrado después de respaldarlo; nunca borra árboles recursivamente. Un borrado normal permanece pendiente, sin recrear silenciosamente la copia ausente ni borrar las restantes.

Para recuperar un árbol íntegro, incluidas sus cachés y carpetas vacías, elige un manifiesto completo y una de las raíces que contiene:

```powershell
.\scripts\restore-skill-rescue.ps1 `
  -ManifestPath 'C:\ruta\AgentOps\rescues\MANIFIESTO.json' `
  -SourceRoot 'C:\ruta\hub-original' `
  -Destination 'C:\ruta\recuperacion-nueva' -WhatIf
```

Repite sin `-WhatIf` para recuperar. El destino debe ser nuevo y estar fuera de las ubicaciones activas y del estado. Se verifican todos los blobs antes de escribir; los archivos existentes nunca se sobrescriben. Los manifiestos incrementales indican `SkillScope`: abarcan las skills afectadas, no necesariamente todas las skills instaladas.

## Cambiar el hub de una instalación existente

El hub figura en dos archivos: `watch-config.json` (sincronización) y `update-state.json` (coordinador de actualizaciones). Si solo cambia uno, el vigilante se detiene con `Synchronization configuration changed; review before updating.` Usa siempre el comando dedicado; no edites esos archivos a mano ni reinstales para cambiar el hub:

```powershell
# Usar la versión activa (ActivePath que devuelve start-session.ps1 -Action Check).
$ActivePath = (& "$env:USERPROFILE\.agent-ops\scripts\start-session.ps1" -Action Check | ConvertFrom-Json).ActivePath
# Evaluar sin escribir: valida rutas y ejecuta un plan de sincronización contra el nuevo hub.
& "$ActivePath\scripts\set-hub.ps1" -HubDir 'C:\ruta\al\hub-canonico' -WhatIf
# Aplicar: respalda ambos archivos en <StateDir>\hub-switch\, los actualiza juntos y reinicia el vigilante.
& "$ActivePath\scripts\set-hub.ps1" -HubDir 'C:\ruta\al\hub-canonico'
```

El hub debe existir y no solaparse con perfiles, estado ni runtime. Si el plan detecta conflictos entre el nuevo hub y los perfiles, devuelve `REVIEW_REQUIRED` (código 2) sin escribir; resuélvelos y repite. Una activación pendiente devuelve `ACTIVATION_REVIEW_REQUIRED`. Un cambio interrumpido entre ambos archivos se completa al repetir el comando con el mismo hub. El hub anterior no se borra. Retira cualquier otro sincronizador (por ejemplo, un espejo `robocopy` heredado) antes del cambio: dos escritores sobre los mismos perfiles no son compatibles.

## Vigilante, fallos y recuperación

```powershell
.\scripts\manage-skills-watcher.ps1 -Action Status
.\scripts\manage-skills-watcher.ps1 -Action Disable
.\scripts\manage-skills-watcher.ps1 -Action Enable
.\scripts\manage-skills-watcher.ps1 -Action Remove
```

Usa los mismos parámetros de ubicación de tu instalación si son personalizados. `Remove` retira únicamente la tarea del vigilante y conserva los datos. La tarea diaria `AgentOpsDailyUpdate` es independiente.

El vigilante hace una reconciliación inicial y cada cinco minutos. Agrupa eventos durante 1,5 segundos, con espera máxima de cinco segundos antes de solicitar trabajo; el tiempo de copia depende del volumen. Los eventos limitan la revisión a las skills afectadas, cuyo rescate siempre incluye su contenido completo. Un desbordamiento de eventos fuerza una revisión completa. Los eventos de sus propias escrituras pueden provocar una comprobación adicional sin copias; no se propagan indefinidamente.

Los fallos transitorios se reintentan con esperas de 1, 2 y 4 segundos; luego se registran y se vuelve a comprobar en la revisión periódica. `watcher.jsonl` contiene resultados y errores sin contenido de los archivos. Un mutex por usuario serializa las operaciones; otro evita vigilantes duplicados.

| Código | Significado |
|---|---|
| 0 | Operación terminada; sin pendientes en el alcance revisado |
| 1 | Error o rescate incompleto |
| 2 | Conflictos, borrados o diferencias que requieren revisión |
| 3 | Otra operación o vigilante está ejecutándose |

Los journals guardan las acciones previstas antes de modificar archivos. Cada reemplazo captura la versión real anterior mediante una operación atómica en el mismo volumen. Los blobs se verifican antes de retirar el respaldo temporal. Si una operación se interrumpe, la siguiente ejecución vuelve a comparar archivos y estado; no reproduce a ciegas las acciones antiguas. El estado se confirma solo después de verificar los archivos resultantes. No existe una transacción atómica que abarque todas las carpetas.

Conserva los journals `Interrupted` y cualquier archivo reservado `.aoc-<identificador>.tmp` que aparezca indicado como `BackupPath`: puede contener una versión capturada durante la interrupción. No los elimines hasta verificar su respaldo. Un estado o blob corrupto detiene la operación; el journal puede incluir `PreviousState`, el hash de la versión anterior del estado conservada en `blobs`. No borres el estado para forzar una sincronización ni selecciones versiones por su fecha.

## Pruebas

No requieren Pester, paquetes externos, red ni acceso a las configuraciones reales. La integración de tareas usa una simulación del programador de Windows; la instalación y actualización usan repositorios Git temporales.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/skills-sync.tests.ps1 -IncludeLinkTest
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tests/windows-integration.tests.ps1
pwsh -NoProfile -File tests/skills-sync.tests.ps1 -IncludeLinkTest
pwsh -NoProfile -File tests/windows-integration.tests.ps1
```

Ejecuta las suites secuencialmente: comparten deliberadamente el bloqueo por usuario. `-IncludeLinkTest` necesita permiso para crear un junction temporal. Un sandbox que restrinja junctions o los recursos de Git puede impedir esas pruebas; ejecútalas en un entorno Windows de pruebas con esos permisos. Las carpetas temporales se conservan para inspección. El workflow de Windows ejecuta ambas suites en los dos intérpretes.
