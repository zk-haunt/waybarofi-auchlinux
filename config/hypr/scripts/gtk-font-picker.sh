#!/usr/bin/env bash
# GTK Font Selector (Super+Shift+F) — pick a system font family + size via Rofi,
# applied live to GTK3/4 apps, GSettings, and XWayland apps (via xsettingsd).
# Mirrors gtk-theme-picker.sh's apply style.

# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

theme="$HOME/.config/rofi/powermenu/style.rasi"

current=$(gsettings get org.gnome.desktop.interface font-name 2>/dev/null | tr -d "'")

# All installed font families, one per line, deduped + sorted.
families=$(fc-list : family | sed 's/,.*//' | sort -u | grep -v '^$')

family=$(echo "$families" | rofi -dmenu -i -p "Font (now: ${current:-default})" -theme "$theme")
[ -z "$family" ] && exit 0

# Pick a size (type a custom number too — no -no-custom here on purpose).
size=$(printf '%s\n' 9 10 11 12 13 14 16 | rofi -dmenu -i -p "Size" -theme "$theme" -theme-str "listview { lines: 7; }")
[ -z "$size" ] && size=11
font="$family $size"

# 1. GSettings (GTK4 / GNOME apps)
gsettings set org.gnome.desktop.interface font-name "$font"

# 2. GTK 3 & 4 settings.ini
for d in gtk-3.0 gtk-4.0; do
    f="$HOME/.config/$d/settings.ini"
    mkdir -p "$HOME/.config/$d"
    if grep -q "gtk-font-name" "$f" 2>/dev/null; then
        sed -i "s/gtk-font-name.*/gtk-font-name=$font/" "$f"
    else
        [ -f "$f" ] || printf '[Settings]\n' > "$f"
        echo "gtk-font-name=$font" >> "$f"
    fi
done

# 3. xsettingsd → XWayland / GTK2 apps (add or update Gtk/FontName, then reload)
xs="$HOME/.config/xsettingsd/xsettingsd.conf"
if [ -f "$xs" ]; then
    if grep -q '^Gtk/FontName' "$xs"; then
        sed -i "s|^Gtk/FontName.*|Gtk/FontName \"$font\"|" "$xs"
    else
        echo "Gtk/FontName \"$font\"" >> "$xs"
    fi
    pkill -HUP xsettingsd 2>/dev/null
fi

notify-send -u low "GTK Font" "Set to $font"
