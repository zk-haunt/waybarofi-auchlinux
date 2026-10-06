#!/usr/bin/env bash
# Auchlinux System & Packages Bootstrap Script

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "\n${BLUE}[+] $*${NC}\n"; }
warn() { echo -e "\n${YELLOW}[!] $*${NC}\n"; }
error() { echo -e "\n${RED}[✗] ERROR: $*${NC}\n" >&2; exit 1; }

usage() {
    cat <<'EOT'
Usage: ./install-packages.sh [OPTIONS]

Options:
  --no-aur      Skip everything that touches the AUR: no AUR helper is looked
                for, built or required, and no AUR packages are installed.
                Official (pacman) packages, Flatpak, dotfiles and the system
                tweaks all still run.
                The same choice is offered as option 3 at the AUR helper
                prompt, if you'd rather decide once you get there.
  -h, --help    Show this help and exit.

Environment:
  NO_AUR=1                          Same as --no-aur.
  AUR_HELPER_CHOICE=paru|yay|none   Answer the helper prompt non-interactively;
                                    'none' skips the AUR. Ignored when the AUR
                                    is already disabled.
EOT
}

# --no-aur exists for machines that should stay on official repos only — a work
# box where unreviewed PKGBUILDs aren't allowed, a quick container/VM run where
# compiling paru costs more than the AUR packages are worth, or any host without
# base-devel. Everything AUR-related is then bypassed, not merely tolerated: the
# script never probes for a helper and never fails on a missing one.
case "${NO_AUR:-}" in
    1|true|yes|on) NO_AUR=1 ;;
    *)             NO_AUR=0 ;;
esac

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-aur)  NO_AUR=1 ;;
        -h|--help) usage; exit 0 ;;
        *)         echo "Unknown option: $1" >&2; echo >&2; usage >&2; exit 1 ;;
    esac
    shift
done

# Verify we are NOT running as root (since yay/paru AUR helpers cannot run as
# root — and even with --no-aur this installs Flatpaks/fonts/configs into $HOME)
if [[ $EUID -eq 0 ]]; then
    error "Do not run this script as root! Sudo permissions will be requested when needed."
fi

# Ensure running in Arch Linux
if [[ ! -f /etc/arch-release ]]; then
    error "This script is designed for Arch Linux only."
fi

# 1. Update pacman databases
info "Updating Arch package databases..."
# -Syu, NOT -Sy. A bare -Sy refreshes the package databases without upgrading,
# so the subsequent `pacman -S` installs packages built against libraries newer
# than the ones on disk — the classic Arch partial-upgrade breakage, which on a
# host left idle for a few weeks can produce an unbootable system.
#
# informant (installed in step 3) adds a pacman hook that aborts every upgrade
# while Arch news is unread. Under `set -e` that would end this script with only
# pacman's terse hook error, so on a re-run check first and say why.
if command -v informant &>/dev/null && ! sudo informant check >/dev/null 2>&1; then
    error "informant check failed — most likely unread Arch news, which blocks upgrades.
    Read it with: sudo informant read   (sudo informant check shows the reason)
    then re-run this script."
fi
sudo pacman -Syu --noconfirm

# 2. Check/Install AUR helper (paru preferred)
AUR_HELPER=""
[[ $NO_AUR -eq 1 ]] || info "Checking for AUR Helper..."
# Actually RUN each helper rather than using `command -v`. A paru-bin left over
# from before a pacman soname bump still exists and is executable — `command -v`
# passes — but every invocation dies with "error while loading shared libraries:
# libalpm.so.15". Running --version is the only way to tell a working helper from
# a present-but-broken one.
if [[ $NO_AUR -eq 1 ]]; then
    info "AUR disabled (--no-aur) — no helper needed, AUR packages will be skipped."
elif paru --version &>/dev/null; then
    AUR_HELPER="paru"
    info "Found 'paru' as AUR helper."
elif yay --version &>/dev/null; then
    AUR_HELPER="yay"
    info "Found 'yay' as AUR helper — using it rather than installing a second helper."
