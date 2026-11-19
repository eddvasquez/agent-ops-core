# Changelog: ops-session-handoff

Cambios relevantes de la skill `ops-session-handoff`. Formato [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/), versionado [SemVer](https://semver.org/lang/es/). Archivo de mantenimiento: no se carga al usar la skill.

## [Unreleased]
### Added
- MODO SALIDA: red de seguridad opcional con `harvest-instructions.ps1` para detectar indicaciones de la sesión que no se registraron.

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
