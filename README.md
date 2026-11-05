<div align="center">

# Agent Ops Core

### El Sistema de Memoria Persistente y Gobernanza Operativa para Equipos de Inteligencia Artificial.

**Deja de quemar horas reexplicando tu negocio en cada chat. Dale a tu IA una memoria física indestructible en Git, verificación de avances sin complacencia y cero amnesia entre sesiones.**

[![Ecosistema](https://img.shields.io/badge/Ecosistema-Multiagente%20(Claude%20%7C%20Gemini%20%7C%20Codex)-818cf8?style=flat-square)]()
[![Arquitectura](https://img.shields.io/badge/Arquitectura-Git%20%2B%20.context%2F-38bdf8?style=flat-square)]()
[![Instalación](https://img.shields.io/badge/Instalador-1--Click%20(Win%20%7C%20Mac%20%7C%20Linux)-10b981?style=flat-square)]()
[![Licencia](https://img.shields.io/badge/Licencia-Apache%202.0-blue?style=flat-square)](LICENSE)
[![Skills](https://img.shields.io/badge/Skills%20Core-6%20Habilidades%20Maestras-orange?style=flat-square)](#el-catalogo-de-las-6-skills-operativas-incluidas)

[Arranque en 60s](#como-arrancar-este-sistema-en-60-segundos-cero-codigo) · [Flujo Diario en 3 Pasos](#el-flujo-de-trabajo-diario-en-3-pasos) · [Garantía Antirriesgo](#tus-archivos-y-tu-memoria-estan-a-salvo) · [Los 4 Cuellos de Botella](#los-cuatro-cuellos-de-botella-que-destruyen-tu-productividad-con-ia) · [Diagramas](#neutralidad-multiagente-y-distribucion-simetrica) · [Los 6 Protocolos](#los-seis-protocolos-universales-de-agentsmd) · [Aviso Legal](#licencia-y-aviso-legal-de-independencia)

</div>

> [!IMPORTANT]
> **Tus Archivos y tu Memoria Están a Salvo:**
> Toda IA dejada a su suerte improvisa supuestos, inventa conclusiones complacientes y olvida el contexto al cerrar la ventana. **Agent Ops Core** impone un estándar físico: ningún agente puede afirmar que una tarea está terminada sin evidencia comprobable, ningún archivo se modifica a ciegas y la memoria histórica de tu negocio queda blindada localmente bajo control de versiones Git y respaldo cloud.

---

## Cómo Arrancar este Sistema en 60 Segundos (Cero Código)

No necesitas ser programador, compilar dependencias ni memorizar comandos de terminal. Elige la vía que mejor se adapte a tu forma de trabajar:

### Método 1: La Vía Directa en Chat (100% Sin Terminal)

Si utilizas **Claude Desktop**, **ChatGPT**, **Gemini**, **Cursor** o **Antigravity**, copia y pega este bloque en el chat de tu IA para activar el protocolo de inmediato:

```text
Actúa como mi Ingeniero de Operaciones y Gobernanza de Proyectos. 

Quiero que trabajemos bajo el estándar universal de AGENTS.md del repositorio público https://github.com/eddvasquez/agent-ops-core.

Por favor realiza lo siguiente de forma estricta:
1. Revisa las directrices públicas de https://raw.githubusercontent.com/eddvasquez/agent-ops-core/main/README.md y los 6 Protocolos de AGENTS.md.
2. Si tienes acceso a mi terminal o herramientas locales, ejecuta el comando de instalación de 1 línea para mi sistema operativo (Windows o Mac/Linux) para instalar las skills operativas en mis carpetas locales (~/.gemini, ~/.claude o ~/.agents).
3. Si estamos operando exclusivamente en esta ventana de chat sin herramientas locales, adopta inmediatamente el Protocolo 1 (MODO ENTRADA): audita el estado actual de nuestro objetivo, revisa qué directrices previas tenemos y entrégame el Reporte de 5 Puntos antes de realizar cualquier cambio, redacción o propuesta.
```

---

### Método 2: Instalación Permanente en tu Computadora (1 Solo Comando)

Si deseas que todas tus sesiones locales de Claude Code, Antigravity o Codex compartan automáticamente las skills maestras y se auto-actualicen cada 24 horas:

#### En Windows (PowerShell):
```powershell
irm https://raw.githubusercontent.com/eddvasquez/agent-ops-core/main/install.ps1 | iex
```

#### En macOS y Linux (Terminal):
```bash
curl -fsSL https://raw.githubusercontent.com/eddvasquez/agent-ops-core/main/install.sh | bash
```

> [!TIP]
> **Detección Automática de Nube:** El instalador detecta si cuentas con Google Drive o almacenamiento cloud configurado, valida la sincronización y registra un proceso de actualización diaria silenciosa sin interrumpir tu trabajo.

---

## El Flujo de Trabajo Diario en 3 Pasos

Una vez activado el sistema, así operas en el día a día para mantener disciplina absoluta en proyectos de **marketing digital, consultoría, finanzas, operaciones o software**:

```mermaid
%%{init: {'theme': 'dark', 'themeVariables': { 'fontSize': '15px' }}}%%
flowchart TD
    Paso1["<b>PASO 1: Arrancar Proyecto</b><br><i>'Usa ops-crear-proyecto para [Nombre]'</i><br>Crea carpeta, inicializa Git y levanta .context/"]
    Paso2["<b>PASO 2: Abrir Sesión de Trabajo</b><br><i>'Iniciemos turno con ops-gestion-relevo MODO ENTRADA'</i><br>Audita Git real, revisa lecciones y emite Reporte de 5 Puntos"]
    Paso3["<b>PASO 3: Cerrar Sesión y Respaldar</b><br><i>'Terminamos por hoy, ejecuta ops-gestion-relevo MODO SALIDA'</i><br>Audita entregables, actualiza progreso y genera commit atómico"]

    Paso1 ==> Paso2 ==> Paso3
    Paso3 -.->|"Siguiente sesión sin amnesia"| Paso2

    classDef step fill:#0f172a,stroke:#38bdf8,stroke-width:2px,color:#f8fafc;
    class Paso1,Paso2,Paso3 step;
```

### 1. Paso 1: Arrancar un Proyecto Nuevo
Dile a tu IA:
> *"Usa `ops-crear-proyecto` para inicializar el proyecto [Nombre de tu Proyecto]"*

La IA creará la estructura limpia, verificará que el directorio esté respaldado en tu almacenamiento cloud (evitando pérdidas por daño de disco), inicializará el repositorio Git local protegido y creará la carpeta `.context/` con los 5 archivos de memoria persistente.

### 2. Paso 2: Abrir Turno de Trabajo (Modo Entrada)
Al comenzar el día o abrir un nuevo chat, dile:
> *"Iniciemos sesión con `ops-gestion-relevo` MODO ENTRADA"*

La IA tiene prohibido tocar archivos o sugerir cambios de inmediato. Primero ejecuta `git status -s` y `git log -n 3`, lee la memoria de `activeContext.md` y las lecciones aprendidas, y te entrega el **Reporte de 5 Puntos** (auditoría Git, directrices vigentes, habilidades disponibles, discrepancias detectadas y siguiente paso inmediato). Tú sólo respondes "OK" para autorizar el avance.

### 3. Paso 3: Cerrar Turno y Relevar (Modo Salida)
Al terminar tu jornada o antes de cerrar el chat, dile:
> *"Terminamos por hoy, ejecuta `ops-gestion-relevo` MODO SALIDA"*

La IA audita qué tareas se cumplieron objetivamente, documenta cualquier error o directriz nueva en `lessons_learned.md`, actualiza con precisión quirúrgica el archivo `activeContext.md` para el próximo turno y genera el commit atómico de relevo en Git con pausa de seguridad para la sincronización en la nube.

---

## Los Cuatro Cuellos de Botella que Destruyen tu Productividad con IA

### 1. La Amnesia de Turno y la Reexplicación Crónica
- **El Coste:** En cada nuevo chat, la IA olvida el perfil del cliente, las cifras de la oferta, el tono de marca y las objeciones previas. El operador pierde entre 20 y 45 minutos repitiendo antecedentes.
- **La Solución Agent Ops:** Memoria persistente en Markdown nativo (`.context/`). La IA lee el estado exacto antes de escribir una sola palabra.

### 2. La Complacencia del Falso Avance
- **El Coste:** El modelo afirma con entusiasmo que un copy, un informe de mercado o un script de ventas está "listo", pero al inspeccionarlo contiene datos genéricos, números inventados o instrucciones a medio hacer.
- **La Solución Agent Ops:** Mandato anti-complacencia. Queda prohibido marcar hitos como terminados sin evidencia física comprobable y contrastada contra criterios objetivos de éxito.

### 3. La Modificación Especulativa (Parches a Ciegas)
- **El Coste:** Ante un error o retroalimentación, la IA pide disculpas serviles y altera variables al azar (*shotgun approach*), dañando la coherencia del resto de entregables.
- **La Solución Agent Ops:** Depuración sistemática en 4 fases: aislamiento del síntoma, análisis de causa raíz, hipótesis única y corrección quirúrgica controlada.

### 4. La Dispersión de Datos y la Vulnerabilidad Cloud
- **El Coste:** Archivos dispersos sin versionar, versiones duplicadas informales (`brief_final_v2.docx`) y riesgo de pérdida absoluta si la plataforma del proveedor sufre una caída o bloquea la cuenta.
- **La Solución Agent Ops:** Neutralidad e independencia total. El conocimiento y la memoria residen en tu máquina y tu nube bajo Git, legibles por cualquier IA de hoy o de mañana.

---

## Comparativa de Rendimiento Operativo

| Dimensión | Operación Sin Gobernanza (Tradicional) | Operación Con Agent Ops Core |
| :--- | :--- | :--- |
| **Continuidad entre Sesiones** | Amnesia recurrente; el usuario debe reexplicar el contexto en cada turno. | Protocolo de Relevo (Modo Entrada): auditoría del estado real y confirmación de foco. |
| **Calidad de Entregables** | Contenido genérico y complaciente sin verificación rigurosa. | Validación contra criterios de éxito explícitos y memoria de lecciones aprendidas. |
| **Resolución de Incidencias** | Modificaciones a ciegas (*shotgun approach*) que generan retrabajos. | Análisis determinista de causa raíz antes de intervenir cualquier activo. |
| **Independencia Tecnológica** | Dependencia absoluta del ecosistema de un solo proveedor. | Neutral: Las mismas reglas operan idénticas en Claude, Gemini, ChatGPT y terminales locales. |
| **Seguridad de Archivos** | Riesgo de pérdida por daño físico o sobreescritura accidental. | Auditoría automática de almacenamiento en la nube y versionado Git protegido. |

---

## El Catálogo de las 6 Skills Operativas Incluidas

| Skill | Tipo | Función Crítica y Resultado Operativo |
| :--- | :---: | :--- |
| **`ops-crear-proyecto`** | Operación | Inicializa proyectos nuevos con arquitectura v2, Git protegido y auditoría preventiva de respaldo en Google Drive/Cloud. |
| **`ops-gestion-relevo`** | Gobernanza | Ejecuta el protocolo de relevo diario (Modo Entrada y Modo Salida) con auto-actualización silenciosa cada 24 horas. |
| **`ops-migrar-proyecto`** | Operación | Convierte proyectos legados o desordenados a la arquitectura universal v2 sin destruir datos ni duplicar archivos. |
| **`ops-git-worktrees`** | Operación | Gestiona directorios de trabajo paralelos en Git para abordar tareas simultáneas sin bloqueos de ramas. |
| **`dev-tdd`** | Calidad | Implementa metodología Test-Driven Development (Red-Green-Refactor) para entregables verificados con pruebas. |
| **`dev-systematic-debugging`** | Resolución | Metodología de 4 fases para investigar y resolver incidencias de causa raíz sin parches a ciegas. |

---

## Neutralidad Multiagente y Distribución Simétrica

El sistema de gobernanza reside en una capa independiente y universal. Ningún arnés ni empresa de IA es propietaria de tu estructura de trabajo:

```mermaid
%%{init: {'theme': 'dark', 'themeVariables': { 'fontSize': '16px', 'fontFamily': 'system-ui, -apple-system, sans-serif' }}}%%
flowchart TD
    subgraph GITHUB["Repositorio Central (Capa Pública)"]
        Core["agent-ops-core<br><b>(Gobernanza y Protocolos)</b>"]
    end

    subgraph LOCAL["Entorno Local del Operador"]
        subgraph HARNESSES["Arneses de Inteligencia Artificial"]
            direction LR
            Gemini["~/.gemini/skills/<br><b>(Antigravity / Gemini)</b>"]
            Claude["~/.claude/skills/<br><b>(Claude Code / App)</b>"]
            Codex["~/.agents/skills/<br><b>(OpenAI Codex / Std)</b>"]
        end

        subgraph PROYECTOS["Proyectos Multidisciplinarios"]
            direction LR
            P1["Marketing & Tráfico<br>(.context/ + AGENTS.md)"]
            P2["Operaciones & Negocio<br>(.context/ + AGENTS.md)"]
            P3["Software & Código<br>(.context/ + AGENTS.md)"]
        end
    end

    Core -->|"install.ps1 / install.sh"| Gemini
    Core -->|"install.ps1 / install.sh"| Claude
    Core -->|"install.ps1 / install.sh"| Codex

    Gemini -->|"Gobernanza Unificada"| PROYECTOS
    Claude -->|"Gobernanza Unificada"| PROYECTOS
    Codex -->|"Gobernanza Unificada"| PROYECTOS

    classDef central fill:#1e293b,stroke:#38bdf8,stroke-width:2px,color:#f8fafc;
    classDef harness fill:#0f172a,stroke:#818cf8,stroke-width:2px,color:#f8fafc;
    classDef project fill:#0f172a,stroke:#34d399,stroke-width:2px,color:#f8fafc;
    class Core central;
    class Gemini,Claude,Codex harness;
    class P1,P2,P3 project;
```

---

## Arquitectura de Trabajo en Dos Capas

El framework separa de forma estricta los procesos operativos de los activos propietarios del negocio:

```mermaid
%%{init: {'theme': 'dark', 'themeVariables': { 'fontSize': '16px' }}}%%
flowchart TD
    subgraph CAPA1["CAPA 1: Gobernanza Universal (GitHub Público)"]
        direction TB
        OpsCore["agent-ops-core"]
        P_Ops["• ops-crear-proyecto<br>• ops-gestion-relevo<br>• ops-migrar-proyecto<br>• dev-tdd & dev-debugging"]
    end

    subgraph CAPA2["CAPA 2: Bóveda Privada (Google Drive Local)"]
        direction TB
        HubPrivado["_ai-skills-hub"]
        P_Priv["• Metodologías comerciales<br>• Activos de marketing y copy<br>• Ofertas de conversión<br>• Credenciales y accesos"]
    end

    subgraph MOTOR["Entorno de Ejecución Local"]
        IA["Claude Code / Antigravity / Codex"]
        Proyecto["Proyectos Activos del Negocio<br>(Marketing, Operaciones, Software)"]
    end

    CAPA1 -->|"Sincronización Git"| IA
    CAPA2 -->|"Servicio de Sincronización"| IA
    IA -->|"Ejecución Blindada"| Proyecto

    classDef public fill:#1e293b,stroke:#38bdf8,stroke-width:2px,color:#f8fafc;
    classDef private fill:#1e293b,stroke:#f59e0b,stroke-width:2px,color:#f8fafc;
    classDef target fill:#0f172a,stroke:#10b981,stroke-width:2px,color:#f8fafc;
    class OpsCore,P_Ops public;
    class HubPrivado,P_Priv private;
    class IA,Proyecto target;
```

1. **Capa 1: Marco de Gobernanza (`agent-ops-core` en GitHub):**
   - Protocolo universal `AGENTS.md`.
   - Inicializador de proyectos multidisciplinarios (`ops-crear-proyecto`).
   - Gestión de relevos y recepción/cierre de turnos (`ops-gestion-relevo`).
   - Estandarización y rescate de proyectos legados (`ops-migrar-proyecto`).
   - Aislamiento de tareas paralelas (`ops-git-worktrees`).
   - Protocolos de verificación y depuración de causa raíz.

2. **Capa 2: Bóveda Privada de Negocio (Almacenamiento Local Respaldado):**
   - Habilidades propietarias de la empresa: marcos de consultoría, ángulos de adquisición, guiones comerciales y credenciales.
   - Reside exclusivamente en tu almacenamiento respaldado y privado, sin exposición en repositorios públicos.
   - Servicios de sincronización en segundo plano unifican ambas capas en los arneses de IA en tiempo real.

---

## Ciclo de Vida Operativo: Protocolo de Relevo

Así interactúan el operador, los agentes de Inteligencia Artificial y el control de versiones en cada turno de trabajo:

```mermaid
%%{init: {'theme': 'dark', 'themeVariables': { 'fontSize': '14px' }, 'sequence': { 'actorFontSize': '14px', 'messageFontSize': '13px', 'noteFontSize': '12px', 'width': 170 }}}%%
sequenceDiagram
    autonumber
    actor U as Operador (Usuario)
    participant IA as Agente de IA (Claude / Gemini / Codex)
    participant CTX as Memoria Local (.context/)
    participant GIT as Control Físico (Git)

    Note over U,GIT: FASE 1: RECEPCIÓN DE TURNO (MODO ENTRADA)
    U->>IA: Inicia sesión / asigna objetivo
    IA->>CTX: Lee AGENTS.md, activeContext.md y lecciones aprendidas
    IA->>GIT: Ejecuta git status -s y git log -n 3
    GIT-->>IA: Retorna estado físico real del árbol
    IA->>U: Emite Reporte de 5 Puntos (auditoría, reglas, skills, siguiente paso)
    U-->>IA: Validación humana explícita ("OK")

    Note over U,GIT: FASE 2: EJECUCIÓN DISCIPLINADA
    IA->>IA: Aplica TDD (Red-Green-Refactor) o Depuración Sistemática
    IA->>CTX: Actualiza memoria operativa

    Note over U,GIT: FASE 3: CIERRE DE TURNO (MODO SALIDA)
    IA->>CTX: Registra lecciones y actualiza activeContext.md
    IA->>GIT: Commit atómico de relevo (con pausa cloud)
    GIT-->>U: Confirmación de versión registrada y respaldo listo
```

---

## Los Seis Protocolos Universales de AGENTS.md

Todo proyecto iniciado con este framework incluye un archivo rector `AGENTS.md` con seis reglas innegociables:

1. **Protocolo 1 (Inicio de Turno / Auditoría de Estado):** Prevalencia de la evidencia física de Git y los registros de contexto sobre suposiciones verbales. Reporte de 5 puntos obligatorio antes de modificar activos.
2. **Protocolo 2 (Cero Suposiciones y Memoria Cruda):** Prohibido adivinar requerimientos o directrices del cliente. Toda corrección humana se registra cronológicamente en `.context/lessons_learned.md`.
3. **Protocolo 3 (Invocación Mandatoria y Anti-Racionalización):** Prohibido omitir habilidades o metodologías probadas con excusas de premura.
4. **Protocolo 4 (Destilación de Conocimiento):** Las reglas operativas que demuestren valor universal se abstraen hacia habilidades maestras reutilizables.
5. **Protocolo 5 (Escritor Único e Higiene en la Nube):** Un único agente activo por turno para prevenir colisiones; prohibición de archivos duplicados; pausas de seguridad para liberar bloqueos de sincronización en la nube.
6. **Protocolo 6 (Cierre de Turno y Relevo):** Auditoría objetiva de tareas terminadas antes de actualizar el progreso y generación de commit atómico de relevo.

---

## Licencia y Aviso Legal de Independencia

Este proyecto está distribuido bajo la Licencia [Apache 2.0](LICENSE).

**Aviso de Independencia y Marcas:** Agent Ops Core es un marco de gobernanza independiente desarrollado por Edd Vásquez. No está afiliado, patrocinado, respaldado ni certificado por Google LLC, Anthropic PBC, OpenAI ni ninguna de sus entidades filiales. Todas las marcas registradas y nombres de productos mencionados pertenecen a sus respectivos titulares.