else
    if command -v paru &>/dev/null || command -v yay &>/dev/null; then
        warn "An AUR helper is installed but does NOT run (usually a prebuilt"
        warn "*-bin package linked against an old libalpm)."
    else
        warn "No AUR helper found."
    fi

    # Ask which helper to build. Both are offered because either can fail on a
    # given day: an AUR build breaks, a dependency won't resolve, upstream moves.
    # Having the fallback one keypress away beats editing the script mid-install.
    # Option 3 is the same thing --no-aur does, offered here because this prompt
    # is where you find out you'd have to compile a helper — deciding it isn't
    # worth it should not mean Ctrl-C and a re-run with a different flag.
    # Override non-interactively with:  AUR_HELPER_CHOICE=yay ./install-packages.sh
    HELPER_CHOICE="${AUR_HELPER_CHOICE:-}"
    if [[ -z "$HELPER_CHOICE" ]]; then
        if [[ -t 0 ]]; then
            echo
            echo "  Which AUR helper should be installed?"
            echo "    1) paru  (Rust)  — default"
            echo "    2) yay   (Go)"
            echo "    3) none          — skip the AUR entirely (same as --no-aur)"
            echo
            read -rp "  Choice [1/2/3, default 1]: " reply
            case "${reply}" in
                2|yay|Yay|YAY)             HELPER_CHOICE="yay" ;;
                3|n|no|none|None|NONE|skip) HELPER_CHOICE="none" ;;
                *)                          HELPER_CHOICE="paru" ;;
            esac
        else
            HELPER_CHOICE="paru"
            info "Non-interactive shell — defaulting to paru."
        fi
    fi

    if [[ "$HELPER_CHOICE" == "none" ]]; then
        NO_AUR=1
        warn "Continuing without an AUR helper — AUR packages will be skipped."
    else

        # Build from SOURCE (`paru` / `yay`), never the prebuilt `-bin` variants.
        # A *-bin package is linked against one libalpm soname; when pacman bumps
        # it (e.g. .so.15 -> .so.16) the binary dies with "error while loading
        # shared libraries" until its maintainer rebuilds. Source builds link
        # against the pacman actually installed, so a fresh install can't land
        # broken. Costs a few minutes of Rust (paru) or Go (yay) compilation on
        # first run — both toolchains are already there if you ran
        # scripts/dev-utils.sh first.
        info "Installing '$HELPER_CHOICE' from source..."
        sudo pacman -S --needed --noconfirm base-devel git

        build_dir=$(mktemp -d)
        git clone "https://aur.archlinux.org/${HELPER_CHOICE}.git" "$build_dir"
        cd "$build_dir"
        makepkg -si --noconfirm
        cd - >/dev/null
        rm -rf "$build_dir"

        if ! "$HELPER_CHOICE" --version &>/dev/null; then
            error "'$HELPER_CHOICE' was built but does not run. Try the other helper: AUR_HELPER_CHOICE=$([[ $HELPER_CHOICE == paru ]] && echo yay || echo paru) ./install-packages.sh — or skip the AUR with ./install-packages.sh --no-aur"
        fi

        AUR_HELPER="$HELPER_CHOICE"
        info "Successfully installed '$AUR_HELPER'."
    fi
fi

