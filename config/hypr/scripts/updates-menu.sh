#!/usr/bin/env bash
# Updates — a row in the hub dropdown (sec-picker.sh): pending pacman and
# Flatpak updates, security fixes waiting to be installed, and how long since
# the last full upgrade.
#
#   updates-menu.sh            the menu
#   updates-menu.sh --status   one JSON line for the hub row
#   updates-menu.sh refresh    re-check now (touches the network)
#
# The checks touch the network, so they're cached — pending updates for an
# hour, security advisories for six — and re-checked at once when anything is
# installed meanwhile (an upgrade from the bar's update icon, a terminal,
# Discover). --status only reads the cache and, when it's stale, starts a
# refresh in the background: the dropdown never waits on a mirror.

# -u and pipefail, but NOT -e — bound to clicks; see clipboard-menu.sh.
set -uo pipefail
MENU_APP="Updates"; MENU_ICON="󰚰"
source "${BASH_SOURCE[0]%/*}/menu-lib.sh"

C="$AUCH_CACHE/updates"; mkdir -p "$C"
STALE_DAYS=7      # yellow when the last full upgrade is older than this
SELF="$HOME/.config/hypr/scripts/updates-menu.sh"

last_upgrade() {   # epoch of the last "starting full system upgrade"
    local d
    d=$(grep 'starting full system upgrade' /var/log/pacman.log 2>/dev/null | tail -n1 | grep -oE '^\[[^]]+\]' | tr -d '[]')
    [[ -n $d ]] && date -d "$d" +%s 2>/dev/null
}
count() { [[ -s $1 ]] && grep -c . "$1" || echo 0; }

# Installed or upgraded anything since the last check? pacman's local database
# changes with every transaction, and Flatpak touches .changed after each
# install or update. Without this an upgrade done elsewhere left the old count
# up for an hour (11 shown right after an upgrade, 2026-10-10).
changed_since_check() {
    local f
    for f in /var/lib/pacman/local /var/lib/flatpak/.changed "${XDG_DATA_HOME:-$HOME/.local/share}/flatpak/.changed"; do
        [[ $f -nt $C/checked ]] && return 0
    done
    return 1
}

# Offline re-check after an upgrade: keep the old list minus what is installed
# now — a cached "name old -> new" line goes once that version (or a later one)
# is in, or the package is gone.
prune_installed() {
    local -A inst=()
    local name old arrow new v
    [[ -s $C/pacman ]] || return 0
    while read -r name v; do inst[$name]=$v; done < <(pacman -Q $(awk '{ print $1 }' "$C/pacman") 2>/dev/null)
    while read -r name old arrow new; do
        [[ -n ${inst[$name]:-} ]] && (( $(vercmp "${inst[$name]}" "$new") < 0 )) && printf '%s %s %s %s\n' "$name" "$old" "$arrow" "$new"
    done <"$C/pacman" >"$C/pacman.tmp"
    mv "$C/pacman.tmp" "$C/pacman"
}

refresh() {
    local rc
    exec 9>"$C/.lock"
    flock -n 9 || return 0                     # one refresh at a time
    # checkupdates: 0 = updates listed, 2 = none, anything else = it failed
    # (offline, mirror down) — then the old list stays.
    checkupdates >"$C/pacman.tmp" 2>/dev/null; rc=$?
    if (( rc == 0 || rc == 2 )); then mv "$C/pacman.tmp" "$C/pacman"; else rm -f "$C/pacman.tmp"; prune_installed; fi
    if command -v flatpak >/dev/null; then
        flatpak remote-ls --updates --columns=application >"$C/flatpak.tmp" 2>/dev/null \
            && mv "$C/flatpak.tmp" "$C/flatpak" || rm -f "$C/flatpak.tmp"
    fi
    if [[ ${1:-} == force ]] || ! fresh "$C/advisories" 21600; then
        arch-audit -u >"$C/advisories.tmp" 2>/dev/null \
            && mv "$C/advisories.tmp" "$C/advisories" || rm -f "$C/advisories.tmp"
    fi
    touch "$C/checked"
    pkill -u "$USER" -RTMIN+11 waybar 2>/dev/null || true   # the shield's tooltip and count, now
}

status() {
    local np nf na le days=0 cls text summary when changed=0
    if changed_since_check; then
        changed=1; setsid -f "$SELF" refresh >/dev/null 2>&1   # the cached counts predate it
    elif ! fresh "$C/checked" 3600; then
        setsid -f "$SELF" refresh >/dev/null 2>&1
    fi
    np=$(count "$C/pacman"); nf=$(count "$C/flatpak"); na=$(count "$C/advisories")
    le=$(last_upgrade)
    if [[ -n $le ]]; then days=$(( ($(date +%s) - le) / 86400 )); when="upgraded $(age $(( $(date +%s) - le )))"
    else when="no full upgrade logged"; fi

    cls=ok
    (( na )) && cls=warning
    (( days >= STALE_DAYS )) && cls=warning
    (( days >= 30 )) && cls=critical
    text="󰚰"; (( np + nf && ! changed )) && text="󰚰 $((np + nf))"

    if [[ -f $C/checked ]] && (( ! changed )); then
        summary="$((np + nf)) update$( ((np + nf == 1)) || echo s)"
        (( na )) && summary+=" · $na security fix$( ((na == 1)) || echo es)"
        summary+=" · $when"
    else
        summary="checking… · $when"
    fi
    emit "$text" "$cls" "<b>Updates</b>
$( ((changed)) && echo "Re-checking: something was installed since the last check" || echo "pacman: $np · Flatpak: $nf · security fixes waiting: $na")
Last full upgrade: $when
Checked: $( [[ -f $C/checked ]] && age $(( $(date +%s) - $(stat -c %Y "$C/checked") )) || echo not yet)" "$summary"
}

menu() {
    local i np nf na le checked
    while :; do
        np=$(count "$C/pacman"); nf=$(count "$C/flatpak"); na=$(count "$C/advisories")
        le=$(last_upgrade)
        checked=$( [[ -f $C/checked ]] && age $(( $(date +%s) - $(stat -c %Y "$C/checked") )) || echo "not yet")
        i=$(printf '%s\n' \
                "󰚰  Update now · pacman, then Flatpak, in a terminal" \
                "󰏗  Pending packages · $np ›" \
                "󰒃  Security fixes waiting · $na ›" \
                "󰏓  Flatpak updates · $nf ›" \
                "󰑐  Check again now" \
                "󰈙  Arch news" |
            pick "Updates" "Last full upgrade: $( [[ -n $le ]] && date -d "@$le" '+%F %H:%M' || echo unknown) · checked $checked") || return
        case $i in
            0) in_terminal "Update" "sudo pacman -Syu; command -v flatpak >/dev/null && flatpak update; '$SELF' refresh force"
               exit 0 ;;
            1) list_rows "Pending" "pacman updates — name, installed → new" <"$C/pacman" ;;
            2) list_rows "Security fixes" "Advisories whose fix is already packaged: updating installs it" <"$C/advisories" ;;
            3) list_rows "Flatpak" "Flatpak apps with an update" <"$C/flatpak" ;;
            4) notify "Checking mirrors, Flatpak and the security tracker…"
               refresh force
               notify "Done: $(count "$C/pacman") pacman, $(count "$C/flatpak") Flatpak, $(count "$C/advisories") security" ;;
            5) in_pager "Arch news" "informant list 2>/dev/null || echo 'informant is not installed'" ;;
        esac
    done
}

case ${1:-} in
    --status) status ;;
    refresh)  refresh "${2:-}" ;;
    *)        toggle_rofi; menu ;;
esac
