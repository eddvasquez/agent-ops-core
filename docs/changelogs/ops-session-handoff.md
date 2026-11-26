# Changelog: ops-session-handoff

Cambios relevantes de la skill `ops-session-handoff`. Formato [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/), versionado [SemVer](https://semver.org/lang/es/). Archivo de mantenimiento: no se carga al usar la skill.

## [Unreleased]

## [2.14.0] - 2026-11-26
### Added
- `references/aprendizaje.md`: sección 6 documentando el registro híbrido de uso (`record-usage.ps1`), la poda sin borrado con destinos `6` (`archivar`) y `7` (`fusionar`) (`prune-skills.ps1`) y el inspector de catálogo (`check-skill-catalog.ps1`).

## [2.13.0] - 2026-11-25
### Changed
- Esperas y trabajo en paralelo (R-018): nunca esperar pasivamente a que terminen pruebas o tareas en segundo plano; ofrecer siempre con botones qué siguiente tarea o diseño adelantar en paralelo (usando `ops-git-worktrees` si toca código).

## [2.12.0] - 2026-11-25
### Added
- Paso 0c de MODO ENTRADA: como mucho una pregunta de integración (permiso de Codex o arranque desactualizado), con botones y en lenguaje llano; se registra con `integrations.ps1` y, si todo va bien, no se dice nada.

## [2.11.0] - 2026-11-25
### Added
- Esperas largas (R-015): avisar una vez de qué corre y cuánto falta, y ofrecer esperar o adelantar una o dos tareas que no dependan del resultado; plantilla en `references/lenguaje.md`.
- Aceptación (R-016, R-017): contrato con la petición literal, criterios e invariantes (`acceptance.ps1`), revisión en contexto limpio con las reglas y fuentes del proyecto, el revisor solo juzga y nunca cambia la oferta, como mucho tres rondas.

## [2.10.0] - 2026-11-25
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
