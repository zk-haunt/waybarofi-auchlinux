#!/usr/bin/env bash
# =============================================================================
#  Terminal & Zsh Setup Script for Arch Linux
#  Run this after a fresh install to get the full themed shell & terminal experience.
#  Includes: oh-my-zsh, autosuggestions, syntax-highlighting, Starship,
#            theme switcher, custom Nerd Fonts, fzf, eza, fastfetch
#
#  Usage: ./scripts/term-n-font.sh
#  From the auchlinux repo root.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ZDOTDIR="$HOME/.config/zsh"
OMZ_DIR="$HOME/.config/zsh/ohmyzsh"

# ─── Color helpers ────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
section() { echo -e "\n${BOLD}━━━ $* ━━━${RESET}"; }

# ─── 1. Required packages ─────────────────────────────────────────────────────
section "Checking / Installing required packages"

PACMAN_PKGS=(
    zsh starship eza fzf fastfetch zoxide bat ripgrep fd git curl rsync
)

info "Checking pacman packages..."
MISSING_PACMAN=()
for pkg in "${PACMAN_PKGS[@]}"; do
    pacman -Q "$pkg" &>/dev/null || MISSING_PACMAN+=("$pkg")
done
if [[ ${#MISSING_PACMAN[@]} -gt 0 ]]; then
    info "Installing missing: ${MISSING_PACMAN[*]}"
    sudo pacman -S --needed --noconfirm "${MISSING_PACMAN[@]}"
else
    ok "All pacman packages already installed"
fi

# ─── 2. Default shell → Zsh ──────────────────────────────────────────────────
section "Setting default shell to Zsh"
CURRENT_SHELL="$(getent passwd "$USER" | cut -d: -f7)"
if [[ "$CURRENT_SHELL" != "/bin/zsh" && "$CURRENT_SHELL" != "/usr/bin/zsh" ]]; then
    chsh -s "$(command -v zsh)" "$USER"
    ok "Default shell changed to zsh — re-login to apply"
else
    ok "Default shell is already zsh ($CURRENT_SHELL)"
fi

# ─── 3. ZDOTDIR in ~/.zshenv ─────────────────────────────────────────────────
section "Configuring ZDOTDIR"
if ! grep -q 'ZDOTDIR' "$HOME/.zshenv" 2>/dev/null; then
    echo 'export ZDOTDIR="$HOME/.config/zsh"' >> "$HOME/.zshenv"
    ok "Added ZDOTDIR export to ~/.zshenv"
else
    ok "ZDOTDIR already configured in ~/.zshenv"
fi

# ─── 4. Deploy dotfiles from repo ────────────────────────────────────────────
section "Deploying config files from repo"
info "Running apply-config.sh for zsh, starship, kitty..."
"$SCRIPT_DIR/apply-config.sh" zsh starship kitty
ok "Config files deployed"

# ─── 4a. Install custom Nerd Fonts ────────────────────────────────────────────
section "Installing custom Nerd Fonts"
FONTS_TAR="$REPO_DIR/scripts/assets/Custom_Nerd_Fonts.tar.gz"
TARGET_DIR="$HOME/.local/share/fonts"

if [[ -f "$FONTS_TAR" ]]; then
    info "Extracting custom Nerd Fonts to $TARGET_DIR..."
    mkdir -p "$TARGET_DIR"
    tar -xzf "$FONTS_TAR" -C "$TARGET_DIR"
    info "Updating system font cache..."
    fc-cache -f "$TARGET_DIR"
    ok "Custom Nerd Fonts installed successfully"
else
    warn "Custom Nerd Fonts archive not found at $FONTS_TAR — skipping font setup"
fi

# ─── 5. Install oh-my-zsh ────────────────────────────────────────────────────
section "Installing oh-my-zsh"
if [[ -f "$OMZ_DIR/oh-my-zsh.sh" ]]; then
    ok "oh-my-zsh already installed at $OMZ_DIR"
else
    info "Installing oh-my-zsh (no chsh, no .zshrc override)..."
    # Download to a file first. Piping curl straight into `sh -c "$(...)"` hides
    # network failures: curl returns non-zero, the substitution expands to an
    # empty string, `sh -c ""` exits 0, and the script reports success while
    # installing nothing. The shell that boots afterwards then falls through to
    # "No plugin system found" with no hint about what actually went wrong.
    omz_installer="$(mktemp)"
    trap 'rm -f "$omz_installer"' EXIT
    if ! curl -fsSL --max-time 60 \
            https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh \
            -o "$omz_installer"; then
        warn "Could not download the oh-my-zsh installer (network?)."
        warn "Re-run this script once you're online — everything else is unaffected."
        exit 1
    fi
    [[ -s "$omz_installer" ]] || { warn "Downloaded oh-my-zsh installer is empty."; exit 1; }

    ZSH="$OMZ_DIR" sh "$omz_installer" "" --unattended --keep-zshrc || true

    # Verify what we actually got, not what the installer claimed.
    if [[ ! -f "$OMZ_DIR/oh-my-zsh.sh" ]]; then
        warn "oh-my-zsh install did not produce $OMZ_DIR/oh-my-zsh.sh"
        warn "Without it, zsh starts bare and prints 'No plugin system found'."
        exit 1
    fi
    ok "oh-my-zsh installed"
fi

# Symlink so HyDE's plugin loader finds it at the expected path
if [[ ! -e "$HOME/.oh-my-zsh" ]]; then
    ln -sf "$OMZ_DIR" "$HOME/.oh-my-zsh"
    ok "Symlinked ~/.oh-my-zsh → $OMZ_DIR"
elif [[ -L "$HOME/.oh-my-zsh" ]]; then
    ok "~/.oh-my-zsh symlink already exists"
else
    warn "~/.oh-my-zsh is a real dir — leaving it. OMZ may already be installed elsewhere."
fi

# ─── 6. Install zsh plugins ──────────────────────────────────────────────────
section "Installing zsh plugins"
CUSTOM_PLUGINS="$OMZ_DIR/custom/plugins"
mkdir -p "$CUSTOM_PLUGINS"

install_plugin() {
    local name="$1" url="$2"
    if [[ -d "$CUSTOM_PLUGINS/$name/.git" ]]; then
        info "Updating plugin: $name"
        git -C "$CUSTOM_PLUGINS/$name" pull --quiet || warn "Failed to update $name"
        ok "$name up to date"
    else
        [[ -d "$CUSTOM_PLUGINS/$name" ]] && rm -rf "$CUSTOM_PLUGINS/$name"
        info "Cloning plugin: $name"
        git clone --depth=1 "$url" "$CUSTOM_PLUGINS/$name"
        ok "$name installed"
    fi
}

install_plugin "zsh-autosuggestions"      "https://github.com/zsh-users/zsh-autosuggestions"
install_plugin "zsh-syntax-highlighting"  "https://github.com/zsh-users/zsh-syntax-highlighting"
install_plugin "zsh-256color"             "https://github.com/chrissicool/zsh-256color"

# ─── 7. Ensure zsh dirs exist ────────────────────────────────────────────────
section "Setting up zsh support directories"
mkdir -p "$ZDOTDIR/functions"
mkdir -p "$ZDOTDIR/completions"
ok "functions/ and completions/ ready"

# ─── 8. Theme mode file ──────────────────────────────────────────────────────
section "Setting default theme (lol)"
THEME_FILE="$ZDOTDIR/zsh_theme_mode"
if [[ ! -f "$THEME_FILE" ]]; then
    echo "lol" > "$THEME_FILE"
    ok "Theme mode set to: lol"
else
    ok "Theme mode already set to: $(cat "$THEME_FILE")"
fi

# ─── 9. Starship config symlink ──────────────────────────────────────────────
section "Linking Starship config"
CURRENT_MODE="$(cat "$THEME_FILE" 2>/dev/null || echo lol)"
STARSHIP_SRC="$HOME/.config/starship/starship_${CURRENT_MODE}.toml"
STARSHIP_LINK="$HOME/.config/starship/starship.toml"

if [[ -f "$STARSHIP_SRC" ]]; then
    ln -sf "$STARSHIP_SRC" "$STARSHIP_LINK"
    ok "Starship → starship_${CURRENT_MODE}.toml"
else
    ln -sf "$HOME/.config/starship/starship_lol.toml" "$STARSHIP_LINK"
    warn "starship_${CURRENT_MODE}.toml not found — fell back to lol"
fi

# ─── 9a. Linking Fastfetch config ──────────────────────────────────────────
section "Linking Fastfetch config"
FASTFETCH_SRC="$HOME/.config/fastfetch/config_${CURRENT_MODE}.jsonc"
FASTFETCH_LINK="$HOME/.config/fastfetch/config.jsonc"

if [[ -f "$FASTFETCH_SRC" ]]; then
    ln -sf "$FASTFETCH_SRC" "$FASTFETCH_LINK"
    ok "Fastfetch → config_${CURRENT_MODE}.jsonc"
else
    ln -sf "$HOME/.config/fastfetch/config_lol.jsonc" "$FASTFETCH_LINK"
    warn "config_${CURRENT_MODE}.jsonc not found — fell back to lol"
fi

# ─── 9c. Linking default Rofi theme config ──────────────────────────────────
section "Linking default Rofi theme config"
ROFI_THEME_FILE="$HOME/.config/rofi/launcher/rofi_theme_mode"
ROFI_THEME_SRC="$HOME/.config/rofi/launcher/style_auch.rasi"
ROFI_THEME_LINK="$HOME/.config/rofi/launcher/style.rasi"

if [[ ! -f "$ROFI_THEME_FILE" ]]; then
    echo "auch" > "$ROFI_THEME_FILE"
    ok "Rofi theme mode set to: auch"
else
    ok "Rofi theme mode already set to: $(cat "$ROFI_THEME_FILE")"
fi

if [[ -f "$ROFI_THEME_SRC" ]]; then
    ln -sf "$ROFI_THEME_SRC" "$ROFI_THEME_LINK"
    ok "Rofi theme linked successfully"
else
    warn "Rofi theme source not found — skipping Rofi theme link"
fi

# ─── 9b. Sync pacman file database (needed for command_not_found_handler)
section "Syncing pacman file database"
if sudo pacman -Fy --noconfirm 2>/dev/null; then
    ok "pacman file database synced (enables package search on unknown commands)"
else
    warn "Could not sync pacman -F database. Run: sudo pacman -Fy"
fi

# ─── 10. Clear stale completion cache ────────────────────────────────────────
section "Clearing zsh completion cache"
rm -f "$ZDOTDIR"/.zcompdump* 2>/dev/null || true
ok "Cache cleared (rebuilds automatically on next start)"

# ─── 11. Verify ──────────────────────────────────────────────────────────────
section "Verification"
echo ""
check() { command -v "$1" &>/dev/null && echo "✓" || echo "✗"; }
chk_dir() { [[ -d "$1" ]] && echo "✓" || echo "✗"; }

printf "  %-34s %s\n" "Default shell"               "$(getent passwd "$USER" | cut -d: -f7)"
printf "  %-34s %s\n" "oh-my-zsh"                   "$([[ -f "$OMZ_DIR/oh-my-zsh.sh" ]] && echo "✓ $OMZ_DIR" || echo "✗ MISSING")"
printf "  %-34s %s\n" "zsh-autosuggestions"          "$(chk_dir "$CUSTOM_PLUGINS/zsh-autosuggestions")"
printf "  %-34s %s\n" "zsh-syntax-highlighting"      "$(chk_dir "$CUSTOM_PLUGINS/zsh-syntax-highlighting")"
printf "  %-34s %s\n" "zsh-256color"                 "$(chk_dir "$CUSTOM_PLUGINS/zsh-256color")"
printf "  %-34s %s\n" "starship"                     "$(check starship) $(starship --version 2>/dev/null | head -1 || echo)"
printf "  %-34s %s\n" "eza"                           "$(check eza)"
printf "  %-34s %s\n" "fzf"                           "$(check fzf) $(fzf --version 2>/dev/null || echo)"
printf "  %-34s %s\n" "fastfetch"                    "$(check fastfetch)"
printf "  %-34s %s\n" "Active theme"                 "$(cat "$THEME_FILE" 2>/dev/null || echo lol)"
printf "  %-34s %s\n" "Starship config linked"        "$([[ -L "$STARSHIP_LINK" ]] && readlink "$STARSHIP_LINK" | xargs basename || echo "✗ NOT linked")"
echo ""

section "All done!"
echo -e "${GREEN}Zsh is fully configured!${RESET} Open a new terminal to see it."
echo ""
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║               Theme Switcher Reference               ║"
echo "  ╠══════════════════════════════════════════════════════╣"
echo "  ║  Keybind: Super + Alt + T  or  Super + Shift + T    ║"
echo "  ║  Cycles:  lol → newpr → onmeds → end4 → lol          ║"
echo "  ╠══════════════════════════════════════════════════════╣"
echo "  ║  lol     │ Starship (lol)         + fastfetch        ║"
echo "  ║  newpr   │ Starship (Minimalist)  + fastfetch        ║"
echo "  ║  onmeds  │ Starship (Powerline)   + fastfetch        ║"
echo "  ║  end4    │ Starship (End4)        + fastfetch        ║"
echo "  ╚══════════════════════════════════════════════════════╝"
echo ""
