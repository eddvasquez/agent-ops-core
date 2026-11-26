---
trigger: glob
globs: "**/.env, **/.env.local, **/.env.*.local, **/.env.production, **/.env.bak, **/*.pem, **/*.key, **/*.pfx, **/*.p12, **/*.kdbx, **/.htpasswd, **/id_rsa*, **/id_ed25519*, **/google-ads.yaml, **/google-ads.yml, **/*.tfstate, **/*.tfstate.backup, **/*.tfvars, **/wp-config.php.bak, **/wp-config.php~"
description: Archivos de credenciales (Agent Ops Core)
---

- Este archivo puede contener credenciales: no leas, muestres, copies ni resumas su contenido.
- Si necesitas un valor, pide al usuario que lo escriba él en el archivo (o que te autorice expresamente); nunca lo pidas en la conversación.
- La protección de credenciales del marco te preguntará antes de cualquier acción sobre él: respeta esa decisión.
