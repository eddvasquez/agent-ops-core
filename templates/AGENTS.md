# Protocolo de Operación de Agentes (Arquitectura v2 Universal)

Todo agente o modelo de Inteligencia Artificial (Claude Code, Antigravity/Gemini, OpenAI Codex, ChatGPT Desktop, Hermes o cualquier otro arnés que trabaje con proyectos locales) que opere en este repositorio debe cumplir de forma estricta e innegociable con los siguientes protocolos:

---

### Protocolo 1 (Inicio de Sesión y Auditoría Git - MODO ENTRADA)
- Al iniciar cualquier turno sobre el proyecto, es mandatorio invocar la skill `ops-session-handoff` (o `ops-gestion-relevo`) bajo **MODO ENTRADA**.
- En Windows, su Paso 0 comprueba el canal estable mediante el punto de entrada instalado. Si hay una candidata verificada, presentar versión, cambios y estimación y respetar la elección de actualizar ahora, preparar para la próxima sesión o posponer. Esta decisión autoriza únicamente la actualización del marco global, no cambios en los archivos del proyecto. No sustituir el mecanismo por un `git pull` directo.
- Lee `AGENTS.md`, todos los archivos de `.context/` (`projectbrief.md`, `systemPatterns.md`, `activeContext.md`, `progress.md`, `lessons_learned.md`, `reglas_proyecto.md`) y las skills disponibles en tus aplicaciones de IA.
- Ejecuta una auditoría física en Git (`git status -s`, `git log -n 3 --oneline`, `git diff --stat`).
- **Resolución de discrepancias:** En caso de existir cualquier contradicción entre el texto de `.context/activeContext.md` y el estado real del árbol de trabajo en Git, **prevalece siempre la evidencia física de Git**.
- **Reanudación en frío:** `& "$ActivePath/scripts/resume-session.ps1" -ProjectPath <proyecto>` indica si la sesión anterior se cortó (`INTERRUPTED`) y su siguiente paso exacto. En ese caso se retoma desde ahí y se completa su MODO SALIDA pendiente.
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
- **Skills críticas, criterio del 1 %:** si existe cualquier posibilidad (≥ 1 %) de que apliquen, se invocan y se lee su `SKILL.md` antes de actuar:
  - `dev-tdd` ante cualquier cambio en algo que se ejecuta: código nuevo o existente, refactors, scripts, automatizaciones y configuración que cambia el comportamiento (CI, build). Prohibido escribir o modificar código sin una prueba previa que haya fallado por la razón correcta.
  - `dev-systematic-debugging` ante cualquier error, prueba roja o comportamiento inesperado. Prohibido el *shotgun debugging* (parchear a ciegas o modificar código especulativamente).
  - Las que el proyecto declare en `reglas_proyecto.md` como «Skill crítica: X, cuando Y».
- **Sin excepciones:** ni «cambio pequeño», ni «es una línea», ni prisa. Solo el usuario puede eximir un cambio concreto, y la exención se anota en `activeContext.md`.
- **Verificación antes del commit:** las suites que cubren lo modificado se ejecutan y deben estar en verde; si no existen, se escriben antes. El resultado (suite y n.º de pruebas) se anota en `activeContext.md`. Las pruebas crean sus archivos temporales en una carpeta propia y la borran al terminar en verde; si fallan, la conservan para revisar el fallo y se borra sola después.
- **Nunca esperar pasivamente:** cuando se lancen pruebas o tareas en segundo plano, ofrecer siempre en ese mismo turno con botones qué siguiente tarea o diseño adelantar en paralelo (usando `ops-git-worktrees` si toca código mientras corren pruebas).
- **Resto de skills, criterio de dominio:** son obligatorias cuando la tarea entra en el dominio que declara su descripción. Fuera de él se razona sin forzarlas: una skill mal aplicada también empeora el resultado.

---