# 3. Official packages to install
OFFICIAL_PKGS=(
    # Compositor & Shell Environment
    hyprland
    waybar
    rofi
    swaync
    hyprlock
    hypridle
    hyprpolkitagent
    hyprpicker
    awww
    uwsm
    
    # Core User Space Applications
    kitty
    dolphin
    ark
    keepassxc
    imv
    mpv
    cava
    code
    neovim
    yazi
    chromium
    signal-desktop
    telegram-desktop
    discord
    
    # System Command Utilities
    fastfetch
    starship
    zsh
    btop
    jq
    rsync
    curl
    wget
    pamixer
    playerctl
    libnotify
    brightnessctl
    network-manager-applet
    flatpak
    pacman-contrib
    udiskie
    unzip
    fzf
    
    # Additional CLI Utilities (used by scripts & zsh configs)
    eza
    zoxide
    bat
    ripgrep
    fd
    duf
    wtype
    cliphist
    arch-audit
    hyprsunset
    wf-recorder
    pavucontrol
    power-profiles-daemon
    xdg-utils
    
    # Clipboard & Screenshot Stack
    grim
    slurp
    swappy
    satty
    wl-clipboard
    wl-clip-persist
    tesseract
    tesseract-data-eng
    zbar
    
    # Theme & Display managers
    nwg-look
    nwg-displays
    qt5ct
    qt6ct
    kvantum
    kvantum-qt5
    imagemagick
    xsettingsd
    papirus-icon-theme
    matugen
    rofi-calc
    
    # Portal support (Screen sharing/file pickers)
    xdg-desktop-portal-hyprland
    xdg-desktop-portal-gtk
    
    # Audio server configuration
    wireplumber
    pipewire
    pipewire-alsa
    pipewire-pulse
    pipewire-jack
    pipewire-audio
    gst-plugin-pipewire

    
    # Bluetooth stack
    bluez
    bluez-utils
    blueman

    # VPN (WireGuard profiles imported into NetworkManager via nmcli)
    wireguard-tools

    # ProtonVPN, from `extra` rather than the Flathub build. Proton's own docs
    # call the Flatpak third-party-maintained with "support may be limited" and
    # the same limitations as their Snap: no Proton Protocols (Smart Protocol,
    # Stealth), no split tunnelling. The native package is the same version
    # (4.18.2) with none of that, and this repo's own rule in plansecurity.md P3
    # is "native is fine for official-repo open-source".
    proton-vpn-gtk-app
    # proton-vpn-cli

    # Security tooling, applied by step 9.
    audit           # auditd — kernel audit log (plansecurity.md P4)
    fwupd           # firmware updates; step 9 enables the metadata refresh timer
    lynis           # security auditor; `sudo lynis audit system` for a baseline
    informant       # Arch news gate: a pacman hook that stops -Syu until unread
                    # news is read with `sudo informant read`. Do NOT join the
                    # `informant` group — see step 9.

    # Firewall. ufw's own before.rules/before6.rules already cover loopback
    # anti-spoofing, established/related, the ICMPv4 set, the full ICMPv6
    # neighbour/router-discovery set and the DHCP client — which is why the
    # hand-written nftables ruleset this replaced was largely redundant.
    # Enabling it is a manual step; see plansecurity.md P1.
    ufw

    # Compressed swap in RAM, set up by step 11 (scripts/zram.sh).
    zram-generator
    
    # Zsh configuration plugins
    zsh-autosuggestions
    zsh-syntax-highlighting
    
    # Fonts
    ttf-jetbrains-mono-nerd
    inter-font
    noto-fonts
    noto-fonts-cjk
    noto-fonts-emoji

    # Camera & webcam (physical webcam + phone-as-webcam pipeline)
    v4l-utils              # v4l2-ctl: list/configure capture devices
    v4l2loopback-dkms      # virtual /dev/video for phone/OBS virtual cameras
    linux-zen-headers      # required to build the v4l2loopback dkms module (zen kernel)
    guvcview               # GUI webcam viewer / control panel
    obs-studio             # advanced capture/streaming + virtual camera
    scrcpy                 # phone mirroring + USB camera source (--v4l2-sink)
    android-udev    # udev rules so adb can claim a plugged-in phone. Without
                    # these the device shows as "no permissions" or does not
                    # appear in `adb devices` at all, which looks like a broken
                    # cable rather than a missing package.
    android-tools          # adb: USB/Wi-Fi device bridge for scrcpy & port-forward
)

# 4. AUR packages to install
AUR_PKGS=(
    pyprland
    ttf-material-symbols-variable-git
    zsh-256color
    grimblast-git
    droidcam                # phone-as-webcam client (Wi-Fi/USB)
    sndcpy                  # forward Android audio over USB (older phones; scrcpy 2.0+ does it natively)
)

# Install official packages
info "Installing official packages via pacman..."
sudo pacman -S --needed --noconfirm "${OFFICIAL_PKGS[@]}"

