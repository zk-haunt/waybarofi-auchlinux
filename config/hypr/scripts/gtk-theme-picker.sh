#!/usr/bin/env bash

# Menu labels live in variables used BOTH in the options string and the case
# patterns below, so the literal exists once. The cursor entry carries a U+FE0F
# variation selector, which is exactly the kind of invisible byte that silently
# breaks full-string dispatch when a label is edited.

# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

LBL_GTK=$'\U0001F3AD  GTK Theme'
LBL_ICON=$'\U0001F3A8  Icon Theme'
LBL_CURSOR=$'\U0001F5B1\UFE0F  Cursor Theme'

# Auchlinux Unified Theme Switcher (GTK, Icons, Cursors) using Rofi
theme="$HOME/.config/rofi/powermenu/style.rasi"

# Helper: Get current settings
get_current() {
    local key="$1"
    if [ "$key" == "gtk" ]; then
        grep "gtk-theme-name" "$HOME/.config/gtk-3.0/settings.ini" 2>/dev/null | cut -d '=' -f 2 | tr -d ' '
    elif [ "$key" == "icon" ]; then
        grep "gtk-icon-theme-name" "$HOME/.config/gtk-3.0/settings.ini" 2>/dev/null | cut -d '=' -f 2 | tr -d ' '
    elif [ "$key" == "cursor" ]; then
        gsettings get org.gnome.desktop.interface cursor-theme 2>/dev/null | tr -d "'"
    fi
}

main_menu() {
    options="${LBL_GTK}\n${LBL_ICON}\n${LBL_CURSOR}"
    echo -e "$options" | rofi -dmenu -i -no-custom -p "Theme Switcher" -theme "$theme" -theme-str "listview { lines: 3; }"
}

# 1. GTK Theme selection
select_gtk() {
    local current=$(get_current "gtk")
    local list=$(find /usr/share/themes "$HOME/.themes" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | rev | cut -d '/' -f 1 | rev | sort -u)
    local selected=$(echo "$list" | rofi -dmenu -i -no-custom -p "GTK (Current: ${current:-default})" -theme "$theme")
    
    if [ -n "$selected" ]; then
        # Update GTK 3 & GTK 4 config files
        mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
        sed -i "s/gtk-theme-name.*/gtk-theme-name=$selected/g" "$HOME/.config/gtk-3.0/settings.ini" 2>/dev/null || echo "gtk-theme-name=$selected" >> "$HOME/.config/gtk-3.0/settings.ini"
        sed -i "s/gtk-theme-name.*/gtk-theme-name=$selected/g" "$HOME/.config/gtk-4.0/settings.ini" 2>/dev/null || echo "gtk-theme-name=$selected" >> "$HOME/.config/gtk-4.0/settings.ini"
        
        # Update GSettings
        gsettings set org.gnome.desktop.interface gtk-theme "$selected"
        
        notify-send -u low "GTK Theme" "Changed to $selected"
    fi
}

# 2. Icon Theme selection
select_icon() {
    local current=$(get_current "icon")
    local list=$(find "$HOME/.icons" "$HOME/.local/share/icons" /usr/share/icons -mindepth 1 -maxdepth 2 -name "index.theme" 2>/dev/null | while read -r file; do
        dir=$(dirname "$file")
        if [ ! -d "$dir/cursors" ]; then
            basename "$dir"
        fi
    done | sort -u)
    
    local selected=$(echo "$list" | rofi -dmenu -i -no-custom -p "Icon Theme (Current: ${current:-default})" -theme "$theme")
    
    if [ -n "$selected" ]; then
        # Update GTK 3 & 4
        mkdir -p "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0"
        sed -i "s/gtk-icon-theme-name.*/gtk-icon-theme-name=$selected/g" "$HOME/.config/gtk-3.0/settings.ini" 2>/dev/null || echo "gtk-icon-theme-name=$selected" >> "$HOME/.config/gtk-3.0/settings.ini"
        sed -i "s/gtk-icon-theme-name.*/gtk-icon-theme-name=$selected/g" "$HOME/.config/gtk-4.0/settings.ini" 2>/dev/null || echo "gtk-icon-theme-name=$selected" >> "$HOME/.config/gtk-4.0/settings.ini"
        
        # Update GSettings
        gsettings set org.gnome.desktop.interface icon-theme "$selected"
        
        notify-send -u low "Icon Theme" "Changed to $selected"
    fi
}

# 3. Cursor Theme selection
select_cursor() {
    local current=$(get_current "cursor")
    local list=$(find "$HOME/.icons" "$HOME/.local/share/icons" /usr/share/icons -mindepth 2 -maxdepth 2 -type d -name "cursors" 2>/dev/null | awk -F'/' '{print $(NF-1)}' | sort -u)
    local selected=$(echo "$list" | rofi -dmenu -i -no-custom -p "Cursor Theme (Current: ${current:-default})" -theme "$theme")
    
    if [ -n "$selected" ]; then
        # Update GSettings
        gsettings set org.gnome.desktop.interface cursor-theme "$selected"
        
        # Update index.theme (Fallback)
        mkdir -p "$HOME/.icons/default"
        echo -e "[Icon Theme]\nInherits=$selected" > "$HOME/.icons/default/index.theme"
        
        # Update Hyprland environment variables in env_var.lua (if the file is writeable/present in repo config)
        local env_file="$HOME/.config/hypr/hyprland/env_var.lua"
        if [ -f "$env_file" ]; then
            sed -i "s/hl.env(\"XCURSOR_THEME\",.*/hl.env(\"XCURSOR_THEME\", \"$selected\")/g" "$env_file"
            sed -i "s/hl.env(\"HYPRCURSOR_THEME\",.*/hl.env(\"HYPRCURSOR_THEME\", \"$selected\")/g" "$env_file"
        fi
        
        # Update GTK-3.0
        sed -i "s/gtk-cursor-theme-name.*/gtk-cursor-theme-name=$selected/g" "$HOME/.config/gtk-3.0/settings.ini" 2>/dev/null
        
        # Apply to running Hyprland session dynamically
        hyprctl setcursor "$selected" 24
        
        notify-send -u low "Cursor Theme" "Changed to $selected (Restart apps to fully apply)"
    fi
}

if [ "${1:-}" == "cursor" ]; then
    select_cursor
    exit 0
elif [ "${1:-}" == "gtk" ]; then
    select_gtk
    exit 0
elif [ "${1:-}" == "icon" ]; then
    select_icon
    exit 0
fi

choice=$(main_menu)
case "$choice" in
    "${LBL_GTK}")
        select_gtk
        ;;
    "${LBL_ICON}")
        select_icon
        ;;
    "${LBL_CURSOR}")
        select_cursor
        ;;
    *)
        notify-send -u critical "Theme Picker" "Unrecognised menu choice: $choice"
        exit 1
        ;;
esac
