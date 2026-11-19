---
name: ops-project-migrate
version: 2.0.0
description: Evalúa y migra proyectos existentes a Agent Ops Core mediante un ejecutor verificable en Windows. Conserva memoria, reglas particulares y skills completas; rescata orígenes sin modificarlos, identifica conflictos y deja los cambios locales por defecto.
triggers:
  - "ops-project-migrate"
  - "ops-migrar-proyecto"
  - "project migrate"
  - "migrar proyecto"
  - "limpiar skills duplicadas"
---

# Migración segura de proyectos existentes

## Alcance y autorización

Esta skill adapta los archivos del proyecto; `ops-session-handoff` inicia y cierra sesiones y `ops-project-init` crea proyectos nuevos. La solicitud de migración autoriza los cambios reversibles necesarios, conservando las decisiones particulares del proyecto. Solicita una decisión concreta si hay reglas contradictorias o versiones divergentes; no elijas una por fecha. No prometas una migración finalizada mientras existan pendientes.

La ejecución verificable cubre Windows. En otros sistemas, limitarse a una auditoría y un plan; no utilizar los instaladores Unix como si ofrecieran las mismas garantías.

## 1. Identificar instalación y proyecto

- Ejecutar MODO ENTRADA y conservar su `SessionId`. Utilizar el `ActivePath` verificado para localizar `scripts/migrate-project.ps1`; no asumir que el bootstrap contiene un ejecutor recién añadido.
- Usar el `ConfigPath` de la instalación seleccionada. Por defecto: `%LOCALAPPDATA%\AgentOps\watch-config.json`. Si el usuario utiliza otra instalación, pasar su ruta explícita; no elegir entre varias por antigüedad ni escanear discos buscando un hub.
- Leer `HubDir`, `Targets` y `StateDir` de esa configuración. `~/.agent-ops` contiene el bootstrap público; el hub predeterminado que crea el instalador es `~/.agent-ops-hub`. Una ruta personalizada válida prevalece. Si falta la configuración o es inválida, detener la migración y resolver la instalación; no crear otro hub como sustituto.
- Leer `AGENTS.md`, `.context/`, las instrucciones específicas del proyecto y el estado de Git. No ejecutar `git pull` como alternativa al coordinador ni alterar opciones de Git.

## 2. Evaluar sin escribir

Invocar desde `ActivePath`:

```powershell
& "$ActivePath/scripts/migrate-project.ps1" -ProjectPath $ProjectPath -ConfigPath $ConfigPath -Mode Plan
```

El resultado JSON incluye acciones, `AgentsHash`, conflictos y códigos: `0` evaluación satisfactoria, `1` fallo, `2` revisión necesaria, `3` ocupado. Reintentar de forma acotada si está ocupado. `-WhatIf` tampoco crea estado, respaldos ni destinos.

El ejecutor detecta `skills/` y `_ai-skills-hub/` dentro del proyecto. Solo reconoce como skills las carpetas que contienen `SKILL.md`. Para otras ubicaciones antiguas identificadas y autorizadas, pasar `-ImportSources`. Son orígenes temporales de solo lectura, nunca réplicas permanentes. No borrar ni mover esas carpetas o sus scripts; una carpeta llamada `skills/` puede contener código de la aplicación.

El rescate abarca el árbol completo de cada skill reconocida: instrucciones, scripts, referencias, adjuntos, binarios, archivos ocultos y directorios vacíos. Las cachés quedan respaldadas, aunque no se propagan. Enlaces o archivos ilegibles impiden declarar un rescate completo. Las copias antiguas de las skills públicas no sustituyen automáticamente la versión activa ni personalizaciones.

## 3. Conservar reglas y memoria

- **`AGENTS.md` con bloque gestionado:** los protocolos del marco viven entre `<!-- agent-ops:begin version=… hash=… -->` y `<!-- agent-ops:end -->`. Todo lo que está fuera es del proyecto y la migración nunca lo toca.
  - Si el bloque no se editó, se actualiza solo en cada versión y el texto exterior se conserva byte a byte.
  - Si se editó dentro del bloque, o el archivo es de un formato antiguo con reglas propias, devuelve `AGENTS_REVIEW_REQUIRED` con `AgentsProposal`: el bloque nuevo y, debajo de `## Reglas particulares del proyecto`, cada línea propia del original. Un archivo antiguo hecho solo con texto de plantillas oficiales se convierte solo, porque no hay nada del proyecto que perder.
