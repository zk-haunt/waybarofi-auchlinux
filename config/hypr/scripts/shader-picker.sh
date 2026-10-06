#!/usr/bin/env bash
# Screen shader picker (Super+N is the blue-light toggle; this is the full menu).
#
# Two bugs fixed here, both of the same family as power-menu.sh:
#
# 1. `hyprctl keyword decoration:screen_shader` does nothing on this setup.
#    The config is pure Lua, and Hyprland rejects keyword outright:
#    "keyword can't work with non-legacy parsers. Use eval." The menu appeared,
#    reported success, and changed nothing. Verified working replacement:
#    hyprctl eval 'hl.config({ decoration = { screen_shader = "<path>" } })'
#
# 2. Dispatch compared the full emoji+label display string, duplicated between
#    the options list and the case patterns, with no *) arm. Several labels carry
#    a U+FE0F variation selector, so an invisible byte difference would break
#    dispatch silently. Labels now live in variables used in BOTH places, and an
#    unmatched choice is reported instead of ignored.

set -uo pipefail

theme="$HOME/.config/rofi/powermenu/style.rasi"
SHADER_DIR="$HOME/.config/hypr/shaders"

LBL_GRAY=$'\U0001F39E\UFE0F  Grayscale'
LBL_INVERT=$'\U0001F47D  Invert Colors'
LBL_OFF=$'\U0001F3AF  Disable Shaders'

# Quote a value as a Lua double-quoted string. NOT [[...]] long brackets: the
# "no shader" sentinel Hyprland expects is the literal [[EMPTY]], and a long
# bracket cannot contain ]] — it produced `[[[[EMPTY]]]]`, a syntax error.
lua_str() {
    local v="$1"
    v="${v//\\/\\\\}"   # backslashes first
    v="${v//\"/\\\"}"     # then double quotes
    printf '"%s"' "$v"
}

apply_shader() {
    local path="$1" name="$2"
    local out
    if out="$(hyprctl eval "hl.config({ decoration = { screen_shader = $(lua_str "$path") } })" 2>&1)" \
       && [[ "$out" != *rror* ]]; then
        notify-send -u low "Shaders" "$name"
    else
        notify-send -u critical "Shaders: failed to apply $name" "${out:-hyprctl eval failed}"
        return 1
    fi
}

options="${LBL_GRAY}
${LBL_INVERT}
${LBL_OFF}"

choice="$(printf '%s\n' "$options" | rofi -dmenu -i -no-custom -p "Screen Shaders" -theme "$theme" -theme-str "listview { lines: 3; }")"
[[ -z "$choice" ]] && exit 0

case "$choice" in
  "$LBL_GRAY")   apply_shader "$SHADER_DIR/grayscale.frag" "Grayscale applied" ;;
  "$LBL_INVERT") apply_shader "$SHADER_DIR/invert.frag"    "Invert Colors applied" ;;
  "$LBL_OFF")    apply_shader "[[EMPTY]]"                  "Shaders disabled" ;;
  *)
    notify-send -u critical "Shaders" "Unrecognised menu choice: $choice"
    exit 1
    ;;
esac
