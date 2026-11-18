# Migración de proyectos existentes (Windows)

El marco global actualiza sus herramientas y skills; cada proyecto conserva su propia memoria y sus reglas. `ops-project-migrate` dirige la revisión y usa un ejecutor verificable. La ejecución requiere una instalación administrada válida; un hub nuevo no sustituye una configuración ausente o dañada. macOS y Linux quedan limitados a auditoría y planificación.

Inicia MODO ENTRADA, resuelve cualquier actualización o recuperación del marco y conserva el `ActivePath` devuelto. La herramienta nueva vive dentro de esa versión, no necesariamente dentro del bootstrap instalado:

```powershell
$entry = Join-Path $ActivePath 'scripts/migrate-project.ps1'
& $entry -ProjectPath 'C:\Proyectos\Ejemplo' -Mode Plan
# Para una instalación personalizada, pasar -ConfigPath a TODOS los comandos.
& $entry -ProjectPath 'C:\Proyectos\Ejemplo' -Mode Apply -WhatIf
```

El modo predeterminado es `Plan`. Ni ese modo ni `WhatIf` crean estado, archivos, respaldos o destinos. `ConfigPath` predetermina `%LOCALAPPDATA%\AgentOps\watch-config.json`; hub, réplicas y estado se leen de esa configuración. Las rutas y su vinculación a la versión activa se validan antes de escribir.

## Reglas particulares y aplicación

Si falta `AGENTS.md`, se usa la plantilla activa. Si ya existe, una marca de la plantilla permite reconocer migraciones completadas. Sin esa marca se devuelve `AGENTS_REVIEW_REQUIRED` con el hash actual. El asistente debe leer el documento, conservar reglas particulares y preparar una fusión; el ejecutor no puede determinar automáticamente la compatibilidad semántica de instrucciones arbitrarias.

Guardar el borrador fuera del proyecto, en una ubicación privada, revisar el diff y aplicar la versión acordada:

```powershell
& $entry -ProjectPath 'C:\Proyectos\Ejemplo' -Mode Apply `
  -AgentsCandidatePath 'C:\RutaPrivada\agents-candidato.md' `
  -ExpectedAgentsHash 'HASH_DEVUELTO_POR_PLAN'
```

Si el original cambia, `PROJECT_CHANGED` impide aplicar el candidato anterior. Los archivos existentes de `.context/` se conservan; solo se crean los ausentes. La sección de ingeniería de `systemPatterns.md` puede recibir una adición identificable cuando falten referencias de TDD o depuración. La operación se puede repetir sin duplicar protocolos.

## Skills y privacidad

`skills/` y `_ai-skills-hub/` dentro del proyecto se inspeccionan como posibles orígenes. Solo se reconocen subcarpetas con `SKILL.md`; el resto se conserva sin interpretarlo como skills. `-ImportSources` permite añadir otros orígenes antiguos identificados. Ninguno recibe escrituras ni se registra como réplica permanente; su desaparición posterior no representa un borrado solicitado.

El motor rescata cada árbol reconocido completo: scripts, adjuntos, binarios, archivos ocultos, cachés y directorios vacíos. Las cachés se guardan en el respaldo pero no se distribuyen. Enlaces, errores de lectura o blobs dañados impiden declarar una copia íntegra. No se ejecuta contenido importado. Las diferencias se comparan por SHA-256; las versiones divergentes requieren revisión. Una skill pública antigua nunca reemplaza automáticamente el catálogo activo. Ante conflictos, `Apply` guarda un rescate de las versiones sin propagarlas ni modificar los metadatos del proyecto.

El hub y los respaldos permanecen fuera del checkout. Las carpetas originales no se borran ni se mueven. Si el anfitrión sigue cargando copias locales antiguas, hay que revisar su selección de skills; conservarlas no equivale a haber cambiado qué copia usa cada aplicación.

Para una resolución explícita, usar el sincronizador de `ActivePath`, las mismas ubicaciones configuradas y los `ImportSources` que devuelve la evaluación. `Key` identifica un archivo y `VersionHash` una versión presente en el conflicto; no se escoge por fecha:

```powershell
$syncArgs = @{
  HubDir = $config.HubDir; Targets = $config.Targets; StateDir = $config.StateDir
  FrameworkDir = $ActivePath; ImportSources = $evaluacion.ImportSources
}
& "$ActivePath/scripts/sync-skills.ps1" @syncArgs -Mode Resolve `
  -Key 'mi-skill/SKILL.md' -VersionHash 'HASH_ELEGIDO_EXPLICITAMENTE' -Json
```

Después repetir la evaluación de la migración. Los resultados y respaldos incluyen todas las versiones; una resolución de un archivo no implica resolver automáticamente el resto de la skill.

## Recuperación y Git

Los journals y respaldos duraderos se guardan en `StateDir/migrations/<identificador-del-proyecto>` y en el almacén privado de blobs. Una sustitución atómica interrumpida puede dejar una captura temporal junto al archivo; el journal conserva su referencia. Revisar las recuperaciones antes de preparar commits.

Si aparece `RECOVERY_REQUIRED`, un `Apply` posterior recupera primero y devuelve `RECOVERED`, sin iniciar otra migración en esa llamada. La recuperación compara hashes y conserva cualquier edición posterior; diferencias no atribuibles a la operación devuelven `RECOVERY_REVIEW_REQUIRED`. No borrar el journal para forzar el resultado. Los rescates completos ya realizados se conservan aunque se reviertan los metadatos. No existe una transacción global entre perfiles y proyecto.

Sin `-Commit`, los cambios quedan locales. Con esa opción se exige raíz Git del proyecto, índice limpio y archivos afectados sin trabajo previo pendiente; se agregan exclusivamente los metadatos revisados. No hay push ni cambios automáticos de opciones Git. `COMMIT_REVIEW_REQUIRED` significa que los archivos pueden estar migrados, pero el commit necesita revisión. Nunca utilizar `git add -A` como sustituto.

Estados satisfactorios: `PLANNED`, `MIGRATED`, `RECOVERED`. Los códigos comunes son `0` satisfactorio, `1` error, `2` revisión pendiente y `3` ocupado. Un resultado satisfactorio se limita al alcance verificado, no garantiza la configuración de todos los anfitriones ni un respaldo externo del disco.