# Install AUR packages
if [[ $NO_AUR -eq 1 ]]; then
    warn "Skipping ${#AUR_PKGS[@]} AUR package(s) (--no-aur)."
else
    info "Installing AUR packages via ${AUR_HELPER}..."
    "$AUR_HELPER" -S --needed --noconfirm "${AUR_PKGS[@]}"
fi

# 5. Flatpak configuration and apps
#
# Everything here is --user on purpose. System and user flatpaks are separate
# ostree repos, so each scope keeps its OWN copy of the shared runtimes
# (freedesktop Platform + Mesa + codecs ≈ 1.6G). Mixing scopes silently pays
# that twice: this machine ended up with Zen installed --system by hand while
# the repo installed Brave --user, so both stacks exist side by side.
# One scope also means no root for updates, and a single set of Flatseal
# permissions to trim (plansecurity.md P3).
#
# Only list APPS. The runtimes (org.freedesktop.Platform, .GL.default,
# .codecs-extra) are pulled in automatically from each app's manifest — naming
# them here would pin versions flatpak should be choosing itself.
FLATPAK_APPS=(
    # Brave — the designated primary browser (plansecurity.md P7: one primary
    # browser, Shields replaces uBlock, aiming for zero extensions). Flatpak
    # because it is a closed-source-ish Chromium rebuild and a high-exposure app,
    # which is exactly the category P3 says to sandbox.
    com.brave.Browser

    # Zen — secondary browser. Same high-exposure reasoning as Brave. Was
    # installed --system by hand, which duplicated the whole runtime stack
    # (~1.6G); migrated to --user on 2026-10-02 so there is one scope to update
    # and one set of Flatseal permissions to trim.
    app.zen_browser.zen

    # Parsec — remote desktop / game streaming. Closed-source binary, so
    # sandboxing it is the point. Was installed by hand and missing from this
    # script entirely until 2026-10-02.
    com.parsecgaming.parsec

    # LocalSend — Wi-Fi file sharing. Flatpak rather than the AUR localsend-bin:
    # it is AUR-only natively, and plansecurity.md P3 says to Flatpak the AUR
    # apps. Also removes the only reason this script needed an AUR helper for a
    # desktop app. Needs port 53317 TCP+UDP opened — see P1.
    org.localsend.localsend_app

    # ProtonVPN — DELIBERATELY NOT USED. Kept here so the decision is visible
    # rather than re-made from scratch later. Use the native `proton-vpn-gtk-app`
    # + `proton-vpn-cli` from `extra` in OFFICIAL_PKGS above instead.
    #
    #   com.protonvpn.www
    #
    # Why native wins here, against the usual P3 "sandbox the high-exposure app"
    # instinct:
    #   1. Proton's own docs (protonvpn.com/support/linux-vpn-setup#limitations)
    #      call the Flathub build third-party-maintained — "support may be
    #      limited" — with "similar limitations as the Snap package".
    #   2. Those documented limitations are: no Proton Protocols (Smart Protocol
    #      AND Stealth), and no split tunnelling. Stealth is the one that matters
    #      on a network that blocks VPNs, which is the main reason to run one here.
    #   3. Identical version either way (4.18.2 at time of writing), so the
    #      sandbox costs features and buys nothing in freshness.
    #   4. It is GPL-3.0 and now in `extra`, so plansecurity.md P3's own rule
    #      applies: "native is fine for official-repo open-source".
    #   5. Size: 667 KiB / 5 MB native vs 32 MB / 89 MB flatpak.
    # Revisit only if it is dropped from `extra`, or if Proton starts shipping
    # Flathub themselves with feature parity.
)

info "Configuring Flatpak and installing apps..."
# Flathub, in the user scope. Note --system installs would fail with "remote not
# found" unless the remote is added there too; we deliberately don't.
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# -y plus --noninteractive so a missing-runtime prompt can't stall an unattended
# run. Installs are idempotent: an already-present app is a no-op.
for _app in "${FLATPAK_APPS[@]}"; do
    info "  flatpak: $_app"
    flatpak install --user --noninteractive -y flathub "$_app"
