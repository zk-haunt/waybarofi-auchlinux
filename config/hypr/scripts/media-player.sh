#!/usr/bin/env bash


# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

theme="$HOME/.config/rofi/powermenu/style.rasi"

if ! command -v playerctl >/dev/null; then
    notify-send -u critical "Media Player" "playerctl is not installed!"
    exit 1
fi

status=$(playerctl status 2>/dev/null)
if [[ -z "$status" ]]; then
    now_playing="No media is playing."
else
    now_playing="$(playerctl metadata --format '{{title}} - {{artist}}' 2>/dev/null)"
fi

LBL_PREV=$'\U000023EE\UFE0F  Previous'
LBL_PLAY=$'\U000023EF\UFE0F  Play / Pause'
LBL_NEXT=$'\U000023ED\UFE0F  Next'
LBL_STOP=$'\U000023F9\UFE0F  Stop'

options="${LBL_PREV}
${LBL_PLAY}
${LBL_NEXT}
${LBL_STOP}"

choice="$(printf '%s\n' "$options" | rofi -dmenu -i -no-custom -p "Media Player" -mesg "<b>Now Playing:</b> $now_playing" -theme "$theme" -theme-str "listview { lines: 4; }")"

[[ -z "$choice" ]] && exit 0

case "$choice" in
  "${LBL_PREV}")
    playerctl previous
    ;;
  "${LBL_PLAY}")
    playerctl play-pause
    ;;
  "${LBL_NEXT}")
    playerctl next
    ;;
  "${LBL_STOP}")
    playerctl stop
    ;;
  *)
    # Was absent: an unmatched choice fell straight through esac, so a
    # label edit broke dispatch with no error at all.
    notify-send -u critical "Media Player" "Unrecognised menu choice: $choice"
    exit 1
    ;;
esac
