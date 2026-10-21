#!/usr/bin/env bash
# System menu — system details and clean-up, in rofi. Same look as the security
# menu (rofi/logviewer/style.rasi); its broom icon sits in the security pill of
# the "auchsec" Waybar layout (config/waybar/security.jsonc).
#
#   system-menu.sh            the menu
#   system-menu.sh --status   one JSON line for the Waybar module
#
# Sizes and lists need no password. Every clean-up asks first. The ones needing
# root open a terminal that shows the command, and pacman / flatpak ask again
# there; ~/.cache folders and the trash are yours, deleted after a yes here.

# -u and pipefail, but NOT -e — same reasoning as clipboard-menu.sh: this is
# bound to clicks, and `set -e` turns a cosmetic failure into a dead button.
set -uo pipefail

theme="$HOME/.config/rofi/logviewer/style.rasi"

KEEP=2               # package versions paccache keeps: current + one to downgrade to
JOURNAL_KEEP=4weeks  # the security menu reads 7 days of sign-ins and the previous boot
GIB=1073741824

# ── helpers ─────────────────────────────────────────────────────────────────
esc()    { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }   # Pango
notify() { notify-send -a "System" -u low -t 2000 "󰃢  System" "$1"; }
# "summary" is extra — Waybar ignores it; sec-picker.sh shows it in its rows.
emit()   { jq -cn --arg text "$1" --arg class "$2" --arg tooltip "$3" --arg summary "${4:-}" \
               '{text: $text, class: $class, alt: $class, tooltip: $tooltip, summary: $summary}'; }
human()  { numfmt --to=iec "${1:-0}"; }   # bytes -> 8.6G
bytes()  { du -sb "$@" 2>/dev/null | awk '{s += $1} END {print s + 0}'; }

# pick PROMPT MESSAGE — rows on stdin; prints the chosen row's index, or
# nothing (and fails) on Esc. Opened from sec-picker.sh, SEC_MENU_POS holds a
# -theme-str that anchors every menu under the bar button, like the dropdown.
# One click picks, like the dropdown (rofi's default wants a double click).
pick() { rofi -dmenu -i -no-custom -format i -p "$1" -mesg "$2" -theme "$theme" -me-select-entry '' -me-accept-entry MousePrimary ${SEC_MENU_POS:+-theme-str "$SEC_MENU_POS"}; }

# confirm QUESTION — 0 only on an explicit yes.
confirm() {
    local i
    i=$(printf '%s\n' "󰁍  No, back" "󰗩  Yes" | pick "Sure?" "$1") || return 1
    [[ $i == 1 ]]
}

# in_terminal TITLE COMMAND — run COMMAND (bash) in kitty, keep the window open
# until Enter, close the menu. Root commands run `sudo -v` first.
in_terminal() {
    setsid -f kitty --title "$1" bash -c "$2; echo; read -rp 'Done — press Enter to close. '" >/dev/null 2>&1
    exit 0
}

# Bytes `paccache -d ARGS` says it would free (a dry run, no root needed).
pac_bytes() {
    local line num unit
    line=$(paccache -d "$@" 2>/dev/null | grep -oE 'disk space saved: [0-9.]+ [KMGT]?i?B' | tail -1)
    [[ -z $line ]] && { echo 0; return; }
    read -r _ _ _ num unit <<<"$line"
    if [[ $unit == B ]]; then echo "${num%.*}"; else numfmt --from=iec-i "${num}${unit%B}"; fi
}
pac_saving() { echo $(( $(pac_bytes -k"$KEEP") + $(pac_bytes -uk0) )); }

journal_bytes() {   # "Archived and active journals take up 352M in the file system."
    journalctl --disk-usage 2>/dev/null | grep -oE '[0-9.]+[KMGT]?B? ' | head -1 |
        sed 's/B\? $//' | numfmt --from=iec 2>/dev/null || echo 0
}

timer_on() { systemctl is-enabled -q paccache.timer 2>/dev/null; }

# ── Waybar status ───────────────────────────────────────────────────────────
status() {
    local pac trash text cls total
    pac=$(pac_saving)
    trash=$(bytes "$HOME/.local/share/Trash")
    total=$((pac + trash))
    text="󰃢"; cls=ok
    (( total >= GIB )) && { text="󰃢 $(human "$total")"; cls=warning; }
    emit "$text" "$cls" "<b>Clean-up</b>
Package cache: $(human "$pac") can go (keeps the newest $KEEP of each)
Weekly automatic clean-up: $(timer_on && echo on || echo off)
Trash: $(human "$trash")
Journal: $(human "$(journal_bytes)")
~/.cache: $(human "$(bytes "$HOME/.cache")")

Disk: $(df -h --output=used,size,pcent / | awk 'NR == 2 {print $1 " of " $2 " used (" $3 ")"}')

<i>Click: system menu</i>" \
        "$( (( total >= GIB )) && echo "$(human "$total") can go" || echo "nothing much to clean") · disk $(df --output=pcent / | awk 'NR == 2 {print $1}') used"
}