### Protocolo 4 (Aprendizaje Gobernado de Skills)
- Está estrictamente prohibido modificar o crear archivos dentro de carpetas de skills sin la autorización humana explícita.
- **Capturar:** lo reutilizable fuera del proyecto (correcciones del usuario, fallos de una skill, patrones repetidos, éxitos) se anota en el momento con `& "$ActivePath/scripts/capture-learning.ps1"`, que lo guarda en la bandeja del hub sin tocar ninguna skill. Observa cada corrección durante la sesión (qué falló → corrección → verificación) y destílala en `MODO SALIDA` con `& "$ActivePath/scripts/session-distill.ps1"` (silencioso si no hubo señal; bloquea secretos y anonimiza datos privados antes de salir del proyecto).
- **Destino más ligero:** cada candidata va al primer peldaño que la resuelve: nada; regla de proyecto (Protocolo 8); parche a una skill existente; referencia dentro de una skill. Una skill nueva exige las cuatro condiciones del umbral (repetida en al menos dos proyectos o tres sesiones, evidencia antes y después, no cabe en una existente, sin solapamiento) y, con 25 skills activas, fusionar o archivar otra.
- **Decidir:** cada propuesta se presenta como ficha validada (`check-proposal.ps1` con código `0`) con el cambio en bloques. El usuario aprueba, ajusta, rechaza o aplaza cada bloque; solo lo aprobado se aplica, con SemVer y changelog, y propagarlo a los arneses se confirma aparte. Nunca reescribir una skill entera. Procedimiento: `references/aprendizaje.md` de `ops-session-handoff`.

---

### Protocolo 5 (Escritor Único e Higiene en Almacenamiento Cloud)
- **Principio de escritor único:** Validar que el campo `Agente Activo` en `.context/activeContext.md` coincida con la plataforma actual antes de efectuar escrituras.
- **Prohibición de duplicados:** Estrictamente prohibido crear archivos con sufijos de versionado (`_v01`, `_v2`, `_final`, `_WIP`, `_backup`). Toda iteración se versiona exclusivamente mediante commits atómicos de Git.
- **Higiene en carpetas sincronizadas:** Advertir y solicitar confirmación previa antes de instalar dependencias masivas locales (`node_modules/`, `.venv/` o descargas pesadas) para no saturar la sincronización en la nube.

---

### Protocolo 6 (Cierre de Turno / Handoff - MODO SALIDA)
- Al concluir cualquier unidad de trabajo o antes de devolver el control al usuario, el agente debe ejecutar obligatoriamente `ops-session-handoff` (o `ops-gestion-relevo`) bajo **MODO SALIDA**.
- **Punto de control por paso:** la sesión puede cortarse sin aviso (cuota, contexto, cierre). Tras cada paso del plan, `& "$ActivePath/scripts/checkpoint.ps1"` registra lo hecho, el siguiente paso exacto y, con `-Request`, la petición literal del usuario, sin hacer commit. Así cualquier arnés con terminal puede retomar, tenga o no lector de conversaciones. Si el arnés muestra que la cuota baja de ~10 %, no se empiezan pasos nuevos: se hace el MODO SALIDA MÍNIMO (`checkpoint.ps1 -Close` y commit de relevo de `.context/`).
- Actualizar `.context/lessons_learned.md` si hubo aprendizajes o correcciones.
- Capturar los aprendizajes reutilizables fuera del proyecto y presentar las fichas de riesgo bajo de la sesión (Protocolo 4); el resto espera a la revisión semanal.
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
- **Despliegues fuera de Git** (WordPress en vivo, GTM, Google Ads, Kiral…): registrar en `CHANGELOG.md` la versión desplegada, el destino, la fecha y la verificación; si se publica una carpeta web o estática, pasar antes `& "$ActivePath/scripts/check-deploy.ps1" -Path <carpeta>`. Sin entrada ni verificación no hay despliegue.
- **Lectura del changelog:** solo al editar el artefacto (`[Unreleased]` y la última versión) o al auditar diferencias entre versiones. No forma parte de MODO ENTRADA.
- **Verificación:** `& "$ActivePath/scripts/check-versioning.ps1" -RepositoryPath <repo>` debe devolver código `0` antes de cada commit; en CI, con `-Base <commit anterior> -Head <commit>`.

---

