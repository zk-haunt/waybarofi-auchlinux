#!/usr/bin/env bash


# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

theme="$HOME/.config/rofi/powermenu/logout.rasi"
# The confirm step gets its own theme. Reusing logout.rasi gave two
# screen-filling slabs, because that file's geometry (mainbox margin 35% 10%,
# element padding 60px 0px, listview columns: 5) is sized for the five-tile
# power menu.
confirm_theme="$HOME/.config/rofi/powermenu/confirm.rasi"

# Icon-only tiles. Glyphs are nf-md-* (Material Design) from JetBrainsMono Nerd
# Font, written as \U escapes rather than literal glyphs so the file stays
# readable in editors without the font and can't be mangled by a re-encode.
# They double as the `case` patterns below, so a glyph can only ever be changed
# in one place.
ICON_LOCK=$'\U000F033E'      # nf-md-lock
ICON_SHUTDOWN=$'\U000F0425'  # nf-md-power
ICON_RESTART=$'\U000F0709'   # nf-md-restart
ICON_LOGOUT=$'\U000F0343'    # nf-md-logout
ICON_SUSPEND=$'\U000F0904'   # nf-md-power_sleep
ICON_YES=$'\U000F012C'       # nf-md-check
ICON_NO=$'\U000F0156'        # nf-md-close

options="${ICON_LOCK}
${ICON_SHUTDOWN}
${ICON_RESTART}
${ICON_LOGOUT}
${ICON_SUSPEND}"

menu() {
  local prompt="$1"
  local lines="${2:-5}"
  rofi -dmenu -i -no-custom -p "$prompt" -theme "$theme" -theme-str "listview { lines: ${lines}; }"
}

confirm() {
  local action="$1"
  local answer
  # No -theme-str override: confirm.rasi already declares the 1x2 layout, so
  # there is nothing to patch at the call site.
  # -selected-row 1 preselects NO. These are destructive, irreversible actions
  # (shutdown/restart/logout), so a reflexive Enter should cancel rather than
  # fire. Previously the default was row 0 = yes.
  answer="$(printf '%s\n%s\n' "$ICON_YES" "$ICON_NO" | rofi -dmenu -i -no-custom -selected-row 1 -p "$action" -theme "$confirm_theme")"
  [[ "$answer" == "$ICON_YES" ]]
}

lock_screen() {
  pidof hyprlock > /dev/null || hyprlock
}

choice="$(printf '%s\n' "$options" | menu "System" 5)"
[[ -z "$choice" ]] && exit 0

case "$choice" in
  "$ICON_LOCK")
    lock_screen
    ;;
  "$ICON_SUSPEND")
    confirm "Suspend" && loginctl lock-session && systemctl suspend
    ;;
  "$ICON_LOGOUT")
    if confirm "Logout"; then
      if command -v uwsm > /dev/null 2>&1 && uwsm check is-active; then
        uwsm stop
      else
        hyprctl dispatch exit
      fi
    fi
    ;;
  "$ICON_RESTART")
    confirm "Restart" && systemctl reboot
    ;;
  "$ICON_SHUTDOWN")
    confirm "Shutdown" && systemctl poweroff
    ;;
  *)
    notify-send -u low "Power menu" "Unknown action: $choice"
    ;;
esac
