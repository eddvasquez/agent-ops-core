# Antigravity: permisos nativos para carpetas de credenciales

Antigravity aplica sus permisos (Deny > Ask > Allow) antes que cualquier otra cosa, pero sus reglas de archivos solo aceptan **rutas exactas o carpetas**, no patrones como `**/.env`. Por eso Agent Ops Core protege los archivos de credenciales de los proyectos con su hook (antes de cada acción) y con la regla `credenciales.md` de su plugin, y añade automáticamente reglas **Ask** («preguntar») en `~/.gemini/config/config.json` para las carpetas fijas de credenciales que existan en tu equipo, tras pedirte permiso una sola vez.

## Cómo añadirlas
1. Al iniciar sesión en un proyecto gobernado, el agente te preguntará una vez si quieres proteger tus carpetas de credenciales en Antigravity (el marco guarda una copia de respaldo antes de modificar `config.json`).
2. Si aceptas, el marco añade una regla `read_file(...)` en la lista **Ask** por cada carpeta existente de la tabla inferior, respetando cualquier regla que ya hayas decidido en `allow`, `ask` o `deny`.
3. **Reinicia Antigravity** para que los cambios surtan efecto. Si prefieres hacerlo a mano, también puedes añadirlas en Antigravity → **Settings → Permissions** (en Windows quita la letra de unidad y usa `/`, por ejemplo `read_file(/Users/<usuario>/.ssh)`).

«Negar lectura» también niega escritura, y una regla sobre una carpeta cubre todo lo que contiene.

## Carpetas habituales de credenciales
| Carpeta (Windows) | Regla |
| --- | --- |
| `%USERPROFILE%\.ssh` | `read_file(/Users/<usuario>/.ssh)` |
| `%APPDATA%\gcloud` | `read_file(/Users/<usuario>/AppData/Roaming/gcloud)` |
| `%USERPROFILE%\.aws` | `read_file(/Users/<usuario>/.aws)` |
| `%USERPROFILE%\.azure` | `read_file(/Users/<usuario>/.azure)` |
| `%USERPROFILE%\.kube` | `read_file(/Users/<usuario>/.kube)` |
| `%USERPROFILE%\.docker` | `read_file(/Users/<usuario>/.docker)` |
| `%USERPROFILE%\.git-credentials` | `read_file(/Users/<usuario>/.git-credentials)` |
| `%USERPROFILE%\.netrc` | `read_file(/Users/<usuario>/.netrc)` |
| `%USERPROFILE%\.npmrc` | `read_file(/Users/<usuario>/.npmrc)` |

Usa **Ask** y no **Deny**: así el agente te pregunta y tú decides, igual que con la protección del marco.

## Qué no cubren
Estas reglas solo frenan las herramientas de archivos del agente. Las órdenes de terminal las revisa el hook de Agent Ops Core (y, con los ajustes Default o Auto, el aislamiento de la terminal solo ve el espacio de trabajo y las carpetas temporales).
