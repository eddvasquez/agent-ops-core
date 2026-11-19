---
name: ops-session-handoff
version: 1.3.0
description: Protocolo de Recepción (MODO ENTRADA) y Cierre de Turno (MODO SALIDA) con auditoría Git, actualizaciones verificadas al inicio de sesión y mandato anti-racionalización.
triggers:
  - "ops-session-handoff"
  - "ops-gestion-relevo"
  - "session handoff"
  - "inicia turno"
  - "modo entrada"
  - "cierra turno"
  - "modo salida"
---

# Skill: Gestión de Relevo y Sesiones (`ops-session-handoff`)

## MODO A: RECEPCIÓN DE TURNO (`MODO ENTRADA`)
**PROHIBIDO modificar archivos o escribir código antes de que el usuario apruebe este reporte.**

### Paso 0: Comprobación de Versiones Verificadas (Windows)
La decisión de actualización de este paso autoriza únicamente los cambios del marco global; los archivos del proyecto siguen sujetos al reporte y autorización del turno.

1. Si existe `~/.agent-ops/scripts/start-session.ps1`, ejecutarlo con `-Action Check` y leer su JSON. Usar siempre ese punto de entrada; no ejecutar `git pull`, no modificar timestamps y no activar versiones mediante otros atajos. La consulta remota tiene un presupuesto de cinco segundos.
2. Conservar el `SessionId` devuelto durante este MODO ENTRADA. Si `NeedsUserChoice` es verdadero, mostrar versión actual, SHA candidato, resumen informativo y estimación. Cuando `Estimate.Measured` sea falso, explicar que todavía no hay mediciones fiables: la preparación de red tiene un presupuesto de dos minutos y la activación puede requerir tiempo adicional. Nunca presentar ese presupuesto como una duración total garantizada.
3. Preguntar al usuario antes de comenzar su trabajo, ofreciendo:
   - **Actualizar ahora:** ejecutar el punto de entrada con `-Action Apply -SessionId <id> -CandidateSha <sha>`.
   - **Preparar en segundo plano para la próxima sesión:** usar `-Action Prepare -Background` con esos mismos identificadores. Esta elección aprueba esa candidata concreta para una sesión posterior; el trabajador solo descarga y verifica.
   - **Posponer:** usar `-Action Defer` con esos identificadores y continuar con la versión actual. No repetir la pregunta para esa misma candidata y sesión.
   Esperar una respuesta explícita; el silencio no elige ninguna opción. La interfaz y la pregunta pertenecen al asistente/anfitrión, no a un `Read-Host` oculto en un proceso.
4. `UPDATED` permite releer las instrucciones del marco desde `ActivePath` antes de auditar el proyecto. `READY_NEXT_SESSION` o `PREPARING` conservan la versión de esta sesión. Una candidata preparada con consentimiento previo se aplica al comenzar otro MODO ENTRADA, no a mitad de una conversación o trabajo.
5. `OFFLINE_CACHED` permite continuar con la instalación verificada e informar brevemente que no pudo comprobarse GitHub. `LOCAL_DEV` identifica una instalación de desarrollo sin actualización automática. `NOT_INSTALLED` o `MIGRATION_REQUIRED` requieren instalación/migración explícita, nunca un `git pull` alternativo. Con `ACTIVATION_REVIEW_REQUIRED`, no eliminar el guard ni sobrescribir ediciones: informar del journal y revisar la recuperación. Con `BUSY`, usar `CanStartWork` y reintentar de forma acotada; un guard de activación impide cargar instrucciones mezcladas.

### Paso 0b: ¿El proyecto está al día con la versión activa?
Se ejecuta también al retomar un chat antiguo, porque MODO ENTRADA corre en cada turno nuevo sobre el proyecto.
1. Ejecutar `& "$ActivePath/scripts/migrate-project.ps1" -ProjectPath <proyecto> -Mode Plan`. Es solo lectura: no escribe en el proyecto ni en el estado.
2. Si devuelve `UpToDate: true` o `Deferred: true`, continuar sin preguntar.
3. Si no, presentar al usuario un resumen breve antes de empezar su trabajo:
   - qué archivos se crearían o actualizarían (`Actions`), que siempre son solo de gobernanza;
   - si `AGENTS.md` se actualiza solo (bloque gestionado sin editar) o necesita revisión (`AGENTS_REVIEW_REQUIRED`, con `AgentsProposal`);
   - la garantía: nada fuera de esos archivos cambia, el contenido previo queda respaldado y se puede revertir con `-Mode Rollback -Journal <JournalId>`.
4. Preguntar: **Migrar ahora**, **Más tarde** (se volverá a ofrecer en la próxima sesión) o **No para esta versión** (`-Mode Defer`, que se recuerda en el estado privado, nunca en el proyecto). Esperar respuesta explícita; el silencio no elige.
5. "Migrar ahora" sigue `ops-project-migrate`. Al terminar, informar del `JournalId` y, si el proyecto usa Git, del `RestoreRef`.

Este inicio se ejecuta al invocar MODO ENTRADA; detectar la apertura de cualquier chat requiere soporte del anfitrión. La tarea diaria solo comprueba novedades y no sustituye la decisión del usuario. macOS/Linux conservan su mecanismo anterior, pendiente de revisión equivalente.

