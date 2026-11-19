# Protocolo de Operación de Agentes (Arquitectura v2 Universal)

Todo agente o modelo de Inteligencia Artificial (Claude Code, Antigravity/Gemini, OpenAI Codex, ChatGPT Desktop, Hermes o cualquier otro arnés que trabaje con proyectos locales) que opere en este repositorio debe cumplir de forma estricta e innegociable con los siguientes protocolos:

---

### Protocolo 1 (Inicio de Sesión y Auditoría Git - MODO ENTRADA)
- Al iniciar cualquier turno sobre el proyecto, es mandatorio invocar la skill `ops-session-handoff` (o `ops-gestion-relevo`) bajo **MODO ENTRADA**.
- En Windows, su Paso 0 comprueba el canal estable mediante el punto de entrada instalado. Si hay una candidata verificada, presentar versión, cambios y estimación y respetar la elección de actualizar ahora, preparar para la próxima sesión o posponer. Esta decisión autoriza únicamente la actualización del marco global, no cambios en los archivos del proyecto. No sustituir el mecanismo por un `git pull` directo.
- Lee `AGENTS.md`, todos los archivos de `.context/` (`projectbrief.md`, `systemPatterns.md`, `activeContext.md`, `progress.md`, `lessons_learned.md`, `reglas_proyecto.md`) y las skills disponibles en tus aplicaciones de IA.
- Ejecuta una auditoría física en Git (`git status -s`, `git log -n 3 --oneline`, `git diff --stat`).
- **Resolución de discrepancias:** En caso de existir cualquier contradicción entre el texto de `.context/activeContext.md` y el estado real del árbol de trabajo en Git, **prevalece siempre la evidencia física de Git**.
- Emite el reporte de sincronización de 5 puntos y **detente a esperar la confirmación explícita del usuario** antes de tocar archivos o escribir código.

---

### Protocolo 2 (Cero Suposiciones y Memoria Cruda)
- Está terminantemente prohibido adivinar requerimientos, suponer dependencias o inventar credenciales.
- Cuando falte información crítica o existan ambigüedades, formula preguntas concisas y bloqueantes.
- Toda corrección, rechazo de enfoque o directriz permanente expresada por el usuario se registra de inmediato:
  - como regla aplicable en `.context/reglas_proyecto.md` (Protocolo 8);
  - y, si aporta contexto útil, como entrada histórica en `.context/lessons_learned.md`, con fecha, error original y regla corregida.

---

### Protocolo 3 (Invocación Mandatoria y Anti-Racionalización)
- Si una tarea tiene $\ge 1\%$ de probabilidad de beneficiarse de una skill especializada instalada, su invocación y lectura de `SKILL.md` es **obligatoria** antes de generar código o responder.
- **En tareas de depuración:** Es mandatorio invocar `dev-systematic-debugging`. Prohibido el *shotgun debugging* (parchear a ciegas o modificar código especulativamente).
- **En desarrollo de código nuevo:** Es mandatorio invocar `dev-tdd` (ciclo estricto Red-Green-Refactor). Prohibido escribir código de producción sin una prueba previa que haya fallado por la razón correcta.

---

### Protocolo 4 (Destilación Controlada a Skill General)
- Está estrictamente prohibido modificar o crear archivos dentro de carpetas de skills sin la autorización humana explícita.
- Cuando una solución o regla documentada en `.context/lessons_learned.md` demuestre ser universalmente reutilizable para otros proyectos, el agente debe proponer formalmente al usuario su destilación como Skill Global en su bóveda central.

---

### Protocolo 5 (Escritor Único e Higiene en Almacenamiento Cloud)
- **Principio de escritor único:** Validar que el campo `Agente Activo` en `.context/activeContext.md` coincida con la plataforma actual antes de efectuar escrituras.
- **Prohibición de duplicados:** Estrictamente prohibido crear archivos con sufijos de versionado (`_v01`, `_v2`, `_final`, `_WIP`, `_backup`). Toda iteración se versiona exclusivamente mediante commits atómicos de Git.
- **Higiene en carpetas sincronizadas:** Advertir y solicitar confirmación previa antes de instalar dependencias masivas locales (`node_modules/`, `.venv/` o descargas pesadas) para no saturar la sincronización en la nube.

