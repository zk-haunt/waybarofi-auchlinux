#!/usr/bin/env bash
# Sticky notes — plain markdown files, a rofi menu, and "pinned" notes as small
# floating kitty windows on every workspace (window rules in hyprland.lua).
# The notes icon sits in the clock group of the "auchsec" Waybar layout.
#
#   notes-menu.sh            the menu: New note, then every note, newest first
#   notes-menu.sh new        quick capture: one line, saved on Enter (Super+Ctrl+N)
#   notes-menu.sh pin FILE   open FILE as a sticky window
#   notes-menu.sh --status   one JSON line for the Waybar module
#
# Notes live in ~/Documents/sticky-notes — usb-backup.sh already copies
# ~/Documents. One file per note; its first line is the title. Delete moves the
# file to the trash, so a slip is recoverable.

# -u and pipefail, but NOT -e — same reasoning as clipboard-menu.sh: this is
# bound to keys and clicks, and `set -e` turns a cosmetic failure into a dead one.
set -uo pipefail

NOTES_DIR="${AUCH_NOTES_DIR:-$HOME/Documents/sticky-notes}"
theme="$HOME/.config/rofi/logviewer/style.rasi"
SLOTS=3        # sticky windows take positions 1..SLOTS (hyprland.lua); more share the last
SIGNAL=12      # "signal" of custom/notes in config/waybar/notes.jsonc

mkdir -p "$NOTES_DIR"

# ── helpers ─────────────────────────────────────────────────────────────────
esc()     { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }   # Pango
notify()  { notify-send -a "Notes" -u low -t 1500 "󰎞  Notes" "$1"; }
# "summary" is extra — Waybar ignores it; sec-picker.sh shows it in its rows.
emit()    { jq -cn --arg text "$1" --arg class "$2" --arg tooltip "$3" --arg summary "${4:-}" \
                '{text: $text, class: $class, alt: $class, tooltip: $tooltip, summary: $summary}'; }
refresh() { pkill -u "$USER" -RTMIN+"$SIGNAL" waybar 2>/dev/null || true; }

# pick PROMPT MESSAGE — rows on stdin; prints the chosen row's index, or
# nothing (and fails) on Esc. Opened from sec-picker.sh, SEC_MENU_POS holds a
# -theme-str that anchors every menu under the bar button, like the dropdown.
# One click picks, like the dropdown (rofi's default wants a double click).
pick() { rofi -dmenu -i -no-custom -format i -p "$1" -mesg "$2" -theme "$theme" -me-select-entry '' -me-accept-entry MousePrimary ${SEC_MENU_POS:+-theme-str "$SEC_MENU_POS"}; }

# Newest first. The names are ours (timestamps), so parsing ls is safe here.
notes()    { ls -1t "$NOTES_DIR"/*.md 2>/dev/null; }
# First non-blank line, minus a leading markdown "#".
title_of() { sed -n '/[^[:space:]]/{s/^[[:space:]]*#*[[:space:]]*//;p;q}' "$1"; }
age_of() {
    local s=$(( $(date +%s) - $(stat -c %Y "$1") ))
    if   (( s < 3600 ));  then echo "$((s / 60))m"
    elif (( s < 86400 )); then echo "$((s / 3600))h"
    else                       echo "$((s / 86400))d"; fi
}

# Sticky windows are kittys titled "note:<file>" with class sticky-note-<slot>.
sticky_titles() { hyprctl clients -j 2>/dev/null | jq -r '.[] | select(.class | startswith("sticky-note-")) | .title'; }
free_slot() {
    local used s
    used=$(hyprctl clients -j 2>/dev/null | jq -r '.[].class')
    for (( s = 1; s <= SLOTS; s++ )); do
        grep -qx "sticky-note-$s" <<<"$used" || { echo "$s"; return; }
    done
    echo "$SLOTS"
}

# ── actions ─────────────────────────────────────────────────────────────────
pin() {
    local f=$1 name addr
    [[ -f $f ]] || { notify "No such note: $f"; return 1; }
    name=$(basename "$f")
    # Already on screen: just focus it. By address, in the Lua dispatch form —
    # `hyprctl dispatch focuswindow …` is legacy syntax this Hyprland rejects,
    # and hl.dsp.focus({ window = "title:…" }) didn't match (checked 2026-10-10).
    addr=$(hyprctl clients -j 2>/dev/null | jq -r --arg t "note:$name" '.[] | select(.title == $t) | .address' | head -n1)
    if [[ -n $addr ]]; then
        hyprctl dispatch "hl.dsp.focus({ window = \"address:$addr\" })" >/dev/null
        return
    fi
    # nano: modern keys (Ctrl+S save, Ctrl+Q close), no bars, wrapped lines.
    setsid -f kitty --class "sticky-note-$(free_slot)" --title "note:$name" \
        -o font_size=10 -o window_padding_width=8 -o confirm_os_window_close=0 \
        nano --modernbindings --zero --softwrap --mouse --autoindent "$f" >/dev/null 2>&1
}

