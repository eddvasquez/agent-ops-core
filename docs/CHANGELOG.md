# Changelog

Todos los cambios relevantes de Agent Ops Core se documentan en este archivo.

El formato sigue [Keep a Changelog](https://keepachangelog.com/es-ES/1.1.0/) y el proyecto usa [Versionado Semántico](https://semver.org/lang/es/). Los cambios de cada skill pública se detallan en `docs/changelogs/<skill>.md`. El changelog, `VERSION` y los changelogs de skills viven en `docs/` porque las instalaciones existentes solo aceptan publicaciones dentro de su lista de rutas permitidas.

## [Unreleased]

## [1.1.1] - 2026-11-19
### Fixed
- Las instalaciones existentes rechazaban la 1.1.0 («Unexpected/private file in public release: CHANGELOG.md»): el arranque instalado verifica cada versión con una lista de rutas fija. `CHANGELOG.md`, `VERSION` y `changelogs/` pasan a `docs/`, y el verificador de versionado acepta también esa ubicación.
- Nueva prueba de regresión: todo archivo publicado debe pasar la lista de rutas del arranque instalado más antiguo soportado.
- Las pruebas de versionado crean sus tags con una identidad de Git de prueba; en CI, donde no hay identidad global, fallaban con «Committer identity unknown».

## [1.1.0] - 2026-11-19
### Added
- Protocolo 8 (Reglas del Proyecto y Compuerta de Cumplimiento): toda corrección del usuario se registra en el acto como regla de proyecto en `.context/reglas_proyecto.md`, se relee antes de producir y entregar y se verifica con una compuerta antes de entregar. Funciona igual en cualquier arnés de IA.
- Verificador `scripts/check-rules.ps1` (`RulesCheck.psm1`): expresiones vetadas y patrones, datos obligatorios, ámbito por pieza, reglas retiradas, insensible a mayúsculas y tildes, palabras completas; con pruebas en `tests/rules-check.tests.ps1`.
- Plantilla `templates/context/reglas_proyecto.md`; la migración la crea cuando falta y nunca toca una existente.
- Protocolo 7 (Versionado Semántico y Trazabilidad de Cambios) en `templates/AGENTS.md`.
- Verificador `scripts/check-versioning.ps1` (`Versioning.psm1`): SemVer declarada, changelogs Keep a Changelog, cobertura de cambios y coherencia de tags; con pruebas en `tests/versioning.tests.ps1`.
- Plantilla `templates/CHANGELOG.md`; la migración la crea cuando falta y nunca modifica una existente.
- Comando `scripts/set-hub.ps1` (`Set-AgentOpsHubDir`) para cambiar el hub de una instalación existente: evalúa un plan de sincronización contra el nuevo hub, respalda y actualiza juntos `watch-config.json` y `update-state.json`, completa cambios interrumpidos y reinicia el vigilante; con pruebas en `tests/hub-reconfigure.tests.ps1`.
- El verificador rechaza un `version:` insertado dentro de una descripción en bloque (`description: >-`).
- Campo `version:` en el frontmatter de las seis skills públicas y sus changelogs en `changelogs/`.

### Changed
- MODO SALIDA y el Protocolo 6 separan el commit funcional del de relevo y prohíben `git add .`/`git add -A`.
- La política de publicación admite `CHANGELOG.md`, `VERSION` y `changelogs/*.md`.
- `AGENTS.md` y `.context/` de este checkout quedan fuera de Git: son gobernanza local, no parte del paquete público.
- Las plantillas pasan a referirse a 7 protocolos. Un `AGENTS.md` migrado con la plantilla anterior requiere revisión (`AGENTS_REVIEW_REQUIRED`) para incorporar el Protocolo 7.

## [1.0.0] - 2026-11-18
### Added
- Línea base versionada: migración verificable de proyectos, actualizaciones verificadas de sesión, sincronización segura de skills en Windows (estado de `e5eb4d1`).
