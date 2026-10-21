#!/usr/bin/env bash
# Wallpaper — a row in the hub dropdown (sec-picker.sh), after ppk's
# Wallpaper-Changer: pick from a thumbnail grid, go random, or rotate on a timer.
#
#   wall-menu.sh            the menu
#   wall-menu.sh --status   one JSON line for the hub row
#   wall-menu.sh random     a random wallpaper (what the rotation timer runs)
#
# Applying does what the older picker did: awww with a grow transition, the
# path saved to ~/.cache/current_wallpaper, matugen regenerating every colour
# file from it (kitty, Waybar, rofi, Hyprland, SwayNC, Yazi), and kitty told to
# reload its colours.
# Rotation is a systemd user timer this script writes when you turn it on
# (~/.config/systemd/user/auch-wallrotate.{service,timer}).

# -u and pipefail, but NOT -e — bound to clicks; see clipboard-menu.sh.
set -uo pipefail
MENU_APP="Wallpaper"; MENU_ICON="󰸉"
source "${BASH_SOURCE[0]%/*}/menu-lib.sh"

DIR="${AUCH_WALLPAPER_DIR:-$HOME/Pictures/wallpapers}"
STATE="$HOME/.cache/current_wallpaper"
UNITS="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
TIMER=auch-wallrotate.timer
SELF="$HOME/.config/hypr/scripts/wall-menu.sh"

walls()   { find "$DIR" -maxdepth 2 -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \) 2>/dev/null | sort; }
current() { [[ -s $STATE ]] && cat "$STATE"; }
rotating() { systemctl --user is-active -q "$TIMER" 2>/dev/null; }
# kitty re-reads its colours on USR1. An if, not `pgrep && pkill`: with no kitty
# open that returns 1, and apply() reported a failure.
reload_kitty() { if pgrep -u "$USER" -x kitty >/dev/null; then pkill -u "$USER" -USR1 kitty; fi; }
interval() { sed -n 's/^OnUnitActiveSec=//p' "$UNITS/$TIMER" 2>/dev/null; }

apply() {   # FILE
    local f=$1
    [[ -f $f ]] || { notify "Not found: $f"; return 1; }
    pgrep -x awww-daemon >/dev/null || { setsid -f awww-daemon >/dev/null 2>&1; sleep 0.3; }
    awww img "$f" --resize crop --transition-type grow --transition-pos center --transition-duration 1 || { notify "awww couldn't set it"; return 1; }
    printf '%s\n' "$f" >"$STATE"
    ln -sf "$f" "$HOME/.cache/current_wallpaper_image"
    if command -v matugen >/dev/null; then
        matugen image "$f" --source-color-index 0 >/dev/null 2>&1 || true
        reload_kitty
    fi
    return 0
}

random_wall() {
    local cur all=() pick
    cur=$(current)
    mapfile -t all < <(walls | grep -vxF -- "${cur:-/nonexistent}")
    (( ${#all[@]} )) || { notify "No wallpapers in $DIR"; return 1; }
    pick=${all[RANDOM % ${#all[@]}]}
    apply "$pick"
}

set_rotation() {   # INTERVAL (systemd time span) | off
    if [[ $1 == off ]]; then
        systemctl --user disable --now "$TIMER" >/dev/null 2>&1
        notify "Rotation off"
        return
    fi
    mkdir -p "$UNITS"
    cat >"$UNITS/auch-wallrotate.service" <<EOF
# Written by wall-menu.sh — the wallpaper rotation it turns on and off.
[Unit]
Description=Random wallpaper (wall-menu.sh)

[Service]
Type=oneshot
ExecStart=$SELF random
EOF
    cat >"$UNITS/$TIMER" <<EOF
# Written by wall-menu.sh — change the interval from the Wallpaper menu.
[Unit]
Description=Rotate the wallpaper every $1

[Timer]
OnActiveSec=$1
OnUnitActiveSec=$1

[Install]
WantedBy=timers.target
EOF
    systemctl --user daemon-reload
    systemctl --user enable "$TIMER" >/dev/null 2>&1
    systemctl --user restart "$TIMER"
    notify "Rotating every $1"
}

status() {
    local cur name
    cur=$(current); name=${cur##*/}
    if rotating; then
        emit "󰸉" active "<b>Wallpaper · rotating every $(interval)</b>
Now: ${name:-?}" "${name:-?} · rotating every $(interval)"
    else
        emit "󰸉" ok "<b>Wallpaper</b>
Now: ${name:-?}
$(walls | grep -c .) in ${DIR/#$HOME/\~}" "${name:-none set} · $(walls | grep -c .) to pick from"
    fi
}

# Cells like the old picker's (rofi/wallpaper/style.rasi): the icon box needs an
# explicit transparent background — unset, rofi painted it white around every
# non-square thumbnail — so the cell shows through it, lavender when selected,
# with the name left-aligned underneath. The menu theme's 36em height only fit
# two of the three rows; 44em fits three.
GRID_STYLE="listview { columns: 4; lines: 3; spacing: 6px; }
    element { orientation: vertical; padding: 12px; spacing: 8px; }
    element-icon { size: 8.5em; border-radius: 6px; background-color: transparent; }
    window { height: 44em; }"

grid() {
    local files=() i
    mapfile -t files < <(walls)
    (( ${#files[@]} )) || { notify "No wallpapers in $DIR"; return; }
    i=$(for f in "${files[@]}"; do printf '%s\0icon\x1f%s\n' "${f##*/}" "$f"; done |
        rofi -dmenu -i -no-custom -format i -show-icons "${ONE_CLICK[@]}" -p "Wallpaper" -mesg "${#files[@]} in ${DIR/#$HOME/\~} · type to filter" \
             -theme "$MENU_THEME" -theme-str "$GRID_STYLE $(_pos)") || return
    apply "${files[i]}" && notify "${files[i]##*/}"
}

rotation_menu() {
    local opts=("15min" "30min" "1h" "3h") i
    i=$( { printf '󰑖  Every %s\n' "${opts[@]}"; echo "󰜺  Off"; } |
        pick "Rotate" "$(rotating && echo "Now: every $(interval)" || echo "Now: off") · a random wallpaper each time, colours follow") || return
    if (( i < ${#opts[@]} )); then set_rotation "${opts[i]}"; else set_rotation off; fi
}

menu() {
    local i cur
    while :; do
        cur=$(current)
        i=$(printf '%s\n' "󰸉  Pick a wallpaper ›" "󰒝  Random wallpaper" \
                "󰑖  Auto-rotate · $(rotating && echo "every $(interval)" || echo off) ›" \
                "󰏘  Re-sync colours to this wallpaper" "󰉋  Open the wallpaper folder" |
            pick "Wallpaper" "Now: ${cur##*/}") || return
        case $i in
            0) grid; return ;;
            1) random_wall && notify "$(current | sed 's#.*/##')"; return ;;
            2) rotation_menu ;;
            3) [[ -n $cur ]] && matugen image "$cur" --source-color-index 0 >/dev/null 2>&1 &&
                   { reload_kitty; notify "Colours regenerated from ${cur##*/}"; } ;;
            4) setsid -f dolphin "$DIR" >/dev/null 2>&1; return ;;
        esac
    done
}

case ${1:-} in
    --status) status ;;
    random)   random_wall ;;
    *)        toggle_rofi; menu ;;
esac
