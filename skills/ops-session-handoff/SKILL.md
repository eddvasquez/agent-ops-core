---
name: ops-session-handoff
description: Protocolo de Recepción (MODO ENTRADA) y Cierre de Turno (MODO SALIDA) con auditoría Git, verificación de auto-actualización cada 24h y mandato anti-racionalización.
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

### Paso 0: Verificación de Actualizaciones de Gobernanza (TTL 24 Horas)
- Si existe el directorio global `~/.agent-ops` y el archivo `~/.agent-ops/.last_update_check`:
  - Verificar si han transcurrido más de 24 horas desde la última verificación.
  - Si es mayor a 24 horas o el archivo no existe, ejecutar silenciosamente `git -C ~/.agent-ops pull --ff-only` y registrar la fecha actual en `.last_update_check`.
  - Si hubo cambios en el repositorio, las skills locales se sincronizan automáticamente.

### Paso 1: Lectura de Contexto y Mandato Anti-Racionalización
1. Lee `AGENTS.md` y los 5 archivos de `.context/` (`projectbrief.md`, `systemPatterns.md`, `activeContext.md`, `progress.md`, `lessons_learned.md`).
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
2. **Reglas Activas:** Restricciones clave de `systemPatterns.md` y `lessons_learned.md`.
3. **Skills Aplicables:** Qué skills gobernarán la sesión (declarando explícitamente `dev-systematic-debugging` o `dev-tdd` si corresponde).
4. **Siguiente Paso Ejecutable:** Qué acción exacta y archivo tocarás inmediatamente tras recibir el "OK".
5. **Dudas Bloqueantes:** Preguntas concisas si falta información crítica.

---

## MODO B: CIERRE DE TURNO (`MODO SALIDA`)
1. **Registrar Lecciones:** Escribir cualquier corrección o aprendizaje en `.context/lessons_learned.md`.
2. **Auditoría Objetiva de Progreso:** Marcar en `.context/progress.md` las tareas terminadas (`[x]`) **únicamente si cuentan con evidencia objetiva de verificación** (pruebas ejecutadas en verde o verificación física confirmada).
3. **Actualización Quirúrgica de Contexto:** Actualizar `.context/activeContext.md` con:
   - Agente activo y fecha.
   - Último archivo modificado.
   - Estado de pruebas/errores.
   - Siguiente paso ejecutable inmediato para el próximo relevo.
4. **Commit Atómico de Relevo:**
   - Ejecutar en el proyecto: `git add .` -> esperar 1 segundo (liberar bloqueos de sincronización cloud) -> `git commit -m "chore(relevo): actualizar activeContext y progreso de sesion"`.
   - Si el proyecto cuenta con un repositorio remoto configurado (`origin`), ejecutar `git push` para respaldo en la nube.
5. *Una vez actualizado activeContext y efectuado el commit, el agente no debe ejecutar código adicional en ese turno.*
