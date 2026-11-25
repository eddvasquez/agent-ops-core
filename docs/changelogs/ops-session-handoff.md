# Changelog: ops-session-handoff

Cambios relevantes de la skill `ops-session-handoff`. Formato [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/), versionado [SemVer](https://semver.org/lang/es/). Archivo de mantenimiento: no se carga al usar la skill.

## [Unreleased]
### Added
- MODO SALIDA: publicar por hitos terminados; tras el push, esperar a GitHub en segundo plano con `wait-ci.ps1` en lugar de quedarse mirando (R-013).
- MODO SALIDA, en el repositorio de Agent Ops Core: tras guardar una versión terminada, `publish-local.ps1` la prueba en las dos versiones de PowerShell y la instala en este PC para todos los proyectos (R-014).

## [2.9.0] - 2026-11-24
### Added
- MODO ENTRADA ejecuta el sensor de higiene del proyecto y menciona sus hallazgos en el reporte, sin borrar ni guardar nada sin la aprobación del usuario.

## [2.8.0] - 2026-11-24
### Added
- «evalúa X» usa `harness-radar.ps1 -Action Evaluate` y se cierra con `-Action Ack -Report`, que exige veredicto; `-Action Coverage` resume lo aprovechado de cada arnés.

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
