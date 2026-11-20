# Changelog: ops-session-handoff

Cambios relevantes de la skill `ops-session-handoff`. Formato [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/), versionado [SemVer](https://semver.org/lang/es/). Archivo de mantenimiento: no se carga al usar la skill.

## [Unreleased]

## [2.2.0] - 2026-11-20
### Added
- MODO ENTRADA, Paso 2: `resume-session.ps1` detecta una sesión cortada (`INTERRUPTED`/`DIVERGED`) y su siguiente paso exacto. Quien recibe completa el MODO SALIDA pendiente.
- Punto de control por paso con `checkpoint.ps1` y MODO SALIDA MÍNIMO cuando la cuota visible baja de ~10 %. MODO SALIDA cierra el checkpoint antes del commit de relevo.

## [2.1.0] - 2026-11-20
### Changed
- MODO ENTRADA: las skills críticas (`dev-tdd`, `dev-systematic-debugging` y las que declare el proyecto) vuelven al criterio del 1 %; el resto mantiene el criterio de dominio.
- MODO SALIDA: el estado de pruebas registra las suites ejecutadas, su n.º de pruebas y las exenciones concedidas por el usuario.

## [2.0.0] - 2026-11-20
### Added
- MODO SALIDA: captura de aprendizajes reutilizables y presentación de las fichas de riesgo bajo de la sesión; procedimiento completo en `references/aprendizaje.md`, que solo se lee al cerrar.
- MODO ENTRADA: aviso de una línea si hay fichas de aprendizaje pendientes (`learning-queue.ps1`).
### Changed
- **BREAKING:** una skill es obligatoria cuando la tarea entra en el dominio que declara su descripción, en lugar de con cualquier probabilidad de ayudar (Protocolo 3).

## [1.4.0] - 2026-11-19
### Added
- MODO SALIDA: los entregables deben existir como archivos y pasar la revisión semántica cuando hay reglas sin patrón.
- MODO SALIDA: red de seguridad opcional con `harvest-instructions.ps1` para detectar indicaciones de la sesión que no se registraron.
### Changed
- MODO ENTRADA, Paso 0: `BUSY` tras «Actualizar ahora» se reintenta sin volver a preguntar, porque la aprobación se conserva.

## [1.3.0] - 2026-11-19
### Added
- Paso 0b de MODO ENTRADA: si el proyecto no está al día con la versión activa, muestra qué cambiaría y ofrece Migrar ahora / Más tarde / No para esta versión, con garantía de reversión.

## [1.2.0] - 2026-11-19
### Changed
- MODO SALIDA hace los commits con `commit.ps1` (rutas explícitas, mensaje por archivo, parada en el primer fallo) y solo hace push si los commits devolvieron código 0.

## [1.1.0] - 2026-11-19
### Changed
- MODO ENTRADA lee `reglas_proyecto.md` y lista sus reglas activas en el reporte; MODO SALIDA comprueba que toda corrección de la sesión quedó registrada como regla y que los entregables pasaron `check-rules.ps1` (Protocolo 8).
- MODO SALIDA verifica el Protocolo 7 con `check-versioning.ps1` y separa el commit funcional del de relevo.
- Sustituye `git add .` por staging selectivo con rutas explícitas.

## [1.0.0] - 2026-11-18
### Added
- Línea base versionada (estado publicado en `e5eb4d1`).
