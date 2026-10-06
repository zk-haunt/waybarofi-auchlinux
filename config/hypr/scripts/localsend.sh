#!/usr/bin/env bash
# Launch / focus LocalSend (cross-platform Wi-Fi file sharing).
# Uses port 53317 (TCP+UDP). The firewall is ufw and defaults to deny-inbound,
# so transfers will not arrive until the port is opened:
#     sudo ufw allow 53317/tcp && sudo ufw allow 53317/udp
# (TCP carries transfers, UDP carries peer discovery — both halves needed.)
# Symptom when blocked: this laptop never shows up in the other device's list.
# Install route: the FLATPAK (org.localsend.localsend_app), not the AUR
# localsend-bin. LocalSend is AUR-only natively and plansecurity.md P3 says to
# Flatpak the AUR apps; it also means no paru dependency and no Flutter build.
# Native binaries are still probed first so an existing AUR install keeps
# working: localsend-bin names it `localsend_app`, source builds `localsend`.
set -uo pipefail

FLATPAK_ID="org.localsend.localsend_app"

launch=""
for c in localsend_app localsend; do
    command -v "$c" &>/dev/null && { launch="$c"; break; }
done
# Fall back to the flatpak. --user first (how install-packages.sh installs it),
# then the system scope, so a hand-installed system copy still launches.
if [ -z "$launch" ] && command -v flatpak &>/dev/null; then
    if flatpak info --user "$FLATPAK_ID" &>/dev/null || flatpak info "$FLATPAK_ID" &>/dev/null; then
        launch="flatpak run $FLATPAK_ID"
    fi
fi
[ -z "$launch" ] && {
    notify-send -u critical "LocalSend" "Not installed.\nflatpak install --user flathub $FLATPAK_ID"
    exit 1
}

# If a window is already open, focus it instead of spawning a second instance.
if command -v hyprctl &>/dev/null && hyprctl clients -j 2>/dev/null | grep -qi 'localsend'; then
    hyprctl dispatch 'hl.dsp.focus({ class = "^([Ll]ocalsend.*)$" })' >/dev/null 2>&1 \
        || hyprctl dispatch focuswindow "class:(?i)localsend" >/dev/null 2>&1
    exit 0
fi

# Unquoted on purpose: $launch may be "flatpak run <id>", i.e. several words.
# shellcheck disable=SC2086
exec $launch