new_note() {   # prints the new file's path
    local text f stamp n=1
    text=$(rofi -dmenu -p "New note" -mesg "One line — Enter saves it. Pin it from the notes menu to write more." \
               -theme "$theme" -theme-str "listbox { enabled: false; } window { height: 9em; } ${SEC_MENU_POS:-}" </dev/null) || return 1
    [[ -n ${text//[[:space:]]/} ]] || return 1
    # Named by the second; a second note within it gets -2, -3… instead of
    # overwriting the first.
    stamp=$(date +%Y-%m-%d_%H-%M-%S); f="$NOTES_DIR/$stamp.md"
    while [[ -e $f ]]; do n=$((n + 1)); f="$NOTES_DIR/$stamp-$n.md"; done
    printf '%s\n' "$text" > "$f"
    refresh
    notify "Saved: $text"
    echo "$f"
}

menu_note() {
    local f=$1 i
    while [[ -f $f ]]; do
        i=$(printf '%s\n' "󰁍  Back" "󰐃  Pin to screen" "󰏫  Edit in a terminal" "󰆏  Copy" "󰩹  Delete (moves it to the trash)" |
            pick "Note" "$(head -n 14 "$f" | esc)") || return
        case $i in
            0) return ;;
            1) pin "$f"; exit 0 ;;
            2) setsid -f kitty --title "note:$(basename "$f")" nano --modernbindings --softwrap "$f" >/dev/null 2>&1; exit 0 ;;
            3) wl-copy < "$f" && notify "Copied to the clipboard" ;;
            4) gio trash "$f" && { refresh; notify "Moved to the trash"; return; } ;;
        esac
    done
}

menu_main() {
    local i files=() rows=() f t on_screen mark
    while :; do
        mapfile -t files < <(notes)
        on_screen=$(sticky_titles)
        rows=()
        for f in "${files[@]}"; do
            t=$(title_of "$f")
            mark=""; grep -qxF "note:$(basename "$f")" <<<"$on_screen" && mark="  󰐃"
            rows+=("$(printf '󰎞  %s  · %s%s' "${t:-(empty)}" "$(age_of "$f")" "$mark")")
        done
        # `if`, not `&&`: with no notes `(( 0 )) && …` fails the group, and
        # pipefail then fails the pick even though a row was chosen — "New note"
        # did nothing until a first note existed (2026-10-10).
        i=$( { echo "󰎜  New note"; if (( ${#rows[@]} )); then printf '%s\n' "${rows[@]}"; fi; } |
             pick "Notes" "${#files[@]} in ${NOTES_DIR/#"$HOME"/\~} · 󰐃 = pinned on screen") || return
        if (( i == 0 )); then new_note >/dev/null; else menu_note "${files[i-1]}"; fi
    done
}

status() {
    local files=() f tip
    mapfile -t files < <(notes)
    tip="<b>Notes</b> · ${#files[@]}"
    for f in "${files[@]:0:6}"; do tip+=$'\n'"• $(title_of "$f" | cut -c1-60 | esc)"; done
    (( ${#files[@]} > 6 )) && tip+=$'\n'"… and $(( ${#files[@]} - 6 )) more"
    tip+=$'\n\n'"<i>Click: notes · Right-click: new note</i>"
    if (( ${#files[@]} )); then
        emit "󰎞 ${#files[@]}" some "$tip" \
            "${#files[@]} note$( (( ${#files[@]} > 1 )) && echo s) · newest: $(title_of "${files[0]}" | cut -c1-28)"
    else
        emit "󰎚" none "$tip" "no notes yet"
    fi
}

# ── main ────────────────────────────────────────────────────────────────────
case ${1:-} in
    --status) status; exit 0 ;;
    pin)      pin "${2:?usage: ${0##*/} pin FILE}"; exit ;;
esac

# A second click on the bar closes the menu instead of stacking another.
if pgrep -u "$USER" -x rofi >/dev/null; then
    pkill -u "$USER" -x rofi
    exit 0
fi

case ${1:-} in
    new) new_note >/dev/null ;;
    "")  menu_main ;;
    *)   echo "usage: ${0##*/} [new | pin FILE | --status]" >&2; exit 2 ;;
esac
