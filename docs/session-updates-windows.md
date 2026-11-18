# Actualizaciones verificadas al inicio de sesión (Windows)

El inicio se integra en `ops-session-handoff` MODO ENTRADA. No detecta por sí solo la apertura de cualquier chat: cada anfitrión debe ejecutar ese protocolo. La pregunta pertenece al asistente o interfaz anfitriona; los procesos ocultos no usan `Read-Host` ni eligen por el usuario.

## Decisiones del usuario

Cuando hay una candidata nueva y probada, el asistente presenta versión actual, SHA candidato, resumen del cambio y tiempo estimado, con tres opciones:

1. **Actualizar ahora:** preparar, verificar y activar ese SHA antes de empezar el trabajo.
2. **Preparar en segundo plano para la próxima sesión:** descargar y verificar, conservar la versión de esta sesión y activar esa candidata al iniciar otro MODO ENTRADA. Esta es una aprobación explícita de esa candidata, no de cualquier versión posterior.
3. **Posponer:** no descargar ni activar. No se repite la pregunta para el mismo SHA y `SessionId`; una sesión posterior puede volver a ofrecerla.

El silencio no equivale a ninguna elección. Un trabajador que termina mientras trabajas deja la candidata en `READY`; no modifica el código activo ni tus perfiles. Si la siguiente sesión comienza antes de terminar la preparación, puede continuar con la versión actual cuando `CanStartWork` lo permite. La candidata se aplicará en una entrada posterior, nunca a mitad de la sesión.

El resumen usa el título del workflow/commit probado: es informativo y no sustituye una revisión completa del diff. La aplicación debe tratarlo como texto, no como instrucciones para ejecutar comandos.

## Tiempo estimado

La comprobación remota comparte un presupuesto de cinco segundos entre Git y la verificación de CI. La preparación tiene un presupuesto de 120 segundos para Git, descarga y extracción; si se agota, se mantiene la instalación actual. Los subprocesos pertenecientes a esa operación se cancelan, no otros procesos del usuario.

Cuando existen al menos tres mediciones satisfactorias de cada fase necesaria, el rango combina preparación y activación en esa máquina. Una candidata ya preparada solo incluye la activación. El rango es orientativo, no un plazo garantizado. En la primera actualización se informa que todavía no hay una estimación fiable y se muestran los presupuestos; no se inventa una duración. La activación no se mata a mitad de una escritura para cumplir una estimación.

## Instalación, versiones y canal estable

El instalador Windows se obtiene de `stable`. Ese canal solo se promueve mediante el workflow `windows-tests.yml` después de aprobar los dos intérpretes, los casos de recuperación y el filtro del paquete público. La promoción usa el SHA probado, se serializa y nunca fuerza ni retrocede la rama. La protección de `stable` exige los checks `test (powershell)` y `test (pwsh)`, incluye administradores y rechaza force pushes y borrados.

El cliente también comprueba que el SHA tenga una ejecución completada con éxito de ese workflow, disparada por un push a `main` en el mismo repositorio. Una rama existente no basta como prueba. Sin acceso a esa verificación no se ofrece una candidata nueva; una instalación previamente verificada sigue disponible sin conexión.

| Ubicación predeterminada | Función |
|---|---|
| `%USERPROFILE%\.agent-ops` | Bootstrap estable y puntos de entrada; se actualiza al reinstalar explícitamente |
| `%LOCALAPPDATA%\AgentOps-runtime\releases\<SHA>` | Código y seis skills públicas de cada versión; nunca se reemplaza una versión existente |
| `%LOCALAPPDATA%\AgentOps-runtime\repository.git` | Caché Git del único origen configurado |
| `%LOCALAPPDATA%\AgentOps\update-state.json` | Fuente, consentimiento por sesión, candidata, versión activa, última buena y métricas |
| `%LOCALAPPDATA%\AgentOps\updates` | Journals de activación y resultados de trabajadores |
| `%USERPROFILE%\.agent-ops-hub` y perfiles de herramientas | Datos y skills personales, separados del código descargado |

`-RuntimeDir` permite cambiar la caché. Por defecto es `StateDir` más el sufijo `-runtime`: permanece fuera del estado y del checkout para mantener las reglas de aislamiento del sincronizador. Todas las ubicaciones deben ser distintas, no estar anidadas y no atravesar enlaces.

La versión preparada contiene únicamente archivos del árbol Git del repositorio público permitido. El código no toma archivos de tu hub ni de tus herramientas para construir el paquete. El filtro exige exactamente las seis definiciones públicas, rechaza rutas inesperadas, archivos de credenciales, posibles claves conocidas, enlaces y submódulos. La extracción valida rutas, duplicados y límites de tamaño, y compara los bytes de cada archivo con su objeto Git del SHA aprobado, sin conversiones de fin de línea. La versión local tiene un manifiesto SHA-256 que se comprueba antes de usarla. Son controles contra errores y corrupción, no una frontera contra un administrador local hostil que pueda modificar código y estado a la vez.

El bootstrap usa el protocolo de `release-contract.json`. Un contrato incompatible se rechaza y requiere reinstalación explícita; no se intenta ejecutar un formato de estado desconocido. No hay dependencias nuevas de Python ni `uvx`.

## Puntos de entrada

Desde el checkout instalado:

