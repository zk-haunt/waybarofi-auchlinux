#!/usr/bin/env bash

# Toggle: if rofi is already running for the user, kill it and exit

# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

if pgrep -u "$USER" -x rofi >/dev/null; then
  pkill -u "$USER" -x rofi
  exit 0
fi

db_file="$HOME/.config/rofi/glyph.db"
recent_file="$HOME/.cache/rofi_glyph_recent"
theme="$HOME/.config/rofi/clipboard/style.rasi"

if [[ ! -f "$db_file" ]]; then
  notify-send -u low "Glyph Picker" "Database not found: $db_file"
  exit 1
fi

if [[ ! -f "$recent_file" ]]; then
  touch "$recent_file"
fi

# Get selection using Rofi (combining recent and all glyphs, preserving order)
selection=$( (cat "$recent_file"; cat "$db_file") | awk '!seen[$0]++' | rofi -dmenu -i -p " Glyph" -theme "$theme" -theme-str 'entry { placeholder: "Search Glyphs..."; }')
[[ -z "$selection" ]] && exit 0

# Extract glyph character (first tab-separated token)
glyph=$(echo "$selection" | cut -f1)

if [[ -n "$glyph" ]]; then
  echo "$glyph" | tr -d '\n' | wl-copy
  notify-send -a "Glyph Picker" -i "dialog-information" "Copied to Clipboard" "$glyph"
  
  # Save to recent list (limit to 30 items)
  (echo "$selection"; cat "$recent_file") | awk '!seen[$0]++' | head -n 30 > "${recent_file}.tmp"
  mv "${recent_file}.tmp" "$recent_file"
fi