# ── views ───────────────────────────────────────────────────────────────────
# list_rows TITLE MESSAGE — rows on stdin; Back on top, Copy on pick.
list_rows() {
    local title=$1 mesg=$2 rows=() i
    mapfile -t rows
    while :; do
        i=$( { echo "󰁍  Back"; if (( ${#rows[@]} )); then printf '%s\n' "${rows[@]}"; fi; } | pick "$title" "$mesg") || return
        (( i == 0 )) && return
        printf '%s' "${rows[i-1]}" | wl-copy && notify "Copied to the clipboard"
    done
}

menu_paccache() {
    local i size saving timer_row
    while :; do
        size=$(bytes /var/cache/pacman/pkg)
        saving=$(pac_saving)
        if timer_on; then timer_row="󰾨  Weekly automatic clean-up is on (paccache.timer, keeps 3)"
        else timer_row="󱤥  Turn on weekly automatic clean-up (paccache.timer, keeps 3)"; fi
        i=$(printf '%s\n' "󰁍  Back" \
                "󰃢  Keep the newest $KEEP of each package · frees $(human "$saving")" \
                "$timer_row" \
                "󰉹  List the files that would go" |
            pick "Package cache" "/var/cache/pacman/pkg holds $(human "$size"). Every update leaves the old package file behind, and nothing removes them unless the timer is on.") || return
        case $i in
            0) return ;;
            1) confirm "Delete $(human "$saving") of old package files? You keep the newest $KEEP versions of each, so you can still downgrade one step." &&
                   in_terminal "Package cache" "sudo -v && sudo paccache -rk$KEEP && sudo paccache -ruk0" ;;
            2) timer_on && { notify "Already on"; continue; }
               in_terminal "paccache.timer" "sudo -v && sudo systemctl enable --now paccache.timer && systemctl list-timers paccache.timer --no-pager" ;;
            3) list_rows "Would go" "Files paccache -rk$KEEP and -ruk0 would delete" \
                   < <({ paccache -dvk"$KEEP"; paccache -dvuk0; } 2>/dev/null | grep '\.pkg\.tar\.[a-z0-9]*$') ;;
        esac
    done
}

menu_orphans() {
    local i rows=()
    mapfile -t rows < <(pacman -Qdt 2>/dev/null)
    if (( ! ${#rows[@]} )); then
        printf '%s\n' "󰁍  Back" | pick "Orphans" "No orphan packages — nothing installed only as a dependency of something you removed." >/dev/null
        return
    fi
    i=$( { printf '%s\n' "󰁍  Back" "󰗩  Remove all ${#rows[@]} (pacman lists them and asks first)"; printf '%s\n' "${rows[@]}"; } |
         pick "Orphans" "Installed as dependencies, needed by nothing now. Check each: an optional dependency you use can show up here.") || return
    case $i in
        0) return ;;
        1) in_terminal "Orphans" 'sudo -v && sudo pacman -Rns $(pacman -Qdtq)' ;;
    esac
}

menu_journal() {
    local i
    i=$(printf '%s\n' "󰁍  Back" "󰃢  Keep only the last ${JOURNAL_KEEP/weeks/ weeks}" |
        pick "Journal" "The system log takes $(human "$(journal_bytes)"). The security menu reads 7 days of sign-ins and the previous boot, so ${JOURNAL_KEEP/weeks/ weeks} keeps all of it.") || return
    (( i == 1 )) && confirm "Delete journal entries older than ${JOURNAL_KEEP/weeks/ weeks}?" &&
        in_terminal "Journal" "sudo -v && sudo journalctl --vacuum-time=$JOURNAL_KEEP && journalctl --disk-usage"
}

menu_cache() {
    local i rows=() names=() name size note
    while :; do
        rows=(); names=()
        while IFS=$'\t' read -r size name; do
            name=${name%/}; name=${name##*/}   # du prints "…/.cache/chromium/"
            names+=("$name")
            rows+=("$(printf '%-7s %s' "$(human "$size")" "$name")")
        done < <(du -sb "$HOME"/.cache/*/ 2>/dev/null | sort -rn | head -n 25)
        i=$( { echo "󰁍  Back"; printf '%s\n' "${rows[@]}"; } |
             pick "~/.cache" "$(human "$(bytes "$HOME/.cache")") in all. Pick a folder to delete it — apps rebuild their own cache.") || return
        (( i == 0 )) && return
        name=${names[i-1]}
        [[ -n $name && $name != */* && $name != . && $name != .. ]] || continue
        case $name in
            cliphist)              note="This is your clipboard history — Super+V starts empty afterwards." ;;
            apply-config-backups)  note="Snapshots apply-config.sh takes before each sync; it makes a new one next run." ;;
            chromium|mozilla|zen*) note="Close the browser first." ;;
            *)                     note="" ;;
        esac
        if confirm "Delete ~/.cache/$name ($(human "$(bytes "$HOME/.cache/$name")"))? $note"; then
            size=$(bytes "$HOME/.cache/$name")
            rm -rf -- "${HOME:?}/.cache/$name" && notify "Deleted ~/.cache/$name — freed $(human "$size")"
        fi
    done
}

