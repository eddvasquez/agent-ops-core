#!/usr/bin/env bash
# update.sh - Actualizador de Agent Ops Core (macOS / Linux)
set -e

REPO_DIR="$HOME/.agent-ops"
TIMESTAMP_FILE="$REPO_DIR/.last_update_check"
FORCE=0

for arg in "$@"; do
    if [ "$arg" = "--force" ] || [ "$arg" = "-f" ]; then
        FORCE=1
    fi
done

if [ ! -d "$REPO_DIR" ]; then
    echo "[!] No se encontro el directorio $REPO_DIR. Ejecute primero install.sh."
    exit 0
fi

# Verificacion de intervalo de 24 horas si no es forzado
if [ "$FORCE" -eq 0 ] && [ -f "$TIMESTAMP_FILE" ]; then
    NOW=$(date +%s)
    # Soporte compatible para mtime en macOS (stat -f %m) y Linux (stat -c %Y)
    if stat -f %m "$TIMESTAMP_FILE" >/dev/null 2>&1; then
        LAST_CHECK=$(stat -f %m "$TIMESTAMP_FILE")
    else
        LAST_CHECK=$(stat -c %Y "$TIMESTAMP_FILE" 2>/dev/null || echo 0)
    fi
    DIFF=$((NOW - LAST_CHECK))
    if [ "$DIFF" -lt 86400 ]; then
        echo "[-] Verificacion omitida: ya se actualizo hace menos de 24h."
        exit 0
    fi
fi

echo "[*] Comprobando actualizaciones de Agent Ops Core desde GitHub..."

cd "$REPO_DIR"
if git pull --ff-only 2>&1; then
    date -u +"%Y-%m-%dT%H:%M:%SZ" > "$TIMESTAMP_FILE"
    
    TARGETS=(
        "$HOME/.gemini/config/skills"
        "$HOME/.claude/skills"
        "$HOME/.agents/skills"
    )

    for target in "${TARGETS[@]}"; do
        mkdir -p "$target"
        if [ -d "$REPO_DIR/skills" ]; then
            for skill_dir in "$REPO_DIR"/skills/*; do
                if [ -d "$skill_dir" ]; then
                    skill_name=$(basename "$skill_dir")
                    mkdir -p "$target/$skill_name"
                    cp -R "$skill_dir/"* "$target/$skill_name/" 2>/dev/null || true
                fi
            done
        fi
    done
    echo "[+] Agent Ops Core actualizado exitosamente."
else
    echo "[!] Advertencia: No se pudo conectar a GitHub o falló git pull."
fi
