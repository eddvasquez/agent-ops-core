# Reglas del proyecto

Fuente de verdad de las correcciones, prohibiciones y requisitos de este proyecto (Protocolo 8 de `AGENTS.md`). Se aplica a **todas** las piezas del proyecto (landing, anuncios, correos, guiones, código…) salvo que una regla indique otro ámbito. `lessons_learned.md` es el historial; este archivo es lo que se cumple.

## Cómo se mantiene
- Cada corrección del usuario o del cliente se registra **en el mismo turno**, antes de seguir trabajando, como una regla nueva. El agente lo confirma en una línea: "Registrada R-NNN: …".
- Se redacta como regla del proyecto, no del entregable: "No afirmar X", no "quitar X del hero".
- Solo se añade, modifica o retira la regla afectada, por su ID. Nunca se reescribe el archivo entero.
- Para dejar de aplicar una regla, cambia `[estado: activa]` por `[estado: retirada]` y anota el motivo. No se borra.
- Formato de cada regla:

```
### R-001 [tipo] [ámbito: todas] [estado: activa]
- Regla: descripción en una línea.
- Motivo: por qué existe.
- Origen: quién la pidió y cuándo (AAAA-MM-DD).
- Detectar: "expresión vetada"; "re:expresión\s+regular"
- Exigir: "texto que debe aparecer"
- Ejemplo: "texto que el usuario o el cliente rechazó"
```

- Tipos: `expresion-vetada`, `prohibido-afirmar`, `dato-obligatorio`, `tono`, `formato`, `otro`.
- Ámbito: `todas`, o una lista separada por comas, por ejemplo `landing, anuncios`.
- `Detectar` y `Exigir` son opcionales. Con ellos, el verificador `check-rules.ps1` controla la regla automáticamente: ignora mayúsculas y tildes y compara palabras completas. Sin ellos, la regla pasa a la revisión semántica de un contexto limpio antes de entregar.
- `Ejemplo` (opcional, recomendado) guarda el texto original que se rechazó. Si la regla tiene `Detectar`, el verificador exige que lo detecte; si no, el ejemplo orienta la revisión.

## Reglas activas

<!-- Añade aquí las reglas. -->