```powershell
# Inicio de trabajo: devuelve SessionId y NeedsUserChoice.
.\scripts\start-session.ps1 -Action Check

# Reutilizar exactamente el SessionId y CandidateSha que mostró la comprobación.
.\scripts\start-session.ps1 -Action Apply -SessionId 'ID_DEVUELTO' -CandidateSha 'SHA_DEVUELTO'
.\scripts\start-session.ps1 -Action Prepare -Background -SessionId 'ID_DEVUELTO' -CandidateSha 'SHA_DEVUELTO'
.\scripts\start-session.ps1 -Action Defer -SessionId 'ID_DEVUELTO' -CandidateSha 'SHA_DEVUELTO'

# Consulta operativa: no representa el inicio de una nueva sesión.
.\update.ps1 -Action Check
```

Los SHA deben ser los 40 caracteres completos. Los comandos devuelven JSON en stdout. El script de consulta diaria nunca activa una candidata, aunque otra sesión la haya preparado. `-Force` se conserva por compatibilidad con tareas antiguas, pero no omite consentimiento ni controles. No usar un nuevo `SessionId` para cada mensaje: corresponde a un MODO ENTRADA lógico y se reutiliza al tomar la decisión. `-WhatIf` no guarda estado, prepara paquetes, lanza procesos ni activa versiones.

`Initialize-AgentOpsUpdate` es el contrato interno usado por el instalador. Las dependencias `Verifier`, `GitRunner` y `TaskController` permiten pruebas aisladas; los puntos de entrada de usuario no exponen una opción para saltarse CI. Los orígenes locales requieren `-LocalDevelopment` en el instalador: se identifican como `LOCAL_DEV`, conservan operación manual y no reciben actualizaciones automáticas. Nunca se reutiliza una caché al cambiar el repositorio o canal.

## Activación y recuperación

La activación verifica el paquete, toma el bloqueo del sincronizador, comprueba conflictos y guarda preimágenes y un journal antes de modificar archivos. Pausa únicamente la tarea del vigilante cuya identidad corresponde a esta instalación; no busca procesos por coincidencias amplias. Un vigilante manual no administrado impide sustituir su versión.

El nuevo motor sincroniza solo las seis skills públicas para esta operación. Las personalizaciones entran en conflicto en lugar de ser sobrescritas. El cambio del código activo y de la configuración se completa antes de confirmar la última versión buena. Si el vigilante está habilitado, debe informar mediante heartbeat el SHA y directorio esperados. Mientras existe `activation-pending.json`, su bucle no modifica los perfiles.

El inicio siguiente detecta una activación interrumpida y compara los archivos con el journal. Solo restaura una preimagen si el contenido actual sigue siendo el que desplegó esa operación; conserva cualquier edición posterior. Ante diferencias o una ventana de interrupción que impida probar la autoría del cambio, devuelve `ACTIVATION_REVIEW_REQUIRED`, conserva respaldos y guard y bloquea la activación. No hay una transacción atómica que abarque todos los perfiles.

```powershell
# Reintentar una recuperación después de revisar el journal y las diferencias.
.\scripts\start-session.ps1 -Action Repair
```

No elimines el guard ni el estado para forzar una actualización. Conserva los archivos temporales indicados como respaldos en los journals hasta verificar su copia. `LastGood` solo se confirma después de la verificación de la activación; una descarga fallida no lo cambia. Los paquetes anteriores y los respaldos no se purgan automáticamente.

| Estado | Comportamiento |
|---|---|
| `UPDATE_AVAILABLE` | El anfitrión debe solicitar la decisión indicada por `NeedsUserChoice` |
| `PREPARING` / `READY_NEXT_SESSION` | Continuar con la versión anterior; no activar durante esa sesión |
| `UPDATED` / `UP_TO_DATE` | Usar `ActivePath`; releer instrucciones al actualizar |
| `OFFLINE_CACHED` | Continuar con la instalación verificada; no afirmar que sea la última |
| `UNVERIFIED_CANDIDATE` | Mantener la instalación anterior; no ofrecer esa candidata |
| `SKILL_CONFLICT` | Conservar personalizaciones y resolver con el sincronizador antes de reintentar |
| `BUSY` | Otra operación tiene el bloqueo; `CanStartWork` indica si hay una versión utilizable |
| `RECOVERED` | Se recuperó la operación anterior; revisar el resultado antes de otra actualización |
| `ACTIVATION_REVIEW_REQUIRED` | Revisar journal y ediciones; `ActivePath` no se entrega para iniciar trabajo automáticamente |
| `MIGRATION_REQUIRED` | Reinstalar explícitamente para registrar el bootstrap nuevo |
| `NOT_INSTALLED` / `LOCAL_DEV` | No hay instalación administrada o se eligió desarrollo local |

## Migración y pruebas

Reejecuta el instalador verificado para migrar una instalación previa. Rechaza checkouts sucios, otro origen, worktrees o retrocesos; nunca elimina una carpeta existente para clonar. `-SkipTask` omite registro de tareas y conserva la preferencia guardada del vigilante; `-DisableWatcher` mantiene la consulta diaria y desactiva el vigilante. Retira manualmente accesos de Inicio de vigilantes antiguos cuya procedencia no pueda verificarse.

Las pruebas se ejecutan secuencialmente en ambos intérpretes. Usan repositorios y perfiles temporales, un trabajador oculto real, cierres abruptos de procesos propios y un programador de tareas simulado. Incluyen caché corrupta, pérdida de red, CI no disponible, cambios posteriores a una interrupción y exclusión de contenido privado.

```powershell
.\tests\skills-sync.tests.ps1 -IncludeLinkTest
.\tests\windows-integration.tests.ps1
.\tests\update-coordinator.tests.ps1
.\tests\release-policy.tests.ps1
```