done

# Per-app sandbox overrides.
#
# This is the opposite of the usual Flatseal chore: plansecurity.md P3 is about
# TRIMMING permissions, and the apps above mostly ship sensible ones already.
# So most entries here WIDEN access where the shipped sandbox is too tight to
# use; Brave is the exception that gets trimmed. Each one states why — a
# permission without a reason is one nobody dares remove later.
#
# Format: "<app-id> <flatpak-override-args...>"
FLATPAK_OVERRIDES=(
    # LocalSend ships filesystems=xdg-download, so received files can only land
    # in ~/Downloads and anything sent from elsewhere has to go through a portal
    # file-picker dialog. Adding ~/Documents makes it usable for the common case
    # without handing over the whole home directory, which would undo the point
    # of sandboxing it. Widen further only if you actually need it:
    #   flatpak override --user --filesystem=home org.localsend.localsend_app
    "org.localsend.localsend_app --filesystem=~/Documents"

    # Brave is the one app here that ships MORE than it needs. Trimmed:
    #   ~/.local/share/applications (create) — the real one. Lets the sandboxed
    #       browser write .desktop launchers, and a launcher's Exec= line runs
    #       OUTSIDE the sandbox when clicked: a sandbox escape. Only used by
    #       "Install app" (PWAs); that stops adding launchers.
    #   ~/.local/share/icons (create) — the icons for those launchers.
    #   host-etc — read access to all of /etc. Only consulted for managed
    #       browser policies (/etc/brave/policies), which this setup has none of.
    #   /tmp — the host's shared /tmp; the sandbox gets a private one anyway.
    #   xdg-desktop — ~/Desktop, unused on Hyprland.
    # Kept: xdg-download, pipewire (audio/WebRTC), dconf/kioslaverc (theme and
    # proxy settings). Undo one with e.g.:
    #   flatpak override --user --filesystem=~/.local/share/applications:create com.brave.Browser
    # or all of them: flatpak override --user --reset com.brave.Browser
    "com.brave.Browser --nofilesystem=~/.local/share/applications --nofilesystem=~/.local/share/icons --nofilesystem=host-etc --nofilesystem=/tmp --nofilesystem=xdg-desktop"
)

