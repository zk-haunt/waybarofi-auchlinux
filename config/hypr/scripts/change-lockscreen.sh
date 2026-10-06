#!/usr/bin/env bash
# Pick a Hyprlock theme via Rofi


# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

LOCK_DIR="$HOME/.config/hypr/hyprlock"
STATE_FILE="$HOME/.config/hypr/hyprlock/.current"
MAIN_CONF="$HOME/.config/hypr/hyprlock.conf"
theme="$HOME/.config/rofi/powermenu/style.rasi"

[[ ! -d "$LOCK_DIR" ]] && notify-send "Hyprlock" "No themes found in $LOCK_DIR" && exit 1

THEMES=$(ls "$LOCK_DIR"/*.conf 2>/dev/null | xargs -I{} basename {} .conf | grep -v "^greetd" | sort)
CURRENT=$(cat "$STATE_FILE" 2>/dev/null || echo "default")

CHOICE=$(echo "$THEMES" | rofi -dmenu -i -p "Lock Screen  [$CURRENT]" -theme "$theme")
[[ -z "$CHOICE" ]] && exit 0

CONF="$LOCK_DIR/$CHOICE.conf"
[[ ! -f "$CONF" ]] && exit 1

# Back up the current working config before overwriting (so a bad theme can
# always be reverted — the picker previously cp -f'd with no backup).
[[ -f "$MAIN_CONF" ]] && cp -f "$MAIN_CONF" "$LOCK_DIR/.last-working.conf"

cp -f "$CONF" "$MAIN_CONF"
echo "$CHOICE" > "$STATE_FILE"

notify-send -i system-lock-screen "Hyprlock Theme" "Set to: $CHOICE" -t 2000
