# OWASP WSTG-CONF-03 frente a Agent Ops Core

Análisis del 2026-11-25, desde la perspectiva de un ingeniero de seguridad ofensiva y AppSec de clase mundial.

**Fuentes:**
- OWASP Web Security Testing Guide (WSTG), *WSTG-CONF-03: Review Old Backup and Unreferenced Files for Sensitive Information*.
- Inspección directa de `scripts/SecretGuard.psm1`, `scripts/PreCommitCheck.psm1`, `scripts/SecretScan.psm1`, `scripts/ProjectHygiene.psm1`, `scripts/UpdateCoordinator.psm1` (`check-release.ps1`) y `templates/antigravity-plugin/rules/credenciales.md` en Agent Ops Core `3.21.0`.

---

## Palabras que usa este documento
- **WSTG-CONF-03:** prueba estándar de OWASP para detectar copias antiguas, respaldos de editores, volcados de base de datos o archivos olvidados que exponen contraseñas, código fuente o configuración interna.
- **Superficie de exposición:** todo archivo o carpeta que queda accesible en un servidor web, en un paquete desplegado o en el historial compartido de Git.
- **Archivo no referenciado (huérfano):** archivo que ya no usa la aplicación pero sigue en la carpeta (por ejemplo `config.php.bak`, `dump.sql`, `phpinfo.php`, `index_old.html`).
- **Pre-commit (revisión al guardar):** control automático que corre justo antes de guardar un cambio en Git y frena el guardado si detecta un riesgo.
- **Sensor de higiene:** revisión pasiva al iniciar sesión que avisa de restos acumulados sin borrar ni cambiar nada.
- **Falso positivo:** alerta sobre un archivo inofensivo y legítimo (como `.env.example` o una migración SQL de esquema).

---

## 1. Qué exige OWASP WSTG-CONF-03 y por qué importa

En aplicaciones web, sitios WordPress, landings y repositorios de automatización es frecuente que queden archivos olvidados junto al código activo:

| Vector WSTG-CONF-03 | Ejemplos habituales | Riesgo principal |
| --- | --- | --- |
| Respaldos de edición o manuales | `*.bak`, `*.old`, `*.orig`, `*.save`, `*~`, `*.swp`, `*.swo` | El servidor entrega código o configuración como texto plano (por ejemplo `wp-config.php.bak` o `.env.bak`). |
| Archivos de estado y secretos | `.env*`, `.tfstate`, `.tfvars`, `.kdbx`, `.htpasswd`, `*.key`, `*.pem` | Fuga directa de claves de nube, bases de datos, tokens o hashes de acceso. |
| Volcados y bases locales | `*.sql`, `*.dump`, `*.sqlite`, `*.db` | Exposición de datos de clientes, correos, usuarios y contraseñas. |
| Paquetes comprimidos olvidados | `backup*.zip`, `site.tar.gz`, `*.rar`, `*.7z` | Descarga completa del sitio, plugins y archivos de configuración en un solo archivo. |
| Control de versiones y diagnóstico | `.git/`, `.svn/`, `debug.log`, `error_log`, `phpinfo.php` | Reconstrucción del historial completo o información interna del servidor y rutas. |

---

## 2. Qué cubría Agent Ops Core antes de este análisis

Antes de incorporar WSTG-CONF-03, el marco ya contaba con protecciones valiosas, pero orientadas sobre todo al **contenido** de claves conocidas y a archivos de credenciales específicos:

