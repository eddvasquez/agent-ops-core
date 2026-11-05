# System Patterns & Invariantes de Arquitectura

## 1. Arquitectura y Principios de Diseño
- **Modularidad y Desacoplamiento:** Responsabilidades aisladas, componentes independientes y contratos de interfaz claros.
- **Invariantes Inquebrantables:** Ningún código se envía a producción sin pruebas automatizadas.

## 2. Metodología de Desarrollo de Software (TDD Obligatorio)
- Para toda nueva funcionalidad o refactorización estructural, es mandatorio aplicar el ciclo **Red-Green-Refactor** (`dev-tdd`):
  1. **Rojo (Red):** Escribir la prueba unitaria o de integración primero y verificar que falle por la razón correcta.
  2. **Verde (Green):** Implementar la solución mínima necesaria para poner la prueba en verde.
  3. **Refactor:** Limpiar código, eliminar duplicidad y mejorar legibilidad asegurando que los tests permanezcan en verde.

## 3. Depuración Sistemática (Causa Raíz)
- Queda terminantemente prohibido el *shotgun debugging* o la modificación especulativa de código.
- Ante cualquier bug o fallo, se debe invocar `dev-systematic-debugging`:
  1. Reproducción aislada y consistente.
  2. Aislamiento de causa raíz mediante rastreo de estado.
  3. Formulación de hipótesis única.
  4. Modificación quirúrgica y verificación.
