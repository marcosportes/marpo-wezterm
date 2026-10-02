#!/bin/bash

# Instala/atualiza o WezTerm e sincroniza a configuração deste repositório
# em ~/.config/wezterm (usuário atual).
#
# Uso: ./setup.sh            -> git pull + instala pacotes faltantes + aplica config
#      ./setup.sh --no-pull  -> pula o git pull

set -e

# ========================================
# CONFIGURAÇÕES
# ========================================
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="$HOME/.config/wezterm"
PACKAGES="wezterm ttf-hack-nerd"

# Arquivos do repositório que não vão para ~/.config/wezterm
EXCLUDES=(--exclude .git --exclude .gitignore --exclude setup.sh
          --exclude README.md --exclude LICENSE --exclude screem.png)

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Função para exibir mensagens
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# A configuração é do usuário, não do root
if [ "$EUID" -eq 0 ]; then
    error "Execute como usuário normal (sem sudo); o sudo será pedido só para instalar pacotes"
    exit 1
fi

echo "=========================================="
echo "Setup WezTerm + configuração"
echo "=========================================="

# ========================================
# 1. Atualizar repositório
# ========================================
if [ "$1" != "--no-pull" ] && [ -d "$SRC_DIR/.git" ]; then
    info "Atualizando repositório (git pull)..."
    OLD_HEAD="$(git -C "$SRC_DIR" rev-parse HEAD)"
    if git -C "$SRC_DIR" pull --ff-only; then
        # Se o próprio setup.sh mudou, reexecuta a versão nova
        if [ "$OLD_HEAD" != "$(git -C "$SRC_DIR" rev-parse HEAD)" ]; then
            info "Repositório atualizado; reexecutando setup..."
            exec "$SRC_DIR/setup.sh" --no-pull
        fi
    else
        warn "git pull falhou (alterações locais ou sem rede); usando versão atual"
    fi
fi

# ========================================
# 2. Instalar pacotes faltantes
# ========================================
if command -v pacman >/dev/null; then
    MISSING=""
    for pkg in $PACKAGES; do
        pacman -Q "$pkg" >/dev/null 2>&1 || MISSING="$MISSING $pkg"
    done
    if [ -n "$MISSING" ]; then
        info "Instalando pacotes:$MISSING..."
        sudo pacman -S --needed --noconfirm $MISSING
    else
        info "Pacotes já instalados: $PACKAGES"
    fi
else
    warn "pacman não encontrado; instale manualmente: ${PACKAGES}"
fi

# ========================================
# 3. Aplicar configuração
# ========================================
mkdir -p "$DEST_DIR"

# Backup só quando a config local difere do repositório
CHANGES="$(rsync -a --checksum --delete --dry-run --itemize-changes \
    "${EXCLUDES[@]}" "$SRC_DIR/" "$DEST_DIR/" | grep -v '^\.d' || true)"

if [ -z "$CHANGES" ]; then
    info "Configuração já está atualizada em $DEST_DIR"
else
    if [ -n "$(ls -A "$DEST_DIR")" ]; then
        BACKUP="$DEST_DIR.backup.$(date +%Y%m%d_%H%M%S)"
        warn "Backup da configuração antiga: $BACKUP"
        cp -a "$DEST_DIR" "$BACKUP"
    fi
    info "Sincronizando configuração para $DEST_DIR..."
    rsync -a --checksum --delete "${EXCLUDES[@]}" "$SRC_DIR/" "$DEST_DIR/"
    chmod +x "$DEST_DIR"/scripts/*.sh
fi

# ========================================
# Finalização
# ========================================
echo ""
echo "=========================================="
info "Setup concluído com sucesso!"
echo "=========================================="
info "Configuração em: $DEST_DIR"
info "O WezTerm recarrega a config sozinho (ou use Ctrl+Shift+R)"
