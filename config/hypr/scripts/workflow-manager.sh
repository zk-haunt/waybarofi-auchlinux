#!/usr/bin/env bash
# Workspace switches use the Lua dispatch form. `hyprctl dispatch workspace N`
# is the legacy hyprlang syntax and this Hyprland rejects it outright:
#   error: [string "return hl.dispatch(workspace 2)"]:1: ')' expected near '2'
# so every workflow silently failed to change workspace. Same lesson already
# learned in smart-move.sh, localsend.sh and pin-window.sh.


# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

theme="$HOME/.config/rofi/powermenu/style.rasi"

LBL_CODING=$'\U0001F4BB  Coding'
LBL_GAMING=$'\U0001F3AE  Gaming'
LBL_BROWSING=$'\U0001F310  Browsing'

options="${LBL_CODING}
${LBL_GAMING}
${LBL_BROWSING}"

choice="$(printf '%s\n' "$options" | rofi -dmenu -i -no-custom -p "Select Workflow" -theme "$theme" -theme-str "listview { lines: 3; }")"

[[ -z "$choice" ]] && exit 0

case "$choice" in
  "${LBL_CODING}")
    notify-send -u low "Workflow" "Launching Coding layout..."
    hyprctl dispatch "hl.dsp.focus({workspace = 2})"
    kitty &
    sleep 0.5
    code &
    ;;
  "${LBL_GAMING}")
    notify-send -u low "Workflow" "Launching Gaming layout..."
    hyprctl dispatch "hl.dsp.focus({workspace = 5})"
    steam &
    ;;
  "${LBL_BROWSING}")
    notify-send -u low "Workflow" "Launching Browsing layout..."
    hyprctl dispatch "hl.dsp.focus({workspace = 1})"
    zen-browser &
    ;;
  *)
    # Was absent: an unmatched choice fell straight through esac, so a
    # label edit broke dispatch with no error at all.
    notify-send -u critical "Workflow" "Unrecognised menu choice: $choice"
    exit 1
    ;;
esac
