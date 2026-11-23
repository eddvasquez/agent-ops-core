# Harness engineering frente a Agent Ops Core

Análisis del 2026-11-23, desde la perspectiva de un harness engineer de clase mundial.

**Fuentes:**
- Video «No necesitas un modelo de IA más potente, necesitas un harness» (transcripción aportada por el usuario).
- OpenAI, «Harness engineering» (feb. 2026).
- Anthropic, «Harness design for long-running apps» (mar. 2026).
- LangChain, «Improving deep agents with harness engineering» (feb. 2026).
- Endor Labs, «Agent Security League» (abr. 2026).
- Documentación oficial de hooks, settings y plugins de Codex, Antigravity y Claude Code (leída el 2026-11-23).

Las cifras son las que publica cada fuente y no se han verificado de forma independiente.

## Palabras que usa este documento
- **Harness (arnés):** todo lo que rodea al modelo de IA. Decide qué ve, qué puede hacer, dónde y cómo se comprueba su trabajo. El modelo pone la capacidad y el arnés decide cuánta llega a funcionar. Claude Code, Codex y Antigravity son arneses.
- **Hook:** un pequeño programa que el arnés ejecuta automáticamente en un momento fijo, por ejemplo antes de que el agente use una herramienta. Puede frenar al agente aunque este «se olvide» de una regla.
- **Commit:** guardar un cambio en el historial del proyecto.
- **CI:** las pruebas automáticas que corren en GitHub cada vez que se publica un cambio.
- **Sandbox:** un espacio cerrado donde el agente trabaja sin poder tocar el resto del ordenador.
- **Linter:** un programa que revisa el código o los textos y avisa cuando algo no cumple una norma.

## 1. Qué dicen las fuentes, en cinco ideas

1. **El harness pesa tanto como el modelo.**
   - LangChain subió de 52,8 % a 66,5 % en una prueba pública de tareas reales en la terminal (Terminal Bench) cambiando solo el arnés, con el mismo modelo.
   - Endor Labs probó el mismo GPT-5.5 en dos harnesses: resolvió bien el 87,2 % de las tareas en Cursor y el 61,5 % en Codex.
2. **El repositorio es la memoria y el AGENTS.md es un mapa, no un manual** (OpenAI).
   - Un AGENTS.md gigante falló: desorienta, se queda obsoleto y no se puede verificar.
   - Funcionó un índice de unas 100 líneas que remite a `docs/`.
3. **Las reglas se hacen cumplir con código, no con instrucciones** (OpenAI).
   - Programas que revisan cada cambio de forma automática detectan cuándo se incumple una norma, y el aviso le dice al agente cómo corregirlo.
   - La «basura» que dejan los agentes se limpia con tareas automáticas continuas.
4. **Quien construye no debe ser quien aprueba** (Anthropic y LangChain).
   - Los agentes elogian su propio trabajo y se detienen en la primera solución plausible.
   - Funciona separar al que hace del que evalúa, con umbrales duros, y acordar antes qué significa «terminado».
5. **Cada pieza del harness es una suposición sobre lo que el modelo no sabe hacer, y caduca** (Anthropic).
   - Con cada modelo nuevo se quitan piezas una a una y se mide el resultado.
   - Endor añade que la seguridad se mide aparte de la funcionalidad: el código que funciona no es necesariamente seguro.

## 2. Dos marcos para evaluar cualquier harness (del video)

**Guías y sensores.**
- Las guías actúan antes de que el agente trabaje: instrucciones, skills y plantillas.
- Los sensores actúan después: tests, hooks y revisores.
- Cada uno puede ser computacional (código: rápido y barato) o inferencial (otro modelo que juzga: flexible, más lento y más caro).
- Hacen falta los dos. Con solo guías, nunca sabes si el agente se las saltó.

**Escalera de cinco peldaños.** Se sube un peldaño solo cuando se ha visto fallar algo, y lo que no puede fallar va en código:
1. Instrucciones escritas (AGENTS.md).
2. Procedimientos fijos (skills).
3. Tests y hooks que bloquean.
4. Varios agentes con papeles distintos: uno planifica, otro construye y otro revisa.
5. Agentes autónomos con trazas, presupuesto y alertas.

| Peldaño o pieza | Agent Ops Core hoy |
|---|---|
| 1. Instrucciones | Sí, incluso en exceso: un AGENTS.md de 109 líneas en prosa |
| 2. Procedimientos (skills) | Sí, bien gobernados (techo de 25 skills y escalera de destinos) |
| 3. Sensores que bloquean | Solo al guardar cambios en el historial y en las pruebas automáticas de GitHub; durante la sesión nada frena al agente |
| 4. Papeles separados | Solo para revisar las reglas sin patrón (revisión en contexto limpio) |
| 5. Trazas, presupuesto y alertas | No existe |
| Memoria y estado | Fuerte: memoria en `.context/`, punto de control tras cada paso y retomar una sesión que se cortó |
| Permisos y sandbox | Los deja a cada arnés, sin una base común |

