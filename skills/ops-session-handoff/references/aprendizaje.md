# Aprendizaje gobernado (Protocolo 4)

Se lee en MODO SALIDA y en la revisión semanal. Nada de esto modifica una skill sin la decisión del usuario.

## 1. Capturar (en el momento, sin interrumpir)
Señales: `correccion` del usuario, `fallo` de una skill (se quedó corta, faltaba un paso), `patron` repetido sin skill que lo cubra, `exito` reutilizable.

```powershell
& "$ActivePath/scripts/capture-learning.ps1" -Signal patron -Project "<proyecto>" -Harness "<arnés>" -Summary "<una línea>" -Evidence "<qué pasó, dónde y cuándo>" [-Skill <skill del hub>]
```

La candidata queda en `<hub>/proposals/inbox/`. Las skills de terceros no reciben candidatas (`SKILL_NOT_IN_HUB`): su mejora es un complemento propio en el hub.

## 2. Triar: escalera de destinos
Cada candidata sube solo hasta el primer peldaño que la resuelve:
1. **Nada:** el modelo ya lo hace bien razonando, o fue un caso aislado. Se descarta con motivo.
2. **Regla de proyecto** (`reglas_proyecto.md`, Protocolo 8): vale para un proyecto o cliente.
3. **Parche** a una skill existente: una línea o un paso en su dominio.
4. **Referencia** dentro de una skill: detalle que solo se lee cuando hace falta.
5. **Skill nueva**, solo con las cuatro condiciones a la vez:
   - repetida en al menos dos proyectos o tres sesiones distintas;
   - evidencia antes y después de que el modelo lo hace peor sin ella;
   - no cabe como parche o referencia de una skill existente;
   - su descripción no se solapa con la de otra skill.
   Con 25 skills activas en el hub, crear exige fusionar o archivar otra.

Agrupar candidatas del mismo tema: la recurrencia entre proyectos es la evidencia más fuerte.

## 3. Fichar
Una ficha por propuesta en `<hub>/proposals/pending/<id>.md`:

```markdown
# Propuesta <id>

- Destino: 3
- Skill: <nombre>
- Versión: 1.4.2 -> 1.5.0
- Riesgo: bajo
- Tamaño: +4 -1
- Descripción nueva: <solo si cambia; 300 caracteres como máximo>

## Por qué
## Evidencia
## Cambio
### Bloque 1
(diff exacto; cada bloque se aprueba por separado)
## Validación
(obligatoria con riesgo medio o alto: prueba antes y después)
## Solapamientos
(skills o reglas que tocan lo mismo, contradicciones; «Ninguno» si no hay)
## Alternativas descartadas
## Umbral
(solo destino 5: las cuatro condiciones como `- [x]`)
## Fusión o archivo
(solo destino 5 con el techo alcanzado)
```

Antes de presentarla: `& "$ActivePath/scripts/check-proposal.ps1" -Path <ficha>` debe devolver código `0`. Proponer parches pequeños por bloque; nunca reescribir una skill entera.

## 4. Decidir
- **Al cierre de sesión:** solo las fichas de riesgo bajo surgidas en la sesión; el usuario puede aplazarlas.
- **Revisión semanal:** el resto y lo aplazado, en lote. Como máximo un lote de cambios por skill a la semana.
- Por cada bloque: aprobar, ajustar, rechazar o aplazar. Lo rechazado se mueve a `proposals/rejected/` con su motivo, para no volver a proponerlo igual.

## 5. Aplicar
Solo los bloques aprobados, en el hub: subir la versión SemVer de la skill, añadir la línea en `changelogs/<skill>.md` y hacer commit con `commit.ps1` (o `apply-proposal.ps1`). Mover la ficha a `proposals/applied/`. Propagar a máquinas y arneses (`sync-skills.ps1`) se confirma aparte.

## 6. Uso, poda y salud del catálogo (Fase 3)
- **Destilación silenciosa al cierre:** ejecuta `& "$ActivePath/scripts/session-distill.ps1" -ProjectPath <proyecto> -CaptureToInbox` en MODO SALIDA; si devuelve `QUIET`, no interrumpas al usuario. Si hay `LowRiskReview`, preséntalo para aprobación por bloque.
- **Uso en MODO SALIDA:** Claude Code registra llamadas `Skill` automáticamente en segundo plano; en cualquier arnés, usa `record-usage.ps1 -Skill <nombre> -Project "<proyecto>" -Outcome helped|hurt` para calificar si ayudó o perjudicó, o `-SyncFromTranscripts` para sincronizar trazas locales hacia `<hub>/proposals/usage.jsonl`.
- **Poda trimestral (90 días sin uso o `hurt` repetido):** `prune-skills.ps1 -EmitProposals` genera fichas con destino `6` (`archivar` en `proposals/archived/<skill>/`, sin borrar nunca) o `7` (`fusionar`), protegiendo las 6 skills núcleo y `always_keep: true`.
- **Salud del catálogo:** `check-skill-catalog.ps1` revisa techo (`25`), largo de descripción (`<= 300` aviso, `> 1024` error), cuerpo (`<= 500` líneas), presupuesto del listado y solapamientos (Jaccard y Contención).
