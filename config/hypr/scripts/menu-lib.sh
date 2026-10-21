# Sourced, not run: what every hub menu needs (the rows of sec-picker.sh's
# dropdown — updates, music, network, lynis, virus, aur, report, shares,
# wallpaper), so each of those scripts is only its own logic.
#
# Set before sourcing:   MENU_APP   name for notifications, e.g. "Updates"
#                        MENU_ICON  glyph for notifications
# Opened from the dropdown, SEC_MENU_POS anchors every menu under the button.

# shellcheck disable=SC2034
source "${BASH_SOURCE[0]%/*}/rofi-anchor.sh"

MENU_THEME="$HOME/.config/rofi/logviewer/style.rasi"
MENU_W=780                                   # px, when anchored by hand
AUCH_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/auch"
mkdir -p "$AUCH_CACHE"

esc()    { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }   # Pango
human()  { numfmt --to=iec "${1:-0}"; }                                # bytes -> 8.6G
# count_lines FILE — non-empty lines; 0 when empty or missing. Not `grep -c .
# FILE || echo 0`: with no match grep prints 0 AND fails, so that gave "0\n0"
# (File shares' row read just "0", 2026-10-11).
count_lines() { local n; n=$(grep -c . "$1" 2>/dev/null); echo "${n:-0}"; }
notify() { notify-send -a "${MENU_APP:-Menu}" -u low -t 3000 "${MENU_ICON:-}  ${MENU_APP:-}" "$1"; }

# emit TEXT CLASS TOOLTIP [SUMMARY] — one JSON line for Waybar / sec-picker.sh.
emit() {
    jq -cn --arg text "$1" --arg class "$2" --arg tooltip "$3" --arg summary "${4:-}" \
        '{text: $text, class: $class, alt: $class, tooltip: $tooltip, summary: $summary}'
}

# Where menus open: under the bar button when SEC_MENU_POS is set, else centred.
_pos() { [[ -n ${SEC_MENU_POS:-} ]] && printf '%s' "$SEC_MENU_POS"; }

# pick PROMPT MESSAGE — rows on stdin; prints the chosen row's index, or
# nothing (and fails) on Esc. pick_markup: the same, rows are Pango markup.
# One click picks, like the dropdowns: rofi's default wants a double click, so a
# single click only highlighted the row — "New note" seemed to do nothing.
ONE_CLICK=(-me-select-entry '' -me-accept-entry MousePrimary)
pick() {
    rofi -dmenu -i -no-custom -format i -p "$1" -mesg "$2" -theme "$MENU_THEME" "${ONE_CLICK[@]}" \
        ${SEC_MENU_POS:+-theme-str "$SEC_MENU_POS"}
}
pick_markup() {
    rofi -dmenu -i -no-custom -markup-rows -format i -p "$1" -mesg "$2" -theme "$MENU_THEME" "${ONE_CLICK[@]}" \
        ${SEC_MENU_POS:+-theme-str "$SEC_MENU_POS"}
}

# ask PROMPT MESSAGE [PREFILL] [password] — one line of free text, or fail on Esc.
# The window is the banner plus the message, so its height follows the message:
# a fixed 9em held one line, and a longer one was drawn over the input row
# (2026-10-11). ~80 characters a line at 780 px; ~1.3em a line on top of 7.5em.
ask() {
    local extra=() lines h
    [[ ${4:-} == password ]] && extra=(-password)
    lines=$(( (${#2} + 79) / 80 )); (( lines )) || lines=1
    h=$(( 75 + 13 * lines ))                                   # tenths of an em
    rofi -dmenu -p "$1" -mesg "$2" -filter "${3:-}" "${extra[@]}" -theme "$MENU_THEME" \
        -theme-str "listbox { enabled: false; } window { height: $((h / 10)).$((h % 10))em; } $(_pos)" </dev/null
}

# confirm QUESTION — 0 only on an explicit yes.
confirm() {
    local i
    i=$(printf '%s\n' "󰁍  No, back" "󰗩  Yes" | pick "Sure?" "$1") || return 1
    [[ $i == 1 ]]
}

# in_terminal TITLE COMMAND — run COMMAND (bash) in kitty; the window stays
# until Enter. Anything needing root runs `sudo -v` first itself.
in_terminal() {
    setsid -f kitty --title "$1" bash -c "$2; echo; read -rp 'Done — press Enter to close. '" >/dev/null 2>&1
}
# in_pager TITLE COMMAND — the same, output through less (no -F: a short result
# doesn't flash shut).
in_pager() {
    setsid -f kitty --title "$1" bash -c "{ $2; } 2>&1 | less -R" >/dev/null 2>&1
}

# list_rows TITLE MESSAGE — rows on stdin; Back on top, a pick copies the row.
# Rows go in with `if`, never `(( n )) && printf`: with no rows that fails the
# group, and pipefail then fails the pick although a row was chosen.
list_rows() {
    local title=$1 mesg=$2 rows=() i
    mapfile -t rows
    while :; do
        i=$( { echo "󰁍  Back"; if (( ${#rows[@]} )); then printf '%s\n' "${rows[@]}"; fi; } | pick "$title" "$mesg") || return
        (( i == 0 )) && return
        printf '%s' "${rows[i-1]}" | wl-copy && notify "Copied to the clipboard"
    done
}

# age SECONDS-AGO -> "5 min ago" / "3 h ago" / "2 days ago"
age() {
    local s=${1:-0}
    if   (( s < 90 ));     then echo "just now"
    elif (( s < 3600 ));   then echo "$((s / 60)) min ago"
    elif (( s < 86400 ));  then echo "$((s / 3600)) h ago"
    elif (( s < 172800 )); then echo "1 day ago"
    else                        echo "$((s / 86400)) days ago"; fi
}

# fresh FILE MAX-SECONDS — 0 if FILE exists and is younger than MAX-SECONDS.
fresh() { [[ -f $1 ]] && (( $(date +%s) - $(stat -c %Y "$1") < $2 )); }

# A second click on the bar closes the menu instead of stacking another.
toggle_rofi() {
    if pgrep -u "$USER" -x rofi >/dev/null; then
        pkill -u "$USER" -x rofi
        exit 0
    fi
}
