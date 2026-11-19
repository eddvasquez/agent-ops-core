# Changelog: ops-project-init

Cambios relevantes de la skill `ops-project-init`. Formato [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/), versionado [SemVer](https://semver.org/lang/es/). Archivo de mantenimiento: no se carga al usar la skill.

## [Unreleased]

## [1.2.0] - 2026-11-19
### Changed
- El commit inicial se hace con `commit.ps1` en lugar de componer `git add`/`git commit`.

## [1.1.0] - 2026-11-19
### Added
- Crea `.context/reglas_proyecto.md` y registra las restricciones del cliente ya conocidas (Protocolo 8).
### Changed
- Inyecta `CHANGELOG.md` y `VERSION` y valida con `check-versioning.ps1` antes del commit inicial.
- Commit inicial con rutas explícitas en lugar de `git add .`.

## [1.0.0] - 2026-11-18
### Added
- Línea base versionada (estado publicado en `e5eb4d1`).
