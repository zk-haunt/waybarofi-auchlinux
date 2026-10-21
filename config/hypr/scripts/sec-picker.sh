#!/usr/bin/env bash
# Security picker — the shield button in the "auchsec" Waybar layout, and the
# hub for the rofi tools. Click it and a dropdown opens right under the button,
# one row per tool with its status: updates, music, notes, network (the
# firewall is part of it), AppArmor, Lynis, logs, virus scan, AUR check,
# clean-up, report IP/URL, phone, file shares, wallpaper. A row opens that
# tool's menu, anchored at the same spot. Only warnings and
# criticals count toward the button's alert number; notes, music and the like
# never raise one.
#
#   sec-picker.sh            the dropdown
#   sec-picker.sh --status   one JSON line for the Waybar button
#
# Waybar doesn't tell a click command where the button is, so the dropdown goes
# under the cursor — which is on the button, since that's what was clicked —
# just below the bar's bottom edge (from hyprctl layers).

# -u and pipefail, but NOT -e — same reasoning as clipboard-menu.sh: bound to a
# click, and `set -e` turns a cosmetic failure into a dead button.
set -uo pipefail

S="$HOME/.config/hypr/scripts"
theme="$HOME/.config/rofi/picker/style.rasi"
PICKER_W=520   # px — the dropdown's width (rofi/picker/style.rasi); needed to keep it on screen
MENU_W=780     # px — the security/system menus' width when anchored the same way

# name|status command|open command|extra search words
ENTRIES=(
    "Updates|$S/updates-menu.sh --status|$S/updates-menu.sh"
    "Music|$S/music-menu.sh --status|$S/music-menu.sh"
    "Notes|$S/notes-menu.sh --status|$S/notes-menu.sh"
    "Network|$S/net-menu.sh --status|$S/net-menu.sh|firewall"
    "AppArmor|$S/security-menu.sh --status apparmor|$S/security-menu.sh apparmor"
    "Lynis|$S/lynis-menu.sh --status|$S/lynis-menu.sh"
    "Logs|$S/security-menu.sh --status logs|$S/security-menu.sh logs"
    "Virus scan|$S/virus-menu.sh --status|$S/virus-menu.sh"
    "AUR check|$S/aur-check.sh --status|$S/aur-check.sh"
    "Clean-up|$S/system-menu.sh --status|$S/system-menu.sh"
    "Report IP/URL|$S/report-menu.sh --status|$S/report-menu.sh"
    "Phone|$S/phone-menu.sh --status|$S/phone-menu.sh"
    "File shares|$S/shares-menu.sh --status|$S/shares-menu.sh"
    "Wallpaper|$S/wall-menu.sh --status|$S/wall-menu.sh"
)
NAME_W=13      # characters — the longest name ("Report IP/URL"), so the summaries line up

esc()  { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }   # Pango
emit() { jq -cn --arg text "$1" --arg class "$2" --arg tooltip "$3" \
             '{text: $text, class: $class, alt: $class, tooltip: $tooltip}'; }

# Icon colour per entry and state: green = protected or clean, yellow = worth a
# look, red = act on it, lavender = running or present (music playing, a phone
# plugged in, notes kept), grey = idle or not installed yet.
colour() {
    case "$1:$2" in
        *:critical)                                              echo "#f38ba8" ;;
        *:warning|AppArmor:complain)                             echo "#f9e2af" ;;
        AppArmor:enforce|Network:ok|"Virus scan:ok")             echo "#a6e3a1" ;;
        *:active|*:connected|*:some)                             echo "#b4befe" ;;
        *:none|*:missing|AppArmor:off|AppArmor:idle)             echo "#7f849c" ;;
        *)                                                       echo "#cdd6f4" ;;
    esac
}

# NAME[i] CLASS[i] ICON[i] SUMMARY[i] for every entry. The status commands run
# in parallel: one after another they take ~0.4 s, which is felt on a click.
gather() {
    local tmp i name cmd
    tmp=$(mktemp -d) || return 1
    for i in "${!ENTRIES[@]}"; do
        IFS='|' read -r name cmd _ <<<"${ENTRIES[i]}"
        NAME[i]=$name
        bash -c "$cmd" >"$tmp/$i" 2>/dev/null &
    done
    wait
    for i in "${!ENTRIES[@]}"; do
        # \x1f, not a tab: bash collapses empty tab-separated fields.
        IFS=$'\x1f' read -r "CLASS[i]" "ICON[i]" "SUMMARY[i]" < <(
            jq -r '[.class // "", ((.text // "") | split(" ")[0]), .summary // ""] | join("\u001f")' "$tmp/$i" 2>/dev/null)
    done
    rm -rf "$tmp"
}

