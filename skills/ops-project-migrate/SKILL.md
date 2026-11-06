---
name: ops-project-migrate
description: Migra proyectos existentes a la arquitectura de gobernanza universal v2, repara .context/ faltante, actualiza AGENTS.md y elimina carpetas de skills duplicadas sin destruir datos.
triggers:
  - "ops-project-migrate"
  - "ops-migrar-proyecto"
  - "project migrate"
  - "migrar proyecto"
  - "limpiar skills duplicadas"
---

# Skill: Migración y Estandarización de Proyectos (`ops-project-migrate`)

## REGLA DE ORO (NO-DESTRUCTIVA):
- **Si los archivos de `.context/` YA existen:** Está ESTRICTAMENTE PROHIBIDO sobrescribirlos o borrar su contenido preexistente.
- **Si alguno de los 5 archivos de `.context/` NO existe:** Créalo con la estructura base sin afectar el resto del proyecto.

---

## PROCEDIMIENTO PASO A PASO:

### 1. Rescate de Skills Locales e Ingesta Previa (Harvest-First)
- Si el proyecto contiene una subcarpeta local `./skills/` o existen habilidades previas en arneses locales (`~/.claude/skills`, `~/.gemini/config/skills`, `~/.agents/skills`):
  - Consolidar y rescatar primero esas skills hacia la bóveda central (`_ai-skills-hub` o `~/.agent-ops`) bajo el principio de *Cosechar Primero*.
  - Una vez confirmado el respaldo en el hub central, **eliminar la carpeta local `./skills/`** del proyecto y cualquier script local obsoleto (`sync_skills_hub.bat`) para prevenir discrepancias de versión y duplicidad.

### 2. Verificación y Autorreparación de `.context/`
- Asegurar la presencia de los 5 archivos en `.context/`:
  - `projectbrief.md`
  - `systemPatterns.md`
  - `activeContext.md`
  - `progress.md`
  - `lessons_learned.md`
- En `systemPatterns.md`, garantizar la inclusión de los mandatos de TDD (`dev-tdd`) y depuración sistemática de causa raíz (`dev-systematic-debugging`).

### 3. Actualización de `AGENTS.md` (Gobernanza Universal v2)
- Respaldar el archivo previo si existe en `.context/AGENTS.bak`.
- Inyectar el `AGENTS.md` estandarizado con los 6 Protocolos Universales:
  1. Protocolo 1: Inicio de Turno (MODO ENTRADA con auditoría Git y TTL 24h).
  2. Protocolo 2: Cero Suposiciones y Memoria Cruda.
  3. Protocolo 3: Invocación Mandatoria y Anti-Racionalización (`dev-systematic-debugging` y `dev-tdd`).
  4. Protocolo 4: Destilación Controlada a Skill General.
  5. Protocolo 5: Escritor Único e Higiene Cloud.
  6. Protocolo 6: Cierre de Turno (MODO SALIDA con verificación objetiva).

### 4. Blindaje Git y Commit de Migración
- Aplicar optimizaciones locales:
  ```bash
  git config core.fscache true
  git config core.preloadindex true
  git config core.longpaths true
  ```
- Ejecutar:
  `git add -A` -> esperar 1 segundo -> `git commit -m "chore(arch): upgrade project to universal agent governance v2"`.