if ((${#FLATPAK_OVERRIDES[@]})); then
    info "Applying Flatpak sandbox overrides..."
    for _ovr in "${FLATPAK_OVERRIDES[@]}"; do
        # Word-split deliberately: each entry is "<app-id> <args...>".
        # shellcheck disable=SC2086
        set -- $_ovr
        _id="$1"; shift
        # A --filesystem=~/Dir grant does nothing if the directory is absent, and
        # a fresh install has no XDG dirs yet, so create the ones we grant.
        for _arg in "$@"; do
            case "$_arg" in
                --filesystem=~/*) mkdir -p "${HOME}/${_arg#--filesystem=~/}" ;;
            esac
        done
        info "  override: $_id $*"
        flatpak override --user "$@" "$_id"
    done
fi

# If you previously installed any of these --system (check:
#   flatpak list --system --app
# ) the user copy above is an ADDITIONAL install, not a move. To reclaim the
# duplicated runtimes afterwards:
#   flatpak uninstall --system <app-id>
#   flatpak uninstall --system --unused

# 6. Apply dotfiles configurations using apply-config.sh
if [[ -f "./scripts/apply-config.sh" ]]; then
    info "Applying repository dotfiles/configs to ~/.config..."
    chmod +x ./scripts/apply-config.sh
    ./scripts/apply-config.sh
fi

# 7. Install Custom Nerd Fonts if archive exists
FONTS_TAR="./scripts/assets/Custom_Nerd_Fonts.tar.gz"
TARGET_DIR="$HOME/.local/share/fonts"
if [[ -f "$FONTS_TAR" ]]; then
    info "Installing custom Nerd Fonts..."
    mkdir -p "$TARGET_DIR"
    tar -xzf "$FONTS_TAR" -C "$TARGET_DIR"
    fc-cache -f "$TARGET_DIR"
    info "Custom Nerd Fonts installed successfully."
fi

# 8. v4l2loopback virtual webcam — auto-create a /dev/video10 "Phone Camera"
#    so phone-camera.sh can stream into it without needing sudo at runtime.
if pacman -Qq v4l2loopback-dkms &>/dev/null; then
    info "Configuring v4l2loopback virtual webcam (/dev/video10)..."
    echo 'options v4l2loopback devices=1 video_nr=10 card_label="Phone Camera" exclusive_caps=1' \
        | sudo tee /etc/modprobe.d/v4l2loopback.conf >/dev/null
    echo 'v4l2loopback' | sudo tee /etc/modules-load.d/v4l2loopback.conf >/dev/null
    sudo modprobe v4l2loopback 2>/dev/null \
        && info "v4l2loopback loaded (virtual cam ready; persists across reboots)." \
        || warn "v4l2loopback will load on next reboot (module just built by dkms)."
fi

# 9. System hardening — scripts/harden-system.sh: ufw, sysctl, coredumps off,
#     removable-media options, unused kernel modules blocked, auditd + rules,
#     time sync, /boot root-only, fwupd metadata timer, informant group check.
#     Kept as a separate script so it can be re-run on its own after editing
#     anything under config/etc/; the reasons for each piece live there.
./scripts/harden-system.sh || warn "System hardening reported an error — re-run ./scripts/harden-system.sh to see it."

# 10. Bluetooth — don't power the radio on by itself. bluetoothd still runs
#     (so the blueman tray icon works without root), but the radio stays off
#     until it's toggled manually from the tray.
#
#     Two settings, because they cover different events:
#       AutoEnable=false  — stops bluetoothd powering adapters when IT starts
#                           (boot). Does nothing on resume, since bluetoothd
#                           doesn't restart there.
#       rfkill block      — the kill-switch layer, which systemd-rfkill saves to
#                           /var/lib/systemd/rfkill/ and replays on every boot
#                           AND every resume from suspend. Without this, waking
#                           the laptop turns the radio back on.
#     Toggling from the blueman tray unblocks it and systemd-rfkill remembers
#     that, so a manual "on" still persists the way you'd expect.
info "Configuring Bluetooth (radio off until toggled via blueman)..."
sudo systemctl enable bluetooth.service
sudo sed -i -E 's/^#?AutoEnable=.*/AutoEnable=false/' /etc/bluetooth/main.conf
sudo rfkill block bluetooth

# 11. Swap: zram — compressed swap in RAM, no disk writes. Without any swap,
#     idle memory can never leave RAM and the OOM killer fires on ordinary
#     peaks; scripts/zram.sh has the measured reasons and also turns zswap off.
info "Setting up zram swap..."
./scripts/zram.sh || warn "zram setup failed — run ./scripts/zram.sh by hand."

info "Bootstrap complete! Reboot now to load into Hyprland."
cat <<'EOT'
  Optional setups are separate scripts — run them when you want them:
    ./scripts/steam/steam.sh                  Steam + Vulkan GPU drivers
    ./scripts/virt/virt-manager.sh            QEMU/KVM + virt-manager
    ./scripts/easyeffects/easyeffects.sh      EasyEffects audio EQ + presets
    ./scripts/vtube/vtube.sh setup                  VTube face-tracking pipeline

EOT

# Listed last so it's the final thing on screen: with --no-aur some configs
# reference binaries that were never installed (grimblast for screenshots,
# pyprland for scratchpads), and that's a lot easier to debug now than after
# a reboot into Hyprland.
if [[ $NO_AUR -eq 1 ]]; then
    warn "Ran with --no-aur — these AUR packages were NOT installed:"
    printf '      %s\n' "${AUR_PKGS[@]}"
    echo
    echo "  Anything in the configs that depends on them will not work until"
    echo "  they're installed. To add them later, re-run without the flag:"
    echo "      ./install-packages.sh"
    echo "  (pacman/flatpak steps are idempotent, so only the AUR part is new work.)"
    echo
fi