**Diagnóstico.** Agent Ops Core tiene muchas guías y pocos sensores. Por eso su cumplimiento depende de la buena fe del agente: de que decida llamar a los scripts. El propio repositorio lo muestra: `projectbrief.md` sigue siendo la plantilla vacía y `activeContext.md` acumula notas antiguas que se contradicen.

## 3. ¿Agent Ops Core es un harness?

**Sí, pero de una capa concreta.**
- Claude Code, Codex o Antigravity son el harness de ejecución: el bucle, las herramientas, la gestión del contexto y los hooks.
- Agent Ops Core es un **harness de entorno y gobernanza, portable entre arneses**. Cubre lo que OpenAI llama harness engineering a nivel de repositorio:
  - memoria versionada;
  - protocolos;
  - compuertas;
  - reanudación;
  - aprendizaje gobernado;
  - canal de versiones verificadas.
- Hasta el 2026-11-23, una regla le impedía intervenir mientras el agente trabaja. La enmienda de R-002 lo abre:
  - Antes: «No usar mecanismos propios de un arnés (hooks, settings, plugins), ni siquiera como adaptadores opcionales; el cumplimiento solo usa archivos del proyecto, skills y scripts de terminal.»
  - Después: «Se pueden usar hooks, settings o plugins de un arnés solo si Codex, Antigravity y Claude Desktop ofrecen un equivalente. La lógica vive en los scripts del marco; cada arnés solo la llama.»

## 4. Lo que Agent Ops Core ya hace bien

- **Memoria dentro del proyecto, y solo un agente escribe a la vez:** la carpeta `.context/`, un punto de control tras cada paso y la posibilidad de retomar una sesión que se cortó. Es el traspaso entre turnos que describe Anthropic.
- **Comprobaciones que frenan errores antes de guardar:** la herramienta de guardado del marco (`commit.ps1`) impide guardar archivos de más por descuido y revisa que cada cambio lleve su versión.
- **Un evaluador separado**, aunque solo para reglas: la revisión en contexto limpio del Protocolo 8.
- **Aprendizaje que convierte fallos en mejoras del entorno** (Protocolo 4), con freno a la acumulación de skills.
- **Versiones verificadas por CI**, con reversión.

## 5. Lo que los tres arneses permiten hacer por igual

En lenguaje llano, Claude Code, Codex y Antigravity permiten ejecutar automáticamente un programa del marco en cuatro momentos:
- **Al empezar la sesión:** por ejemplo, para preparar la sesión sin que el agente tenga que acordarse.
- **Antes de que el agente haga algo:** puede impedirlo, por ejemplo, leer contraseñas.
- **Después de que lo haga:** puede avisarle, por ejemplo, si está repitiendo lo mismo una y otra vez.
- **Cuando el agente quiere dar el trabajo por terminado:** puede obligarlo a seguir si faltan pruebas.

Los tres también permiten empaquetar estos programas en un complemento (plugin) y bloquear acciones con listas de permisos.

**Conclusión.** Se puede escribir cada comprobación una sola vez, en los scripts del marco, y que los tres arneses la llamen. Solo cambian el archivo donde se declara y el formato exacto de la respuesta.

**Pendiente de confirmar:**
- en Antigravity, qué ocurre si el programa falla o tarda demasiado;
- en Codex, si funciona también dentro del editor de código;
- en Claude Code, cómo se evita que el aviso de «no has terminado» se repita sin fin.

### Anexo técnico: equivalencias

Según la documentación oficial leída el 2026-11-23:

| Mecanismo | Claude Code (incl. escritorio) | Codex (CLI y app) | Antigravity (app, CLI, IDE) | ¿Común? |
|---|---|---|---|---|
| Hook al iniciar sesión | `SessionStart` | `SessionStart` | `SessionStart` (inyecta pasos) | **Sí** |
| Hook antes de una herramienta, con bloqueo | `PreToolUse` (deny o código 2) | `PreToolUse` (deny o código 2) | `PreToolUse` (`decision: "deny"`) | **Sí** |
| Hook después de una herramienta | `PostToolUse` (informa, no deshace) | `PostToolUse` (no deshace) | `PostToolUse` (no bloquea) | **Sí** |
| Hook al terminar, que obliga a seguir | `Stop` (block o código 2) | `Stop` (block crea un prompt de continuación) | `Stop` (`decision: "continue"`) | **Sí** |
| Tipo de handler | `command`, entre otros | `command`, `mcp_tool` | Solo `command` | **Sí** (`command`) |
| Hooks dentro de un plugin | `hooks/hooks.json` | `hooks/hooks.json` | `hooks.json` del plugin | **Sí** |
| Hooks del proyecto | `.claude/settings.json` | `.codex/hooks.json` (solo en proyectos de confianza) | `.agents/hooks.json` | Sí, pero en archivos distintos |
| Reglas de permisos (deny) | `permissions.deny` | `permissions.<perfil>.filesystem` (deny) | `permissions.deny` | Sí, con sintaxis distinta |
| Skills (`SKILL.md`) | Sí | Sí | Sí | **Sí** (ya se usa) |

