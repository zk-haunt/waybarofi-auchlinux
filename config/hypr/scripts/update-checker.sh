#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  update-checker.sh  —  pending pacman/AUR/flatpak updates for Waybar
#  --status : print the JSON payload for the custom/updates module
#  (no args): open a terminal and run the full system upgrade
#  Behaviour ported from lol's HyDE `system.update.sh` — click opens
#  kitty and runs the real upgrade (no rofi picker), just done directly
#  instead of via hyde-shell.
# ─────────────────────────────────────────────────────────────


# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

AUR_HELPER=""
for helper in paru yay; do
    command -v "$helper" &>/dev/null && AUR_HELPER="$helper" && break
done

OFFICIAL_COUNT=$(checkupdates 2>/dev/null | grep -c '\S')
AUR_COUNT=0
[[ -n "$AUR_HELPER" ]] && AUR_COUNT=$("$AUR_HELPER" -Qua 2>/dev/null | grep -c '\S')
FLATPAK_COUNT=0
command -v flatpak &>/dev/null && FLATPAK_COUNT=$(flatpak remote-ls --updates 2>/dev/null | grep -c '\S')

COUNT=$((OFFICIAL_COUNT + AUR_COUNT + FLATPAK_COUNT))

# Called with --status: print JSON for Waybar
if [[ "${1:-}" == "--status" ]]; then
    if [[ "$COUNT" -eq 0 ]]; then
        echo '{"text":"","tooltip":" Packages are up to date","class":"up-to-date"}'
    else
        tooltip="󱓽 Official $OFFICIAL_COUNT\n󱓾 AUR $AUR_COUNT"
        [[ "$FLATPAK_COUNT" -gt 0 ]] && tooltip+="\n󰏓 Flatpak $FLATPAK_COUNT"
        echo "{\"text\":\"󰮯 $COUNT\",\"tooltip\":\"$tooltip\",\"class\":\"has-updates\"}"
    fi
    exit 0
fi

# Called without args (waybar on-click): open a terminal and run the full
# system upgrade — official + AUR via the AUR helper's -Syu, then flatpak,
# exactly like lol's system.update.sh "up" path. No rofi picker.
if [[ "$COUNT" -eq 0 ]]; then
    notify-send "System up to date" "No pending updates found." -i system-software-update
    exit 0
fi

# Build the upgrade command that runs inside the terminal.
# Same three glyphs as the waybar tooltip above; the terminal banner had lost
# them and was printing a bare two-space indent instead.
upgrade_cmd="printf '\\n󱓽 Official %s   󱓾 AUR %s   󰏓 Flatpak %s\\n\\n' '$OFFICIAL_COUNT' '$AUR_COUNT' '$FLATPAK_COUNT'; "
# informant's pacman hook refuses to upgrade while Arch news is unread, and
# pacman then exits with a terse "failed to run hook" error. Show the news here
# first — `sudo informant read` prints each item and marks it read — so the
# upgrade below goes through. Unprivileged `informant check` works (it only
# warns about the root-owned HTTP cache, hence 2>/dev/null) and exits non-zero
# while anything is unread.
if command -v informant &>/dev/null; then
    upgrade_cmd+="if ! informant check >/dev/null 2>&1; then printf '󰎕 Unread Arch news — read it before upgrading:\\n\\n'; sudo informant read; printf '\\n'; fi; "
fi
# ok tracks the package upgrade, so the banner below can't claim success when
# pacman refused (news gate, conflict, Ctrl-C) and installed nothing.
if [[ -n "$AUR_HELPER" ]]; then
    # paru/yay -Syu upgrades official repos AND the AUR in one pass.
    upgrade_cmd+="if $AUR_HELPER -Syu; then ok=1; else ok=0; fi; "
else
    upgrade_cmd+="if sudo pacman -Syu; then ok=1; else ok=0; fi; "
fi
if command -v flatpak &>/dev/null && [[ "$FLATPAK_COUNT" -gt 0 ]]; then
    upgrade_cmd+="flatpak update; "
fi
upgrade_cmd+="if [ \"\$ok\" = 1 ]; then printf '\\n󰄬 Upgrade finished. Press any key to close...'; "
upgrade_cmd+="else printf '\\n󰅙 Package upgrade did NOT complete — see the output above. Press any key to close...'; fi; "
upgrade_cmd+="read -n 1"

kitty --title systemupdate sh -c "$upgrade_cmd"