menu_trash() {
    local size
    size=$(bytes "$HOME/.local/share/Trash")
    confirm "Empty the trash ($(human "$size"))? Files there are gone for good." || return
    gio trash --empty && notify "Trash emptied — freed $(human "$size")"
}

menu_flatpak() {
    in_terminal "Flatpak" "flatpak uninstall --unused"
}

details() {
    local bat="" b
    for b in /sys/class/power_supply/BAT*; do
        [[ -r $b/capacity ]] || continue
        bat="󱈑  Battery: $(<"$b/capacity")%"
        [[ -r $b/energy_full && -r $b/energy_full_design ]] &&
            bat+=", health $(( $(<"$b/energy_full") * 100 / $(<"$b/energy_full_design") ))% of design"
    done
    {
        echo "󰘚  CPU: $(lscpu | sed -n 's/^Model name: *//p')"
        echo "󰍛  Memory: $(free -h | awk '/^Mem/ {print $3 " used of " $2 ", " $7 " available"}')"
        echo "󰍛  Swap: $(free -h | awk '/^Swap/ {print $3 " used of " $2}') ($(swapon --show=NAME --noheadings | paste -sd' '))"
        df -h --output=target,used,size,pcent -x tmpfs -x devtmpfs -x efivarfs 2>/dev/null |
            awk 'NR > 1 {print "󰋊  Disk " $1 ": " $2 " of " $3 " used (" $4 ")"}'
        [[ -n $bat ]] && echo "$bat"
        echo "󰌽  Kernel: $(uname -r)"
        echo "󰔟  Up: $(uptime -p | sed 's/^up //')"
        echo "󰏖  Packages: $(pacman -Q | wc -l) ($(pacman -Qe | wc -l) explicit, $(pacman -Qm | wc -l) foreign)"
        echo "󰚰  Last full upgrade: $(grep 'starting full system upgrade' /var/log/pacman.log | tail -1 | grep -oE '^\[[^]T]+' | tr -d '[')"
    } | list_rows "Details" "Pick a line to copy it."
}

menu_main() {
    local i pac saving orphans trash cache
    while :; do
        pac=$(bytes /var/cache/pacman/pkg); saving=$(pac_saving)
        orphans=$(pacman -Qdtq 2>/dev/null | wc -l)
        trash=$(bytes "$HOME/.local/share/Trash"); cache=$(bytes "$HOME/.cache")
        i=$(printf '%s\n' \
                "󰏗  Package cache · $(human "$pac"), $(human "$saving") can go ›" \
                "󰆴  Orphan packages · $orphans" \
                "󰠮  Journal · $(human "$(journal_bytes)") ›" \
                "󱁿  ~/.cache · $(human "$cache") ›" \
                "󰩹  Trash · $(human "$trash")" \
                "󰆧  Flatpak: remove unused runtimes" \
                "󰋽  System details ›" |
            pick "System" "$(uname -r) · up $(uptime -p | sed 's/^up //') · / $(df -h --output=pcent,avail / | awk 'NR == 2 {print $1 " used, " $2 " free"}')") || return
        case $i in
            0) menu_paccache ;;
            1) menu_orphans ;;
            2) menu_journal ;;
            3) menu_cache ;;
            4) menu_trash ;;
            5) menu_flatpak ;;
            6) details ;;
        esac
    done
}

# ── main ────────────────────────────────────────────────────────────────────
[[ ${1:-} == --status ]] && { status; exit 0; }

# A second click on the bar closes the menu instead of stacking another.
if pgrep -u "$USER" -x rofi >/dev/null; then
    pkill -u "$USER" -x rofi
    exit 0
fi
menu_main