| Capa del marco | Qué cubría ya | Brecha frente a WSTG-CONF-03 |
| --- | --- | --- |
| **Antes de cada acción** (`SecretGuard.psm1` y `credenciales.md`) | Protege `.env*` (salvo ejemplos), llaves (`pem`, `key`, `pfx`, `p12`), `google-ads.yaml`, `.npmrc`, `credentials*`/`secret*`. Las reglas nativas de Claude Code ya incluyen `.tfstate`, `.tfvars`, `.kdbx` y `.htpasswd`. | `Test-AgentOpsSecretPath` (que protege Codex, Antigravity y comandos de terminal) **no incluía** `.tfstate`, `.tfvars`, `.kdbx`, `.htpasswd` ni respaldos de archivos sensibles (`.env.bak`, `wp-config.php.bak`). |
| **Al guardar en Git** (`PreCommitCheck.psm1` + `SecretScan.psm1`) | Bloquea líneas añadidas que contengan llaves privadas o prefijos de token (`ghp_`, `AIza`, `sk-`). | No revisaba las **rutas preparadas (staged)**: permitía guardar `backup.sql`, `terraform.tfstate`, `config.bak` o `.env` si no incluían esos prefijos exactos. |
| **Higiene al iniciar sesión** (`ProjectHygiene.psm1`) | Reporta copias de skills del hub, archivos >7 días en `scratch/`/`tmp/`/`.tmp/` y gobernanza sin guardar en Git. | No buscaba respaldos (`.bak`, `.old`, `~`, `.swp`), volcados (`.sql`, `.dump`) ni estados olvidados en la raíz o en carpetas web (`web/`, `public/`, `dist/`). |
| **Despliegue web / WordPress / landings** | `check-release.ps1` valida el paquete público de Agent Ops Core; Protocolo 7 pide registrar despliegues fuera de Git. | No existía una herramienta de solo lectura para auditar una carpeta web antes de subirla a producción. |

---

## 3. Diseño de defensa en capas gradual

Para cubrir tanto **sitios web / WordPress / landings** como **repositorios locales** sin frenar el trabajo legítimo:

1. **Capa 1 — Higiene al iniciar sesión (`ProjectHygiene.psm1`, solo lectura):**
   - Avisa cuando aparecen restos o respaldos olvidados (`backup-or-unreferenced`), excluyendo `node_modules/`, `.git/`, `.venv/`, `vendor/`, `scratch/`, `tmp/`, `.tmp/`.
   - Respeta `.gitignore` en repositorios normales, **pero mantiene el aviso** dentro de carpetas de salida web (`web/`, `public/`, `www/`, `dist/`, `build/`), donde un archivo ignorado por Git sigue siendo un riesgo si se sube por FTP, WordPress o Kiral.
   - Nunca borra ni modifica archivos automáticamente (`ProjectHygiene.psm1` es estrictamente de solo lectura y no ejecuta `Remove-Item`).

2. **Capa 2 — Durante la sesión (`SecretGuard.psm1` y `credenciales.md`):**
   - Iguala la protección en todos los arneses para `.tfstate`, `.tfvars`, `.kdbx`, `.htpasswd` y variantes con sufijo de respaldo (`.bak`, `.old`, `.orig`, `.save`, `.swp`, `~`) de archivos sensibles.
   - Mantiene excluidos los archivos de ejemplo (`.env.example`, `.env.sample`, `.env.template`, `.env.dist`).

3. **Capa 3 — Al guardar en Git (`PreCommitCheck.psm1`):**
   - Bloquea guardar rutas sensibles (`.env`, llaves, `.tfstate`, `.kdbx`, `.htpasswd`), respaldos de editor/manuales (`.bak`, `.old`, `.orig`, `.save`, `.swp`, `~`), volcados (`.dump`, `.sqlite`, `.db`, `.sql` fuera de `migrations/`/`schema/`/`seeds/`), comprimidos de respaldo y `phpinfo.php` / `debug.log`.
   - Muestra exactamente qué archivo causó el bloqueo y cómo sacarlo del guardado (`git restore --staged`) o ignorarlo.

4. **Capa 4 — Antes de desplegar (`DeployAudit.psm1` + `check-deploy.ps1`, solo lectura):**
   - Revisa la carpeta candidata a producción antes de publicar o subir archivos.
   - Bloquea (`BLOCKED`, código `1`) si encuentra `.git/`, `.svn/`, credenciales, estados de infraestructura, respaldos, volcados, comprimidos o archivos de diagnóstico (`phpinfo.php`, `debug.log`, `error_log`).

---

## 4. Criterio para evitar falsos positivos

- **Ejemplos de configuración:** `.env.example`, `.env.sample`, `.env.template` y `.env.dist` nunca se bloquean.
- **Migraciones y esquemas SQL legítimos:** los archivos `.sql` dentro de `migrations/`, `schema/` o `seeds/` pasan normalmente, salvo que su nombre indique un volcado o respaldo (`*dump*`, `*backup*`).
- **Respaldos privados del marco:** los respaldos automáticos que guarda Agent Ops Core en `%LOCALAPPDATA%\AgentOps\backups` quedan fuera de los repositorios y nunca disparan alertas.
