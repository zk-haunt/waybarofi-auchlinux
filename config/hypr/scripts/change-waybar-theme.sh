#!/usr/bin/env bash

# Pick a Waybar theme via Rofi and apply it live

# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

WAYBAR_DIR="$HOME/.config/waybar"
theme="$HOME/.config/rofi/powermenu/style.rasi"

# Scan for available themes from config/waybar/themes
THEME_DIR="$HOME/auchlinux/config/waybar/themes"
if [[ ! -d "$THEME_DIR" ]]; then
    THEME_DIR="$WAYBAR_DIR/themes"
fi

THEMES=$(find "$THEME_DIR" -name "config_*.jsonc" 2>/dev/null | sed -E 's/.*config_(.*)\.jsonc/\1/' | sort)

# Get current theme
CURRENT="auch"
if [[ -f "$THEME_DIR/waybar_theme_mode" ]]; then
    CURRENT=$(cat "$THEME_DIR/waybar_theme_mode")
elif [[ -f "$WAYBAR_DIR/themes/waybar_theme_mode" ]]; then
    CURRENT=$(cat "$WAYBAR_DIR/themes/waybar_theme_mode")
fi

CHOICE=$(echo "$THEMES" | rofi -dmenu -i -p "Waybar Theme [$CURRENT]" -theme "$theme")
[[ -z "$CHOICE" ]] && exit 0

# Apply the theme using the waybar-theme script
WAYBAR_THEME_SCRIPT="$HOME/auchlinux/config/waybar/scripts/waybar-theme"
if [[ ! -x "$WAYBAR_THEME_SCRIPT" ]]; then
    WAYBAR_THEME_SCRIPT="$WAYBAR_DIR/scripts/waybar-theme"
fi

if [[ -x "$WAYBAR_THEME_SCRIPT" ]]; then
    "$WAYBAR_THEME_SCRIPT" "$CHOICE"
else
    # Fallback manual implementation if the script is not executable/found
    echo "$CHOICE" > "$THEME_DIR/waybar_theme_mode"
    rm -f "$WAYBAR_DIR/config.jsonc" "$WAYBAR_DIR/style.css"
    ln -sf "$THEME_DIR/config_$CHOICE.jsonc" "$WAYBAR_DIR/config.jsonc"
    ln -sf "$THEME_DIR/style_$CHOICE.css" "$WAYBAR_DIR/style.css"
    killall -q waybar
    waybar >/dev/null 2>&1 &
    notify-send -i dialog-information "Waybar" "Theme changed to $CHOICE"
fi