# anchor_under_cursor WIDTH (placement under the button) — shared with phone-menu.sh.
source "$S/rofi-anchor.sh"

status() {
    local NAME=() CLASS=() ICON=() SUMMARY=() i n=0 worst=ok tip=""
    gather
    for i in "${!ENTRIES[@]}"; do
        case ${CLASS[i]} in
            critical) n=$((n + 1)); worst=critical ;;
            warning)  n=$((n + 1)); [[ $worst == critical ]] || worst=warning ;;
        esac
        tip+="<span foreground='$(colour "${NAME[i]}" "${CLASS[i]}")'>${ICON[i]}</span>  <b>${NAME[i]}</b> · $(printf '%s' "${SUMMARY[i]}" | esc)"$'\n'
    done
    tip+=$'\n'"<i>Click: open one · Right-click: log viewer</i>"
    if (( n )); then emit "󰻌 $n" "$worst" "$tip"; else emit "󰕥" ok "$tip"; fi
}

dropdown() {
    local NAME=() CLASS=() ICON=() SUMMARY=() rows=() plain=() i open name
    gather
    for i in "${!ENTRIES[@]}"; do
        # Search text, plus hyphen-free copies ("Clean-up" → "Cleanup") so typing
        # them without the hyphen finds them too.
        # What typing searches: the name, word starts only (-matching prefix),
        # so "n" is Notes and Network — searching the summaries too found every
        # row with an "n" anywhere (2026-10-11). Plus the entry's extra words
        # and hyphen-free names ("Cleanup"). Escaped like the display text:
        # interactive rofi parses it as markup, and a bare "&" hid a row.
        IFS='|' read -r _ _ _ extra <<<"${ENTRIES[i]}"
        plain+=("$(printf '%s' "${NAME[i]} ${extra} ${NAME[i]//-/}" | esc)")
        # Padded names in a monospaced font put the summaries in a column. The icon
        # uses the fixed-width Nerd Font: the theme's "Propo" one gives every icon
        # its own width, which pushes the column out of line.
        printf -v name "%-${NAME_W}s" "${NAME[i]}"
        rows+=("<span font_family='JetBrainsMono Nerd Font' foreground='$(colour "${NAME[i]}" "${CLASS[i]}")'>${ICON[i]:-󰘥}</span>   <b>$name</b>  <span foreground='#a6adc8'>$(printf '%s' "${SUMMARY[i]:-no status}" | esc)</span>")
    done
    # One click picks a row (rofi's default wants a double click); a click
    # outside closes it; typing filters. rofi searches each row's plain text
    # and shows its "display" — searching the markup itself matched every row
    # on "span" or "fore" (2026-10-11).
    i=$(for i in "${!rows[@]}"; do printf '%s\0display\x1f%s\n' "${plain[i]}" "${rows[i]}"; done |
        rofi -dmenu -i -no-custom -markup-rows -matching prefix -format i -p "" \
             -theme "$theme" -theme-str "$(anchor_under_cursor "$PICKER_W") listview { lines: ${#rows[@]}; }" \
             -me-select-entry '' -me-accept-entry MousePrimary) || exit 0
    [[ $i =~ ^[0-9]+$ ]] || exit 0
    IFS='|' read -r _ _ open _ <<<"${ENTRIES[i]}"
    SEC_MENU_POS=$(anchor_under_cursor "$MENU_W")
    export SEC_MENU_POS
    exec bash -c "$open"
}

# ── main ────────────────────────────────────────────────────────────────────
[[ ${1:-} == --status ]] && { status; exit 0; }

# A second click on the button closes the dropdown instead of stacking another.
if pgrep -u "$USER" -x rofi >/dev/null; then
    pkill -u "$USER" -x rofi
    exit 0
fi
dropdown
