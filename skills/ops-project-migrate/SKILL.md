---
name: ops-project-migrate
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

- Si existe `AGENTS.md` y necesita adaptación, preparar una fusión con los seis protocolos de `templates/AGENTS.md` de la versión activa. Conservar reglas particulares y revisar contradicciones explícitamente. Guardar el candidato fuera del proyecto, preferentemente en el estado privado de la instalación, sin sobrescribir archivos anteriores.
- Presentar el diff concreto de esa fusión. Si el usuario ya autorizó una adaptación compatible, continuar; si una contradicción requiere elegir una política, esperar esa decisión.
- Pasar `-AgentsCandidatePath` y el `-ExpectedAgentsHash` devuelto por la evaluación. Si el original cambió, evaluar nuevamente; nunca forzar el hash anterior. El ejecutor verifica integración mínima y concurrencia; la revisión semántica y la conservación de reglas corresponden al asistente, no a una comparación automática de textos.
- Si falta `AGENTS.md`, el ejecutor usa la plantilla activa. Crea únicamente archivos ausentes de `.context/`. Conserva íntegros los existentes; la incorporación de referencias de ingeniería a `systemPatterns.md` es aditiva y aplicable al trabajo de software.

## 4. Aplicar y verificar

Ejecutar `-Mode Apply` con las mismas rutas y el candidato revisado si corresponde. La aplicación realiza rescate íntegro previo y guarda un journal privado. Ante conflictos de skills, respalda las versiones sin propagarlas y devuelve revisión necesaria. Resolver únicamente versiones elegidas explícitamente mediante `scripts/sync-skills.ps1` de `ActivePath`, pasando `HubDir`, `Targets`, `StateDir`, `FrameworkDir` e `ImportSources` de la misma evaluación/configuración, junto con `-Mode Resolve -Key <archivo> -VersionHash <hash>`. Después volver a evaluar.

`MIGRATED` confirma la migración. Una repetición no debe duplicar protocolos ni reescribir archivos sin cambios. `RECOVERY_REQUIRED` indica una operación interrumpida: un `Apply` posterior intenta recuperar primero y devuelve `RECOVERED`; revisar ese resultado antes de repetir la migración. `RECOVERY_REVIEW_REQUIRED` conserva ediciones posteriores y requiere revisar el journal. No eliminar guards, respaldos ni archivos temporales para aparentar éxito.

Los respaldos duraderos y borradores están fuera del proyecto. La sustitución atómica puede dejar capturas temporales locales tras una interrupción; deben resolverse antes de preparar un commit. Un rescate completo ya realizado se conserva incluso si se revierten los metadatos del proyecto. No existe una transacción atómica que abarque todos los perfiles y el proyecto.

## 5. Git y entrega

Por defecto dejar los cambios locales y mostrar el diff, los respaldos y cualquier pendiente. Si el usuario pide commit, usar `-Commit`: exige índice limpio y ausencia de cambios previos en los archivos afectados, y agrega exclusivamente los archivos de migración revisados. Si devuelve `COMMIT_REVIEW_REQUIRED`, la migración puede estar aplicada; revisar Git antes de reintentar. No ejecutar `git add -A`, cambiar configuración de Git ni hacer push automáticamente.

No incluir borradores, respaldos ni skills personales en commits. La publicación del marco contiene únicamente las seis definiciones públicas permitidas. Después de migrar, utilizar MODO ENTRADA para las sesiones normales, sin repetir la migración en cada chat.
