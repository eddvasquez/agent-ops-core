# Antigravity: permisos nativos para carpetas de credenciales

Antigravity aplica sus permisos (Deny > Ask > Allow) antes que cualquier otra cosa, pero sus reglas de archivos solo aceptan **rutas exactas o carpetas**, no patrones como `**/.env`, y se configuran **desde su interfaz**: no hay un archivo que el marco pueda escribir. Por eso Agent Ops Core protege los archivos de credenciales de los proyectos con su hook (antes de cada acción) y con la regla `credenciales.md` de su plugin, y te propone añadir tú estas reglas para las carpetas de credenciales de tu usuario, que sí tienen ruta fija.

## Cómo añadirlas
1. Abre Antigravity → **Settings → Permissions** (o **Permissions → This Computer** si tienes agentes remotos).
2. En la lista **Ask** («preguntar»), añade una regla `read_file(...)` por cada carpeta que exista en tu equipo.
3. Antigravity quita la letra de unidad y usa `/` en Windows: `C:\Users\<usuario>\.ssh` se escribe `read_file(/Users/<usuario>/.ssh)`.

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