- **Revisión con el usuario:** guardar `AgentsProposal` fuera del proyecto (por ejemplo, en el scratchpad) y mostrarle las líneas de "Reglas particulares". Si alguna es texto obsoleto de una plantilla antigua que quiere quitar, ajustar el candidato y escribir esas líneas, una por línea, en un archivo de **eliminaciones aprobadas**. No quitar ninguna línea sin su aprobación explícita.
- Aplicar con `-AgentsCandidatePath <candidato> -ExpectedAgentsHash <AgentsHash> [-ApprovedRemovalsPath <archivo>]`.
  - El ejecutor exige que el candidato contenga el bloque gestionado vigente sin modificar.
  - **Compuerta de conservación:** comprueba mecánicamente que cada línea propia del original siga en el candidato o figure en las eliminaciones aprobadas. Si falta alguna, devuelve `AGENTS_RULES_MISSING` con `MissingLines` y no escribe nada.
  - Si el original cambió desde la evaluación, devuelve `PROJECT_CHANGED`: volver a evaluar, nunca forzar.
- Si falta `AGENTS.md`, el ejecutor usa la plantilla activa. Crea únicamente archivos ausentes de `.context/`. Conserva íntegros los existentes; la incorporación de referencias de ingeniería a `systemPatterns.md` es aditiva y aplicable al trabajo de software.
- **Protocolo 7:** si falta `CHANGELOG.md`, el ejecutor lo crea desde `templates/CHANGELOG.md`; uno existente nunca se modifica. Tras migrar, declarar la versión actual del artefacto (`VERSION`, manifiesto del stack o cabecera de WordPress) y, para skills, `version:` en el frontmatter con su `changelogs/<skill>.md`. Validar con `scripts/check-versioning.ps1` de `ActivePath`. Un `AGENTS.md` de plantillas anteriores se convierte al bloque gestionado como se describe arriba.
- **Protocolo 8 – siembra de reglas:** el ejecutor crea `.context/reglas_proyecto.md` si falta y nunca modifica uno existente. Las correcciones pasadas no se adivinan:
  1. Revisar `lessons_learned.md`, `docs/`, los briefs y los entregables previos en busca de correcciones, prohibiciones y requisitos del cliente.
  2. Presentarlos al usuario como **reglas candidatas** (tipo, ámbito y texto, con el origen de cada una).
  3. Registrar solo las que confirme, con el formato de la plantilla.
  4. Comprobar el archivo con `check-rules.ps1` de `ActivePath` sobre un entregable existente.

## 4. Aplicar y verificar

Ejecutar `-Mode Apply` con las mismas rutas y el candidato revisado si corresponde. La aplicación realiza rescate íntegro previo y guarda un journal privado. Ante conflictos de skills, respalda las versiones sin propagarlas y devuelve revisión necesaria. Resolver únicamente versiones elegidas explícitamente mediante `scripts/sync-skills.ps1` de `ActivePath`, pasando `HubDir`, `Targets`, `StateDir`, `FrameworkDir` e `ImportSources` de la misma evaluación/configuración, junto con `-Mode Resolve -Key <archivo> -VersionHash <hash>`. Después volver a evaluar.

`MIGRATED` confirma la migración y devuelve:
- `JournalId`;
- `RestoreRef`, una referencia oculta de Git `refs/agent-ops/pre-migration/<id>` al `HEAD` previo, que no mueve ramas;
- el registro `.context/agent-ops.json`, con la versión del marco que sigue el proyecto.

**Deshacer:** `-Mode Rollback -Journal <JournalId>` devuelve cada archivo migrado a su contenido exacto anterior y elimina los que la migración creó. Si alguno se editó después, no toca nada y devuelve `ROLLBACK_REVIEW_REQUIRED`.

**No para esta versión:** `-Mode Defer` lo recuerda en el estado privado de la instalación, solo para la plantilla vigente.

Una repetición no debe duplicar protocolos ni reescribir archivos sin cambios (`UpToDate: true`). `RECOVERY_REQUIRED` indica una operación interrumpida: un `Apply` posterior intenta recuperar primero y devuelve `RECOVERED`; revisar ese resultado antes de repetir la migración. `RECOVERY_REVIEW_REQUIRED` conserva ediciones posteriores y requiere revisar el journal. No eliminar guards, respaldos ni archivos temporales para aparentar éxito.

Los respaldos duraderos y borradores están fuera del proyecto. La sustitución atómica puede dejar capturas temporales locales tras una interrupción; deben resolverse antes de preparar un commit. Un rescate completo ya realizado se conserva incluso si se revierten los metadatos del proyecto. No existe una transacción atómica que abarque todos los perfiles y el proyecto.

## 5. Git y entrega

Por defecto dejar los cambios locales y mostrar el diff, los respaldos y cualquier pendiente. Si el usuario pide commit, usar `-Commit`: exige índice limpio y ausencia de cambios previos en los archivos afectados, y agrega exclusivamente los archivos de migración revisados. Si devuelve `COMMIT_REVIEW_REQUIRED`, la migración puede estar aplicada; revisar Git antes de reintentar. No ejecutar `git add -A`, cambiar configuración de Git ni hacer push automáticamente.

No incluir borradores, respaldos ni skills personales en commits. La publicación del marco contiene únicamente las seis definiciones públicas permitidas. Después de migrar, utilizar MODO ENTRADA para las sesiones normales, sin repetir la migración en cada chat.