---

### Protocolo 6 (Cierre de Turno / Handoff - MODO SALIDA)
- Al concluir cualquier unidad de trabajo o antes de devolver el control al usuario, el agente debe ejecutar obligatoriamente `ops-session-handoff` (o `ops-gestion-relevo`) bajo **MODO SALIDA**.
- Actualizar `.context/lessons_learned.md` si hubo aprendizajes o correcciones.
- Actualizar `.context/progress.md` marcando con `[x]` **únicamente hitos comprobados objetivamente** mediante pruebas ejecutadas en verde o verificación física.
- Actualizar `.context/activeContext.md` indicando con precisión quirúrgica: último archivo modificado, estado de revisión/errores y el siguiente paso ejecutable inmediato para el próximo relevo.
- Ejecutar el verificador de versionado (Protocolo 7) y corregir cualquier fallo antes de commitear.
- **Commits separados:** primero los cambios funcionales, con su entrada de changelog y un mensaje Conventional Commits; después el commit de relevo, que solo contiene `.context/`. Prohibido `git add .` o `git add -A`.
- **Todo commit y toda etiqueta se hacen con la herramienta del marco**, nunca componiendo `git` a mano: `& "$ActivePath/scripts/commit.ps1" -RepositoryPath <proyecto> -Paths <rutas> -MessageFile <archivo>` (opcional: `-Tag vX.Y.Z -TagMessage "…"`).
  - Prepara solo esas rutas, pasa el mensaje por archivo (comillas, tildes y saltos de línea llegan intactos), verifica el Protocolo 7 y crea la etiqueta únicamente sobre el commit recién hecho.
  - Si algo falla, se detiene y devuelve `Code` distinto de `0` y el `Step` exacto: no continuar con el paso siguiente.
- Commit de relevo: `& "$ActivePath/scripts/commit.ps1" -RepositoryPath <proyecto> -Paths .context -Message "chore(relevo): actualizar activeContext y progreso de sesion"`. Esperar 1 segundo antes, para liberar bloqueos de la nube.
- **Operaciones con efectos (commit, etiqueta, push, borrados):** una por llamada, comprobando su resultado antes de la siguiente. Prohibido encadenarlas con `;` o `&&` en una sola línea: un comando nativo que falla no detiene la línea en Windows PowerShell 5.1. Los textos libres (mensajes, JSON) se pasan por archivo, nunca como argumento entre comillas.
- *Una vez actualizado activeContext y efectuado el commit, el agente no debe ejecutar código adicional en ese turno.*

---

### Protocolo 7 (Versionado Semántico y Trazabilidad de Cambios)
- **Unidad versionable:** todo artefacto entregable (proyecto, tema o plugin de WordPress, skill, script independiente) declara su versión SemVer `MAJOR.MINOR.PATCH` en su lugar natural: `VERSION` o `package.json`/`pyproject.toml` (proyecto), cabecera `Version:` de `style.css` o del archivo principal (WordPress), `version:` en el frontmatter de `SKILL.md` (skill). Nunca en el nombre del archivo (Protocolo 5).
- **SemVer:** MAJOR rompe un contrato (flags, formato de salida, API, comportamiento esperado del agente); MINOR añade capacidad compatible; PATCH corrige sin cambiar el contrato.
- **Changelog:** formato Keep a Changelog. Proyecto: `CHANGELOG.md` en la raíz, o `docs/CHANGELOG.md` (con `docs/VERSION`) cuando el repositorio solo puede publicar dentro de `docs/`. Skills: `changelogs/<skill>.md` (o `docs/changelogs/<skill>.md`) en la raíz del repositorio que las versiona, **nunca dentro de la carpeta de la skill** ni enlazado desde `SKILL.md`, para no consumir contexto al usarla. Todo cambio entregable añade una línea orientada a impacto en `## [Unreleased]` **en el mismo commit**. Conservar como máximo 10 versiones publicadas; las anteriores pasan a `changelogs/archive/`.
- **Commits:** Conventional Commits con ámbito del artefacto (`feat(<artefacto>): …`, `fix(<artefacto>): …`). `BREAKING CHANGE:` obliga a subir MAJOR.
- **Publicación:** mover `[Unreleased]` a `## [X.Y.Z] - AAAA-MM-DD`, actualizar la versión declarada y crear un tag anotado: `vX.Y.Z` (proyecto) o `<skill>@vX.Y.Z` (repositorio de skills).
- **Despliegues fuera de Git** (WordPress en vivo, GTM, Google Ads, Kiral…): registrar en `CHANGELOG.md` la versión desplegada, el destino, la fecha y la verificación. Sin entrada no hay despliegue.
- **Lectura del changelog:** solo al editar el artefacto (`[Unreleased]` y la última versión) o al auditar diferencias entre versiones. No forma parte de MODO ENTRADA.
- **Verificación:** `& "$ActivePath/scripts/check-versioning.ps1" -RepositoryPath <repo>` debe devolver código `0` antes de cada commit; en CI, con `-Base <commit anterior> -Head <commit>`.