### Protocolo 8 (Reglas del Proyecto y Compuerta de Cumplimiento)
- **Fuente de verdad:** `.context/reglas_proyecto.md` reúne las correcciones, prohibiciones y requisitos del proyecto y de su cliente. Prevalece sobre las skills, sobre ejemplos anteriores y sobre lo que se recuerde de la conversación. `lessons_learned.md` es solo el historial.
- **Captura inmediata:** cuando el usuario corrija, rechace o pida eliminar algo, registrar la regla **en ese mismo turno, antes de continuar**, y confirmarlo en una línea con el texto literal de la regla (`Registrada R-NNN: «…»`). Si no queda escrita, la corrección no existe para la próxima conversación.
- **Citar con el texto literal:** al nombrar una regla en un mensaje o en un archivo (reportes, `activeContext.md`, lecciones, commits), la primera vez se cita literal su línea `Regla:` (`R-NNN: «…»`); después basta el ID. Las enmiendas se muestran como antes → después de esa línea. La línea `Regla:` se mantiene en unas 40 palabras como máximo y los matices van en `Motivo:` o `Nota:`; `check-rules.ps1` avisa en `Warnings` de las que se pasan.
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

---

### Protocolo 9 (Recepción de Solicitudes: Perspectiva y Entrevista)
- **Cuándo:** solo ante solicitudes sustanciales (entregables, diseños, estrategias, decisiones o encargos ambiguos). Nunca ante confirmaciones, respuestas cortas, correcciones puntuales o tareas mecánicas.
- **Perspectiva profesional:** si el usuario ya citó uno o varios profesionales en la conversación, responder con los que encajan con la nueva solicitud, en su versión de clase mundial y sin volver a preguntar; preguntar solo si ninguno encaja. Si no citó ninguno, preguntar primero desde qué perspectiva responder: 2–3 perfiles de clase mundial pertinentes (el más adecuado primero, cada uno con una línea sobre qué aporta), con selección múltiple, «Sin perspectiva profesional» y respuesta libre.
- **Varias perspectivas:** como máximo 4 por respuesta; si hay más pertinentes, usar las 4 más relevantes. La respuesta es una síntesis integrada con la recomendación final, que señala dónde discrepan los profesionales y por qué se eligió una postura. Si el usuario cambia el panel («ahora solo desde B», «añade a E»), el cambio rige para el resto de la sesión.
- **Entrevista opcional:** después, ofrecer «hacerte todas las preguntas necesarias para entender a fondo la solicitud y darte la mejor respuesta posible». Si acepta, preguntar una a una, cada pregunta con opciones (la recomendada primero) y respuesta libre, nunca en bloque. Cada pregunta se entiende sola.
- **Memoria:** ambas elecciones valen para toda la sesión. Si el usuario dice «siempre» o «nunca», registrarlo como regla en `reglas_proyecto.md` (Protocolo 8) y no volver a ofrecerlo.
- **Transparencia:** con perspectiva activa, indicarlo en una línea al inicio de la respuesta, con las perspectivas activas y las excluidas («Perspectivas: A, B y C de clase mundial (D no aplica a esta solicitud)»). El rol eleva el criterio y el rigor; nunca inventa credenciales, experiencias ni datos.
- **Universal:** usar la herramienta de preguntas del arnés si existe; si no, texto con opciones numeradas y una opción «Otra». Una pregunta por mensaje.
- **Lenguaje según la persona:** hablar a cada usuario según su perfil (`& "$ActivePath/scripts/user-profile.ps1" -Action Get`). Por defecto, lenguaje llano: contar consecuencias y no mecanismos, y poner el término técnico entre paréntesis solo si le sirve para actuar («guardé una versión (commit)»). El perfil se pregunta una sola vez por persona en MODO ENTRADA (máximo 3 preguntas, se pueden saltar), se guarda en el equipo y no en el proyecto, y vale para todos sus proyectos. Lo que leen los agentes (`.context/`, commits, salidas de scripts) sigue siendo técnico. Glosario y pautas: `references/lenguaje.md` de `ops-session-handoff`.
