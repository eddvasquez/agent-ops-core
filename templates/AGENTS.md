# Protocolo de Operación de Agentes (Arquitectura v2 Universal)

Todo agente o modelo de Inteligencia Artificial (Claude Code, Antigravity/Gemini, OpenAI Codex, ChatGPT Desktop) que opere en este repositorio debe cumplir de forma estricta e innegociable con los siguientes protocolos:

---

### Protocolo 1 (Inicio de Sesión y Auditoría Git - MODO ENTRADA)
- Al iniciar cualquier turno sobre el proyecto, es mandatorio invocar la skill `ops-gestion-relevo` bajo **MODO ENTRADA**.
- Lee `AGENTS.md`, todos los archivos de `.context/` (`projectbrief.md`, `systemPatterns.md`, `activeContext.md`, `progress.md`, `lessons_learned.md`) y las skills disponibles en tu arnés activo.
- Ejecuta una auditoría física en Git (`git status -s`, `git log -n 3 --oneline`, `git diff --stat`).
- **Resolución de discrepancias:** En caso de existir cualquier contradicción entre el texto de `.context/activeContext.md` y el estado real del árbol de trabajo en Git, **prevalece siempre la evidencia física de Git**.
- Emite el reporte de sincronización de 5 puntos y **detente a esperar la confirmación explícita del usuario** antes de tocar archivos o escribir código.

---

### Protocolo 2 (Cero Suposiciones y Memoria Cruda)
- Está terminantemente prohibido adivinar requerimientos, suponer dependencias o inventar credenciales.
- Cuando falte información crítica o existan ambigüedades, formula preguntas concisas y bloqueantes.
- Toda corrección, rechazo de enfoque o directriz permanente expresada por el usuario debe registrarse de inmediato en `.context/lessons_learned.md` con fecha, error original y regla corregida.

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
- Al concluir cualquier unidad de trabajo o antes de devolver el control al usuario, el agente debe ejecutar obligatoriamente `ops-gestion-relevo` bajo **MODO SALIDA**.
- Actualizar `.context/lessons_learned.md` si hubo aprendizajes o correcciones.
- Actualizar `.context/progress.md` marcando con `[x]` **únicamente hitos comprobados objetivamente** mediante pruebas ejecutadas en verde o verificación física.
- Actualizar `.context/activeContext.md` indicando con precisión quirúrgica: último archivo modificado, estado de revisión/errores y el siguiente paso ejecutable inmediato para el próximo relevo.
- Realizar el commit atómico de relevo: `git add .` -> esperar 1 segundo para liberar bloqueos en nube -> `git commit -m "chore(relevo): actualizar activeContext y progreso de sesion"`.
- *Una vez actualizado activeContext y efectuado el commit, el agente no debe ejecutar código adicional en ese turno.*