### Paso 1: Lectura de Contexto y Mandato Anti-Racionalización
1. Lee `AGENTS.md` y los archivos de `.context/` (`projectbrief.md`, `systemPatterns.md`, `activeContext.md`, `progress.md`, `lessons_learned.md`, `reglas_proyecto.md`). Lee `reglas_proyecto.md` completo: sus reglas activas gobiernan todo entregable de la sesión (Protocolo 8).
2. Revisa las skills disponibles en tu arnés activo (`.gemini`, `.claude`, `.agents`). Aplica el **Principio Anti-Racionalización**:
   - Si la tarea involucra investigar o corregir un error: es **mandatorio** invocar `dev-systematic-debugging` (prohibido parchar a ciegas).
   - Si involucra diseñar o construir componentes de software: es **mandatorio** invocar `dev-tdd` (Red-Green-Refactor).
   - Si involucra tareas simultáneas o ramas paralelas: evaluar `ops-git-worktrees`.
   - *Queda prohibido evadir skills con pretextos de premura o "cambio pequeño".*

### Paso 2: Auditoría Física en Git
- Ejecuta `git status -s`, `git log -n 3 --oneline` y `git diff --stat`.
- **Regla de resolución:** Si el texto de `activeContext.md` contradice la evidencia física de Git, **prevalece siempre Git**.

### Paso 3: Entrega del Reporte de 5 Puntos
Entrega ÚNICAMENTE estos 5 puntos y **detén tu turno esperando el "OK" explícito del usuario**:
1. **Auditoría Git vs. Contexto:** Estado real del repositorio frente a `activeContext.md`.
2. **Reglas Activas:** Las reglas activas de `reglas_proyecto.md`, por ID y en una línea cada una (si son muchas, las que afectan al trabajo previsto y el total), más las restricciones clave de `systemPatterns.md`.
3. **Skills Aplicables:** Qué skills gobernarán la sesión (declarando explícitamente `dev-systematic-debugging` o `dev-tdd` si corresponde).
4. **Siguiente Paso Ejecutable:** Qué acción exacta y archivo tocarás inmediatamente tras recibir el "OK".
5. **Dudas Bloqueantes:** Preguntas concisas si falta información crítica.

---

## MODO B: CIERRE DE TURNO (`MODO SALIDA`)
1. **Registrar Correcciones y Lecciones:**
   - Repasar la sesión y comprobar que **cada** corrección, rechazo o pedido del usuario o del cliente tiene su regla en `.context/reglas_proyecto.md` (Protocolo 8). Registrar las que falten antes de seguir.
   - Escribir en `.context/lessons_learned.md` el contexto histórico que aporte valor.
   - Si en la sesión se produjeron entregables, confirmar que pasaron `check-rules.ps1`.
2. **Auditoría Objetiva de Progreso:** Marcar en `.context/progress.md` las tareas terminadas (`[x]`) **únicamente si cuentan con evidencia objetiva de verificación** (pruebas ejecutadas en verde o verificación física confirmada).
3. **Actualización Quirúrgica de Contexto:** Actualizar `.context/activeContext.md` con:
   - Agente activo y fecha.
   - Último archivo modificado.
   - Estado de pruebas/errores.
   - Siguiente paso ejecutable inmediato para el próximo relevo.
4. **Verificación de Versionado (Protocolo 7):**
   - Si hay cambios entregables, confirmar que cada artefacto tocado tiene su línea en `[Unreleased]` de su changelog (`CHANGELOG.md` del proyecto o `changelogs/<skill>.md`) y que su versión declarada es SemVer válida.
   - Ejecutar `& "$ActivePath/scripts/check-versioning.ps1" -RepositoryPath <proyecto>`. Si devuelve código distinto de `0`, corregir las incidencias que lista antes de commitear; no debilitar el verificador ni omitirlo. Las advertencias de rotación indican mover versiones antiguas a `changelogs/archive/`.
   - Leer el changelog solo en este paso (sección `[Unreleased]` y última versión), nunca completo ni en MODO ENTRADA.
5. **Commits separados y selectivos:**
   - Prohibido `git add .` y `git add -A`, y prohibido componer `git commit`/`git tag` a mano. Todo commit pasa por `& "$ActivePath/scripts/commit.ps1"`, que prepara solo las rutas indicadas, recibe el mensaje por archivo, verifica el Protocolo 7 y se detiene en el primer fallo.
   - Primero, si hay cambios funcionales: escribir el mensaje Conventional Commits (`<tipo>(<artefacto>): <resumen>`; `BREAKING CHANGE:` exige subir MAJOR) en un archivo temporal y ejecutar `commit.ps1 -RepositoryPath <proyecto> -Paths <rutas del cambio> <changelog> -MessageFile <archivo>`.
   - Comprobar su JSON: `Code` `0` y `Status` `COMMITTED`. Si no, corregir lo que indique `Step`/`Issues` antes de seguir.
   - Después, el relevo: esperar 1 segundo (liberar bloqueos de sincronización cloud) y ejecutar `commit.ps1 -RepositoryPath <proyecto> -Paths .context -Message "chore(relevo): actualizar activeContext y progreso de sesion"`.
   - Si el proyecto cuenta con un repositorio remoto configurado (`origin`), ejecutar `git push` en una llamada aparte, solo si los commits anteriores devolvieron `Code` `0`.
6. *Una vez actualizado activeContext y efectuado el commit, el agente no debe ejecutar código adicional en ese turno.*
