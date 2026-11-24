# Changelog: ops-session-handoff

Cambios relevantes de la skill `ops-session-handoff`. Formato [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/), versionado [SemVer](https://semver.org/lang/es/). Archivo de mantenimiento: no se carga al usar la skill.

## [Unreleased]

## [2.7.0] - 2026-11-24
### Added
- MODO ENTRADA explica cómo marcar vistos los cambios de documentación del radar (-Source), además de las versiones nuevas o instaladas.

## [2.6.1] - 2026-11-23
### Fixed
- MODO ENTRADA solo muestra el radar de arneses a quien mantiene Agent Ops Core, dentro de su repositorio.

## [2.6.0] - 2026-11-23
### Added
- MODO ENTRADA ejecuta el radar de arneses y muestra sus novedades en el reporte; «evalúa X» produce un informe con veredicto y marca la novedad como vista.

## [2.5.0] - 2026-11-23
### Added
- Paso 0a de MODO ENTRADA: perfil de lenguaje de cada persona (entrevista única de 3 preguntas como máximo, que se puede saltar) y guía `references/lenguaje.md` con glosario de términos técnicos en lenguaje llano. Por defecto, los mensajes al usuario van en lenguaje llano.

## [2.4.0] - 2026-11-23
### Changed
- El reporte de entrada y el relevo citan cada regla con el texto literal de su línea `Regla:`, no solo su ID, para entenderla sin abrir `reglas_proyecto.md`.

## [2.3.0] - 2026-11-20
### Added
- Punto de control por paso con `-Request`, la petición literal del usuario, para retomar desde cualquier arnés con terminal. La reanudación devuelve `UserRequests` y lee también Antigravity.

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
