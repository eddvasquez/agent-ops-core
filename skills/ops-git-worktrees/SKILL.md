---
name: ops-git-worktrees
description: Procedimiento para crear, gestionar y limpiar directorios de trabajo paralelos con git worktree de forma segura en Windows, macOS y Linux sin colisiones ni bloqueos de ramas.
triggers:
  - "ops-git-worktrees"
  - "git worktree"
  - "ramas paralelas"
  - "aislar rama"
  - "worktree"
  - "trabajar en paralelo git"
---

# Skill: Gestión de Git Worktrees (Aislamiento Paralelo)

## Propósito y Alcance
Esta skill proporciona el procedimiento canónico para operar múltiples ramas simultáneamente en un mismo repositorio mediante `git worktree`.
- **Cuándo usar:** Cuando se requiera desarrollar una nueva característica experimental, ejecutar un agente en paralelo, o revisar un bug sin cambiar de rama ni ensuciar el árbol de trabajo actual.
- **Ventaja:** Permite tener carpetas de trabajo físicas independientes compartiendo el mismo historial y base de datos de `.git`.

---

## REGLAS CRÍTICAS DE ENTORNO (WINDOWS, MACOS, LINUX & CLOUD)

1. **Ubicación de Worktrees:**
   - Crear los worktrees como carpetas hermanas del repositorio principal o en un directorio designado (e.g., `../<repo-name>-worktrees/<nombre-rama>`), evitando anidarlos dentro del árbol de trabajo principal.
   - En carpetas sincronizadas por Google Drive o servicios en la nube, esperar al menos 1 segundo tras comandos que alteren referencias de Git para permitir que se liberen los bloqueos de archivos.
2. **Habilitación de rutas largas:**
   - Asegurar `git config core.longpaths true`.
3. **Prohibición de checkout cruzado:**
   - Git no permite que dos worktrees tengan la misma rama activa a la vez. Siempre crear una rama nueva para cada worktree.

---

## PROCEDIMIENTO PASO A PASO

### 1. Creación de un Worktree
Para iniciar una tarea en una rama nueva (`feature/nombre-tarea`) aislada:
```bash
# Desde el directorio raíz del repositorio principal:
git worktree add -b <nombre-rama> <ruta-destino-worktree> <rama-base>

# Ejemplo práctico:
git worktree add -b feat-nueva-api ../mi-proyecto-feat-api main
```

### 2. Operación dentro del Worktree
- Navegar a la carpeta creada (`cd ../mi-proyecto-feat-api`).
- Operar, editar y compilar normalmente.
- Los commits atómicos realizados allí impactan de inmediato el repositorio Git compartido:
```bash
git status -s
git add .
git commit -m "feat: implementar nuevo endpoint"
```

### 3. Listar Worktrees Activos
Para auditar qué carpetas de trabajo están activas:
```bash
git worktree list
```

### 4. Cierre y Limpieza del Worktree
Una vez que el trabajo ha concluido (fusionado o descartado):
1. **Volver al repositorio principal:**
   ```bash
   cd <ruta-repo-principal>
   ```
2. **Eliminar el worktree:**
   ```bash
   # Elimina la carpeta y desvincula la referencia:
   git worktree remove <ruta-destino-worktree>
   ```
3. **Podar referencias obsoletas:**
   ```bash
   git worktree prune
   ```
4. **Gestionar la rama local:**
   - Si la rama ya se fusionó: `git branch -d <nombre-rama>`
   - Si se decide descartar: `git branch -D <nombre-rama>`
