#!/usr/bin/env bash


# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

theme="$HOME/.config/rofi/powermenu/style.rasi"

LBL_BROWSER=$'\U0001F310  Browser (Zen)'
LBL_CODE=$'\U0001F4BB  Code (VSCode)'
LBL_NOTES=$'\U0001F4DD  Notes (Obsidian)'
LBL_MUSIC=$'\U0001F3B5  Music (Spotify)'
LBL_CHAT=$'\U0001F4AC  Chat (Discord)'

options="${LBL_BROWSER}
${LBL_CODE}
${LBL_NOTES}
${LBL_MUSIC}
${LBL_CHAT}"

choice="$(printf '%s\n' "$options" | rofi -dmenu -i -no-custom -p "Quick Apps" -theme "$theme" -theme-str "listview { lines: 5; }")"

[[ -z "$choice" ]] && exit 0

case "$choice" in
  "${LBL_BROWSER}")
    zen-browser &
    ;;
  "${LBL_CODE}")
    code &
    ;;
  "${LBL_NOTES}")
    obsidian &
    ;;
  "${LBL_MUSIC}")
    spotify &
    ;;
  "${LBL_CHAT}")
    discord &
    ;;
  *)
    # Was absent: an unmatched choice fell straight through esac, so a
    # label edit broke dispatch with no error at all.
    notify-send -u critical "Quick Apps" "Unrecognised menu choice: $choice"
    exit 1
    ;;
esac