---

### Protocolo 8 (Reglas del Proyecto y Compuerta de Cumplimiento)
- **Fuente de verdad:** `.context/reglas_proyecto.md` reúne las correcciones, prohibiciones y requisitos del proyecto y de su cliente. Prevalece sobre las skills, sobre ejemplos anteriores y sobre lo que se recuerde de la conversación. `lessons_learned.md` es solo el historial.
- **Captura inmediata:** cuando el usuario corrija, rechace o pida eliminar algo, registrar la regla **en ese mismo turno, antes de continuar**, y confirmarlo en una línea ("Registrada R-NNN: …"). Si no queda escrita, la corrección no existe para la próxima conversación.
- **Nivel correcto:** redactar la regla para el proyecto, no para el entregable. "No afirmar X" en lugar de "quitar X del hero". El ámbito por defecto es `todas`; restringirlo (`landing`, `anuncios`…) solo cuando el usuario lo indique.
- **Cambios por delta:** añadir, modificar o retirar reglas por su ID (`[estado: retirada]`). Nunca reescribir ni resumir el archivo entero, porque se perderían detalles.
- **Inyección en el momento de uso:** releer `reglas_proyecto.md` justo antes de producir cualquier entregable (copy, anuncios, landing, guion, código, contenido) y de nuevo antes de entregarlo. También tras una compactación o un resumen de la conversación.
- **Todo entregable vive en un archivo:** copy, anuncios, guiones o correos se guardan en el proyecto antes de entregarlos, aunque también se muestren en el chat. Lo que solo existe en el chat no pasa por la compuerta.
- **Compuerta antes de entregar:**
  1. Ejecutar `& "$ActivePath/scripts/check-rules.ps1" -RulesPath .context/reglas_proyecto.md -Path <entregable o carpeta> -Scope <ámbito>` y corregir hasta obtener código `0`.
  2. Si devuelve `ReviewRules` (reglas que no se pueden comprobar con un patrón), repetirlo con `-ReviewOut .context/revisiones/<entregable>.md`. Ese archivo lo revisa un **contexto limpio** (un subagente o un segundo pase sin el historial de redacción, leyendo solo las reglas y el entregable), que sustituye cada `PENDIENTE` por `PASA` o `FALLA` con una cita del entregable.
  3. Ejecutar con `-ReviewVerdictPath .context/revisiones/<entregable>.md` y corregir hasta obtener código `0`. Si cambia el entregable o las reglas, la revisión deja de valer (línea `Huella`) y hay que repetirla.
  4. Indicar al entregar que la compuerta pasó, incluida la revisión.
- **Ejemplo por regla:** al registrar una corrección, guardar en `- Ejemplo:` el texto que se rechazó. El verificador comprueba que `Detectar` lo detecta; en las reglas sin patrón, el ejemplo orienta la revisión.
- **Universal:** este protocolo se basa solo en archivos del proyecto y en un script de terminal. Se aplica igual en cualquier arnés de IA.
