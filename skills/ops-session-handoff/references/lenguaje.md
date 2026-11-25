# Lenguaje con el usuario (Protocolo 9)

Cómo hablarle a cada persona según su perfil. Se aplica a todo lo que lee el usuario: reportes, preguntas, resúmenes y cierres. No se aplica a lo que leen los agentes: `.context/`, mensajes de commit, registros y salidas de scripts siguen en lenguaje técnico y exacto, porque es lo que permite retomar el trabajo desde otra herramienta.

## Perfil
- Consultar: `& "$ActivePath/scripts/user-profile.ps1" -Action Get`. El perfil es de la persona, no del proyecto: vive en el estado privado del equipo y vale para todos sus proyectos.
- `AskInterview: true` → hacer la entrevista antes del reporte de MODO ENTRADA. Si no, usar `Register` sin preguntar.
- La persona puede cambiarlo cuando quiera («háblame más técnico», «más sencillo»): actualizar con `-Action Set` y confirmarlo en una línea.

## Entrevista (una sola vez por persona)
Una pregunta por mensaje, con opciones (la recomendada primero) y respuesta libre. Presentarla en una línea: «Antes de empezar, tres preguntas rápidas para hablarte en tu idioma. Puedes saltarlas.»
1. ¿A qué te dedicas principalmente? Marketing · Experiencia de usuario · Investigación de mercados · Desarrollo de software · Otro.
2. ¿Te resultan familiares palabras como «commit» o «push»? No (`none`) · Algunas (`some`) · Sí, trabajo con ellas (`fluent`).
3. ¿Qué prefieres que te cuente? Solo el resultado (`result`) · El resultado y los pasos principales (`steps`) · Todo el detalle (`full`).

Guardar: `user-profile.ps1 -Action Set -Role "<respuesta 1>" -TechFamiliarity <none|some|fluent> -Detail <result|steps|full>`. Si la persona prefiere saltarla: `-Action Set -Skipped` (lenguaje llano y solo el resultado; no se vuelve a preguntar).

## Registros
- `plain` (por defecto): lenguaje llano, sin términos técnicos. Solo se añade el término entre paréntesis cuando a la persona le sirve para actuar (por ejemplo, para hablar con un desarrollador o reconocer un botón).
- `bridged`: lenguaje llano con el término técnico entre paréntesis la primera vez que aparece: «guardé una versión (commit)».
- `technical`: términos técnicos directos.

## Principios
- Contar la consecuencia, no el mecanismo: qué cambia para la persona, si se puede deshacer y qué tiene que decidir.
- Las decisiones con efectos (subir cambios, publicar, borrar, volver atrás) se preguntan en llano, diciendo si tienen vuelta atrás.
- Nunca mostrar identificadores internos (códigos de versión, rutas de estado, `JournalId`) salvo en `technical` o si la persona los pide.
- Con `Detail: result`, un resumen de 2 o 3 frases; los pasos, solo si los pide.

## Glosario
Usar siempre la misma expresión llana para cada término, en cualquier herramienta.

| Término técnico | Expresión llana |
|---|---|
| repositorio (repo) | carpeta del proyecto con su historial |
| commit | guardar una versión |
| push | subir los cambios a la copia en internet |
| pull / fetch | traer los últimos cambios |
| main | versión principal |
| rama (branch) | copia de trabajo paralela |
| merge | unir los cambios |
| tag / etiqueta | marca de versión |
| release / publicar | publicar una versión nueva |
| CI | pruebas automáticas |
| stable | versión aprobada para instalar |
| SHA / hash | código de la versión (en `plain`, no mostrarlo) |
| diff | cambios hechos |
| rollback / revertir | volver atrás |
| conflicto (merge conflict) | dos cambios que chocan y hay que elegir |
| checkpoint | punto de control para retomar |
| changelog | registro de cambios |
| migración | poner el proyecto al día con la nueva versión del marco |
| skill | habilidad del asistente |
| script | herramienta automática |
| journal / RestoreRef | copia de seguridad para volver atrás (en `plain`, sin su identificador) |
| arnés (harness) | herramienta de IA (Claude, Codex, Gemini…) |

Ejemplo en `plain`: «Guardé tus cambios y los subí a la copia en internet. Se están ejecutando las pruebas automáticas; si pasan, te ofreceré instalar la versión nueva en este equipo.»

## Plantilla de espera (R-015)
«Las pruebas de [qué] están corriendo en segundo plano (faltan unos N min). Cuando terminen podré [lo bloqueado]. Mientras tanto puedo adelantar [A, la recomendada: qué aporta] o [B]. O, si prefieres, esperamos y sigo cuando terminen.»
