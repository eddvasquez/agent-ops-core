# Historial de versiones anteriores: ops-session-handoff

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
