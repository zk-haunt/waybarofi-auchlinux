#!/usr/bin/env bash
# Lynis — a row in the hub dropdown (sec-picker.sh): the hardening score with
# its history, the warnings and suggestions, and a button to run an audit.
#
#   lynis-menu.sh               the menu
#   lynis-menu.sh --status      one JSON line for the hub row
#   lynis-menu.sh import FILE   (internal) read the lines the terminal copied
#
# /var/log/lynis-report.dat is root-only. After an audit — or on "Read the
# latest report" — the terminal copies just the score, warnings and
# suggestions into ~/.cache/auch/lynis/, so the menu can list them without a
# password. Each read adds a line to the score history.

# -u and pipefail, but NOT -e — bound to clicks; see clipboard-menu.sh.
set -uo pipefail
MENU_APP="Lynis"; MENU_ICON="󰒃"
source "${BASH_SOURCE[0]%/*}/menu-lib.sh"

C="$AUCH_CACHE/lynis"; mkdir -p "$C"
SELF="$HOME/.config/hypr/scripts/lynis-menu.sh"
REPORT=/var/log/lynis-report.dat
# Copy the report's score/warning/suggestion lines into a user-owned file, then import.
GRAB="t=\$(mktemp) && sudo grep -E '^(hardening_index|warning\\[\\]|suggestion\\[\\]|report_datetime_end)=' $REPORT >\"\$t\" && '$SELF' import \"\$t\"; rm -f \"\$t\""

import() {
    local f=$1 score when
    [[ -s $f ]] || { echo "Nothing read from the report."; return 1; }
    score=$(sed -n 's/^hardening_index=//p' "$f" | tail -n1)
    when=$(sed -n 's/^report_datetime_end=//p' "$f" | tail -n1)
    # warning[]=ID|text|details|solution|  ->  "ID  text — details"
    for kind in warning suggestion; do
        grep "^$kind\[\]=" "$f" | sed "s/^$kind\[\]=//" |
            awk -F'|' '{ d = ($3 != "" && $3 != "-") ? " — " $3 : ""; print $1 "  " $2 d }' >"$C/${kind}s"
    done
    [[ -n $score ]] && printf '%s\t%s\n' "${when:-$(date '+%F %T')}" "$score" >>"$C/history.tsv"
    echo "Lynis score $score — $(grep -c . "$C/warnings") warnings, $(grep -c . "$C/suggestions") suggestions saved for the menu."
}

last() { [[ -s $C/history.tsv ]] && tail -n1 "$C/history.tsv"; }

status() {
    local when score secs
    if ! IFS=$'\t' read -r when score < <(last); then
        emit "󰒃" none "<b>Lynis</b>
No audit read yet. Run one from the menu (about 3 minutes)." "no audit yet — run one"
        return
    fi
    secs=$(( $(date +%s) - $(date -d "$when" +%s 2>/dev/null || date +%s) ))
    emit "󰒃 $score" ok "<b>Lynis · hardening index $score</b>
Audited $(age "$secs")
Warnings: $(count_lines "$C/warnings") · suggestions: $(count_lines "$C/suggestions")" \
        "score $score · $(count_lines "$C/warnings") warnings · audited $(age "$secs")"
}

explain() {   # LINE -> lynis's own explanation of that test, in a pager
    local id=${1%% *}
    in_pager "Lynis $id" "sudo -v && sudo lynis show details $id"
}

findings() {   # KIND TITLE MESSAGE
    local rows=() i
    [[ -f $C/$1 ]] && mapfile -t rows <"$C/$1"
    while :; do
        i=$( { echo "󰁍  Back"; if (( ${#rows[@]} )); then printf '%s\n' "${rows[@]}"; fi; } | pick "$2" "$3") || return
        (( i == 0 )) && return
        explain "${rows[i-1]}"; exit 0
    done
}

menu() {
    local i when score nw ns
    while :; do
        IFS=$'\t' read -r when score < <(last) || { when=""; score=""; }
        nw=$(count_lines "$C/warnings"); ns=$(count_lines "$C/suggestions")
        i=$(printf '%s\n' \
                "󰒃  Run an audit now · about 3 minutes, in a terminal" \
                "󰀦  Warnings · $nw ›" \
                "󰋽  Suggestions · $ns ›" \
                "󰄪  Score history ›" \
                "󰈔  Read the latest report · if you ran lynis yourself" |
            pick "Lynis" "${score:+Hardening index $score, audited $when}${score:-No audit read yet} · harden-system.sh lists the suggestions declined on purpose") || return
        case $i in
            0) in_terminal "Lynis audit" "sudo -v && sudo lynis audit system && $GRAB"; exit 0 ;;
            1) findings warnings "Warnings" "Pick one for lynis's explanation (asks your password)" ;;
            2) findings suggestions "Suggestions" "Pick one for lynis's explanation (asks your password)" ;;
            3) list_rows "Score history" "Each audit read here — date, hardening index" < <(tac "$C/history.tsv" 2>/dev/null | tr '\t' ' ') ;;
            4) in_terminal "Lynis report" "sudo -v && $GRAB"; exit 0 ;;
        esac
    done
}

case ${1:-} in
    --status) status ;;
    import)   import "${2:?file}" ;;
    *)        toggle_rofi; menu ;;
esac
