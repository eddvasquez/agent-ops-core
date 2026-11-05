#!/usr/bin/env bash
# install.sh - Instalador Universal de Agent Ops Core (macOS / Linux)
set -e

REPO_URL="${REPO_URL:-https://github.com/eddvasquez/agent-ops-core.git}"
TARGET_DIR="$HOME/.agent-ops"

echo "=========================================================="
echo "  Agent Ops Core - Instalador de Gobernanza para IA (Unix)"
echo "=========================================================="

# 1. Clonar o Actualizar el Repositorio Central
if [ -d "$TARGET_DIR/.git" ]; then
    echo "[*] Repositorio detectado en $TARGET_DIR. Actualizando..."
    cd "$TARGET_DIR"
    git pull --ff-only
else
    echo "[*] Clonando Agent Ops Core en $TARGET_DIR..."
    rm -rf "$TARGET_DIR"
    git clone "$REPO_URL" "$TARGET_DIR"
fi

# 2. Registrar Timestamp Inicial
date -u +"%Y-%m-%dT%H:%M:%SZ" > "$TARGET_DIR/.last_update_check"

# 3. Detectar Estado de Respaldo Cloud (Google Drive / iCloud en macOS)
echo "[*] Verificando presencia de almacenamiento respaldado en la nube..."
GDRIVE_FOUND=0

# Rutas estándar de Google Drive en macOS y Linux
if [ -d "$HOME/Library/CloudStorage" ]; then
    for d in "$HOME/Library/CloudStorage"/GoogleDrive-*; do
        if [ -d "$d" ]; then
            echo "  [+] Respaldo Google Drive detectado en macOS: $d"
            GDRIVE_FOUND=1
            break
        fi
    done
fi

if [ -d "$HOME/Google Drive" ] || [ -d "$HOME/Documents/ChatGPT" ]; then
    echo "  [+] Directorio respaldado detectado en: $HOME/Documents/ChatGPT"
    GDRIVE_FOUND=1
fi

if [ "$GDRIVE_FOUND" -eq 0 ]; then
    echo "  [!] ATENCION: No se detecto ruta activa de Google Drive."
    echo "      Se recomienda ejecutar proyectos dentro de una carpeta sincronizada o conectar repositorios remotos Git."
fi

# 4. Replicar Skills a los Arneses Locales (~/.gemini, ~/.claude, ~/.agents)
echo "[*] Desplegando skills a los arneses de IA..."
TARGETS=(
    "$HOME/.gemini/config/skills"
    "$HOME/.claude/skills"
    "$HOME/.agents/skills"
)

for target in "${TARGETS[@]}"; do
    mkdir -p "$target"
    if [ -d "$TARGET_DIR/skills" ]; then
        for skill_dir in "$TARGET_DIR"/skills/*; do
            if [ -d "$skill_dir" ]; then
                skill_name=$(basename "$skill_dir")
                mkdir -p "$target/$skill_name"
                cp -R "$skill_dir/"* "$target/$skill_name/" 2>/dev/null || true
            fi
        done
        echo "  [+] Skills instaladas en: $target"
    fi
done

chmod +x "$TARGET_DIR/update.sh" 2>/dev/null || true

# 5. Tarea Diaria Opcional (Cron)
if command -v crontab >/dev/null 2>&1; then
    CRON_CMD="0 9 * * * \"$TARGET_DIR/update.sh\" >/dev/null 2>&1"
    (crontab -l 2>/dev/null | grep -Fv "$TARGET_DIR/update.sh" ; echo "$CRON_CMD") | crontab - 2>/dev/null || true
    echo "  [+] Tarea diaria registrada en crontab (9:00 AM)."
fi

echo "=========================================================="
echo "  ¡Instalacion completada con exito!                      "
echo "  Skills operativas disponibles en todos tus arneses de IA."
echo "=========================================================="
