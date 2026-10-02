#!/bin/bash

# Instala/atualiza o WezTerm e sincroniza a configuração deste repositório
# em ~/.config/wezterm (usuário atual).
#
# Distros: Arch/Manjaro, Debian/Ubuntu/Mint, Fedora, openSUSE
#          (outras: Flatpak, se disponível)
#
# Uso: ./setup.sh            -> git pull + instala pacotes faltantes + aplica config
#      ./setup.sh --no-pull  -> pula o git pull

set -e

# ========================================
# CONFIGURAÇÕES
# ========================================
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST_DIR="$HOME/.config/wezterm"
FONT_NAME="Hack Nerd Font"
FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/latest/download/Hack.tar.xz"
FONT_DIR="$HOME/.local/share/fonts/HackNerdFont"

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
# 2. Instalar dependências, WezTerm e fonte
# ========================================
# Família da distro a partir de /etc/os-release (ID e ID_LIKE)
DISTRO=""
if [ -r /etc/os-release ]; then
    . /etc/os-release
    for id in $ID $ID_LIKE; do
        case "$id" in
            arch|manjaro)               DISTRO=arch;   break ;;
            debian|ubuntu)              DISTRO=debian; break ;;
            fedora|rhel|centos)         DISTRO=fedora; break ;;
            opensuse*|suse|sles)        DISTRO=suse;   break ;;
        esac
    done
fi
info "Distro detectada: ${PRETTY_NAME:-desconhecida} (${DISTRO:-sem suporte})"

# Instala pacotes com o gerenciador da distro
pkg_install() {
    case "$DISTRO" in
        arch)   sudo pacman -S --needed --noconfirm "$@" ;;
        debian) sudo apt-get install -y "$@" ;;
        fedora) sudo dnf install -y "$@" ;;
        suse)   sudo zypper --non-interactive install "$@" ;;
        *)      return 1 ;;
    esac
}

# Ferramentas usadas pelo setup e pelos scripts do footer
for cmd in rsync curl tar xz; do
    if ! command -v "$cmd" >/dev/null; then
        pkg="$cmd"
        [ "$cmd" = xz ] && [ "$DISTRO" = debian ] && pkg=xz-utils
        info "Instalando $pkg..."
        pkg_install "$pkg" || { error "Instale '$pkg' manualmente"; exit 1; }
    fi
done

install_flatpak() {
    if command -v flatpak >/dev/null; then
        warn "Instalando via Flatpak (scripts do footer podem não funcionar no sandbox)"
        flatpak install -y flathub org.wezfurlong.wezterm
    else
        warn "Instale o WezTerm manualmente: https://wezterm.org/install/linux.html"
        return 1
    fi
}

# --- WezTerm ---
if command -v wezterm >/dev/null; then
    info "WezTerm já instalado: $(wezterm --version)"
else
    info "Instalando WezTerm..."
    install_native() {
        case "$DISTRO" in
            arch|suse)
                pkg_install wezterm
                ;;
            debian)
                # Repositório apt oficial do WezTerm
                command -v gpg >/dev/null || pkg_install gnupg
                curl -fsSL https://apt.fury.io/wez/gpg.key \
                    | sudo gpg --yes --dearmor -o /usr/share/keyrings/wezterm-fury.gpg
                echo 'deb [signed-by=/usr/share/keyrings/wezterm-fury.gpg] https://apt.fury.io/wez/ * *' \
                    | sudo tee /etc/apt/sources.list.d/wezterm.list >/dev/null
                sudo apt-get update
                pkg_install wezterm
                ;;
            fedora)
                # COPR oficial do WezTerm
                sudo dnf install -y dnf-plugins-core 2>/dev/null || true
                sudo dnf copr enable -y wezfurlong/wezterm-nightly
                pkg_install wezterm
                ;;
            *)
                return 1
                ;;
        esac
    }
    if ! install_native; then
        [ -n "$DISTRO" ] && warn "Falha ao instalar pelo gerenciador da distro"
        install_flatpak || true
    fi
fi

# --- Fonte Hack Nerd Font ---
if fc-list : family 2>/dev/null | grep -q "$FONT_NAME"; then
    info "Fonte já instalada: $FONT_NAME"
elif [ "$DISTRO" = arch ]; then
    info "Instalando fonte: $FONT_NAME..."
    pkg_install ttf-hack-nerd
else
    # Sem pacote nas outras distros: baixa do repositório do Nerd Fonts
    info "Baixando fonte $FONT_NAME para $FONT_DIR..."
    mkdir -p "$FONT_DIR"
    curl -fsSL "$FONT_URL" | tar -xJ -C "$FONT_DIR"
    fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || true
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