Diseño que encaja con la R-002 enmendada: un script del marco por evento, con toda la lógica, y un adaptador mínimo por arnés que solo traduce la respuesta.

## 6. Cómo pasar de la buena fe al cumplimiento automático: tres capas

1. **En el historial del proyecto (Git), disponible ya en cualquier arnés:** cada vez que alguien intenta guardar un cambio, se ejecutan las mismas comprobaciones que hoy hace la herramienta de commit del marco. Así, nadie se las puede saltar guardando a mano.
2. **En los cuatro momentos comunes a los tres arneses:**
   - Al empezar: se prepara la sesión (MODO ENTRADA) sin depender del agente.
   - Al querer terminar: se comprueba que las pruebas pasaron y que el punto de control está al día.
   - Después de cada acción: se detecta si el agente está en bucle.
   - Antes de cada acción: se bloquea lo peligroso, como leer contraseñas.
3. **En las pruebas automáticas de GitHub:** la última red para lo que no se comprobó en el equipo.

## 7. Oportunidades de mejora

| # | Oportunidad | Evidencia | Idea concreta | Esfuerzo |
|---|---|---|---|---|
| 0 | Peldaño «comprobación automática» en el aprendizaje | La escalera del Protocolo 4 solo produce texto | Cada corrección que no debe repetirse se convierte, si se puede, en una comprobación automática y no solo en una regla escrita | Bajo |
| 0b | Base común de permisos y presupuesto | No hay límites comunes | Impedir en los tres arneses que el agente lea contraseñas y avisar cuando una sesión supera un número máximo de pasos | Medio |
| 1 | Pruebas verificadas, no autodeclaradas | El Protocolo 3 confía en lo que el agente anota | Ejecutar de verdad las pruebas y guardar el resultado; sin esa evidencia no se puede guardar el cambio ni dar el trabajo por terminado | Medio |
| 2 | Higiene automática de la memoria | Plantilla vacía y notas contradictorias en `.context/` | Una revisión automática al empezar y al cerrar cada sesión que avise de lo vacío o desactualizado y diga cómo arreglarlo | Bajo |
| 3 | AGENTS.md como mapa | 109 líneas de prosa normativa | Un índice corto (40 a 60 líneas) que remita a documentos de detalle, que el agente lee solo cuando los necesita | Medio |
| 4 | Evaluador separado para entregables | El contexto limpio solo revisa reglas | Antes de empezar, escribir qué significa «terminado»; al final, otro agente que no participó decide si pasa o falla | Medio |
| 5 | Errores que enseñan a corregirse | Las incidencias no siempre dicen qué hacer | Cada aviso de los scripts incluye la acción exacta para corregirlo, y una prueba automática lo exige | Bajo |
| 6 | Seguridad mínima en todos los proyectos | El escaneo de secretos solo existe en la publicación de versiones | Buscar contraseñas y claves filtradas en cada cambio que se guarda, y antes de cada acción del agente | Bajo-medio |
| 7 | Aprender de las trazas | El marco ya lee las conversaciones pasadas, pero solo para recuperar indicaciones del usuario | Detectar patrones de fallo en la revisión semanal y enviarlos a la bandeja de aprendizaje | Medio |
| 8 | Detección de bucles | No existe | Avisar al agente cuando repite el mismo paso o edita el mismo archivo muchas veces | Bajo |
| 9 | Quitar piezas del arnés con cada modelo nuevo | No hay un ritual para quitar piezas | En la revisión semanal, revisar qué pieza ya no aporta; quitar una por vez | Bajo |
| 10 | Medir el propio marco | No hay evaluaciones del marco | Tareas repetibles para comparar arnés y modelo, con y sin el marco | Alto |

**Orden recomendado:**
1. Primero, el cumplimiento automático: la comprobación al guardar cambios y luego los cuatro momentos comunes.
2. Conectar a esos hooks las mejoras 1, 8 y 0b.
3. Después, las mejoras 2 y 5 (baratas).
4. Luego, la 3 y la 4.
5. La 10, solo cuando las anteriores estén estables.
