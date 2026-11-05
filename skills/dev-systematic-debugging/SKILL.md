---
name: dev-systematic-debugging
description: Metodología determinista de 4 fases para investigar y resolver bugs, fallos y comportamientos inesperados sin conjeturas, parches a ciegas ni modificaciones especulativas.
triggers:
  - "dev-systematic-debugging"
  - "depurar"
  - "debug"
  - "resolver bug"
  - "investigar error"
  - "fallo en ejecucion"
  - "analisis causa raiz"
---

# Skill: Depuración Sistemática (Causa Raíz)

## Propósito y Filosofía
Esta skill gobierna la resolución de cualquier error, fallo en pruebas o comportamiento anómalo del software.
- **Regla de oro:** Queda terminantemente prohibido el "shotgun debugging" (aplicar parches intuitivos, modificar código a ciegas o cambiar múltiples variables esperando que el fallo desaparezca).
- **Principio de evidencia:** Todo cambio debe estar fundamentado en una causa física identificada y confirmada mediante reproducción previa.

---

## PROCEDIMIENTO DETERMINISTA DE 4 FASES

### FASE 1: REPRODUCCIÓN MÍNIMA DETERMINISTA
Antes de tocar una sola línea de código en el proyecto:
1. **Aislar el escenario:** Identificar los datos de entrada exactos, variables de entorno, argumentos de línea de comandos o estado del sistema que desencadenan el fallo.
2. **Crear el arnés de reproducción:**
   - Construir una prueba automatizada o un script mínimo (en carpeta de scratch o tests) que falle de forma consistente (100% reproducible).
   - Ejecutar el reproductor y registrar la salida completa, código de salida y stack trace.
3. **Criterio de salida de Fase 1:** No avanzar a la Fase 2 si el fallo es intermitente o no se ha reproducido de manera aislada.

---

### FASE 2: AISLAMIENTO Y DIAGNÓSTICO DE CAUSA RAÍZ
1. **Rastrear la pila hacia atrás:**
   - No asumir que el error está en la línea que lanza la excepción. Inspeccionar el flujo de llamadas desde el origen del dato hasta el punto de fallo.
2. **Inspección de estado:**
   - Añadir logs temporales específicos o inspeccionar valores en tiempo de ejecución.
   - Determinar exactamente qué invariante o suposición se violó (e.g., tipo de dato inesperado, valor `None`/`null`, condición de carrera, codificación de caracteres, ruta inexistente).
3. **Diferenciar síntoma de causa:**
   - Si una función recibe `None`, capturar el `None` no es la solución si la función anterior debía retornar un objeto válido. Reparar la fuente del dato, no ocultar el síntoma con un bloque `try/catch` vacío o un `if` defensivo injustificado.

---

### FASE 3: FORMULACIÓN DE HIPÓTESIS Y CAMBIO QUIRÚRGICO
1. **Una sola hipótesis por ciclo:**
   - Formular explícitamente: *"Si modifico X en el archivo Y para manejar Z, la prueba de reproducción pasará porque..."*.
2. **Edición mínima indispensable:**
   - Modificar únicamente el bloque de código estrictamente necesario para corregir la causa raíz.
   - Prohibido refactorizar módulos adyacentes, renombrar variables no relacionadas o cambiar estilos de código durante la corrección de un bug.

---

### FASE 4: VERIFICACIÓN Y NO-REGRESIÓN
1. **Comprobar la corrección:**
   - Ejecutar el arnés de reproducción creado en la Fase 1. Debe pasar limpiamente (en verde).
2. **Comprobar la no-regresión:**
   - Ejecutar la suite de pruebas completa del proyecto o módulo afectado para asegurar que la corrección no rompió funcionalidades colaterales.
3. **Limpieza:**
   - Eliminar cualquier log de depuración temporal o código de diagnóstico añadido durante la investigación.
4. **Documentación:**
   - Si el bug se debió a un malentendido de la plataforma, registrar la lección aprendida en `.context/lessons_learned.md`.
