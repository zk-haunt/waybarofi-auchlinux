#!/usr/bin/env bash
# File shares — a row in the hub dropdown (sec-picker.sh), after ppk's
# FileServerGui: find SMB (Windows/Samba) shares on this network, open them in
# Dolphin, or browse and download right here.
#
#   shares-menu.sh            the menu
#   shares-menu.sh --status   one JSON line for the hub row
#
# Finding shares means scanning the subnet for port 445 with nmap — on a work
# or school network that can look like an attack, so it asks first, and a
# server can be added by name instead. Logins go to smbclient through its
# PASSWD environment variable (not the command line, which any process can
# read) and are forgotten when the menu closes.

# -u and pipefail, but NOT -e — bound to clicks; see clipboard-menu.sh.
set -uo pipefail
MENU_APP="File shares"; MENU_ICON="󰉋"
source "${BASH_SOURCE[0]%/*}/menu-lib.sh"

C="$AUCH_CACHE/shares"; mkdir -p "$C"
LIST="$C/shares"           # "host|share|comment" per line, from the last scan
SMB_USER=""; SMB_PASS=""   # this run only

have_nmap() { command -v nmap >/dev/null; }

smb() {   # smbclient, as guest or with the login given in this run
    if [[ -n $SMB_USER ]]; then PASSWD="$SMB_PASS" smbclient -U "$SMB_USER" "$@" 2>/dev/null
    else smbclient -N "$@" 2>/dev/null; fi
}
shares_of() { smb -L "//$1" -g | awk -F'|' -v h="$1" '$1 == "Disk" { print h "|" $2 "|" $3 }'; }

subnet() {   # this machine's network, at most a /24 around it
    local dev cidr ip pfx
    dev=$(ip route show default 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
    cidr=$(ip -4 -o addr show dev "$dev" 2>/dev/null | awk '{ print $4; exit }')
    [[ -n $cidr ]] || return 1
    ip=${cidr%/*}; pfx=${cidr#*/}
    (( pfx < 24 )) && pfx=24
    echo "$ip/$pfx"
}

scan() {
    local net hosts=() h
    net=$(subnet) || { notify "Not connected to a network"; return 1; }
    confirm "Scan $net for file sharing (port 445)? On a work or school network this can look like an attack — only do it where that's fine." || return 1
    notify "Scanning $net — this takes a few seconds…"
    mapfile -t hosts < <(nmap -n -Pn -T4 -p 445 --open -oG - "$net" 2>/dev/null | awk '/445\/open/ { print $2 }')
    : >"$LIST.tmp"
    for h in "${hosts[@]}"; do shares_of "$h" >>"$LIST.tmp"; done
    mv "$LIST.tmp" "$LIST"; touch "$C/scanned"
    notify "Found $(grep -c . "$LIST") shares on ${#hosts[@]} computer$( ((${#hosts[@]} == 1)) || echo s)"
}

status() {
    local n hosts
    if ! have_nmap; then
        emit "󰉋" missing "<b>File shares</b>
Scanning for shares needs nmap — open this row to install it, or add a server by name." "needs nmap to scan — tap to install"
        return
    fi
    if [[ -f $C/scanned ]]; then
        n=$(count_lines "$LIST"); hosts=$(cut -d'|' -f1 "$LIST" 2>/dev/null | sort -u | grep -c .)
        emit "󰉋" ok "<b>File shares</b>
$n shares on $hosts computers · scanned $(age $(( $(date +%s) - $(stat -c %Y "$C/scanned") )))" "$n shares on $hosts computers · scanned $(age $(( $(date +%s) - $(stat -c %Y "$C/scanned") )))"
    else
        emit "󰉋" ok "<b>File shares</b>
Find shared folders on this network." "find shared folders on this network"
    fi
}

# browse HOST SHARE [DIR] — list a folder; folders open, files download.
browse() {
    local host=$1 share=$2 dir=${3:-} rows=() kinds=() names=() i out
    out=$(smb "//$host/$share" -c "cd \"${dir:-/}\"; ls") || { notify "Couldn't open \\\\$host\\$share${SMB_USER:+ as $SMB_USER} — try Log in"; return; }
    while IFS=$'\x1f' read -r kind name size; do
        [[ $name == . || $name == .. || -z $name ]] && continue
        names+=("$name"); kinds+=("$kind")
        if [[ $kind == D ]]; then rows+=("󰉋  $name/"); else rows+=("󰈔  $name · $(human "$size")"); fi
    done < <(python3 -c '
import re, sys
for line in sys.stdin:
    m = re.match(r"^  (.+?)\s+([A-Z]*)\s+(\d+)\s+\w{3} \w{3}\s+\d+ [\d:]+ \d{4}$", line.rstrip("\n"))
    if m:
        print("D" if "D" in m.group(2) else "F", m.group(1), m.group(3), sep="\x1f")' <<<"$out")
    i=$( { echo "󰁍  Back"; if (( ${#rows[@]} )); then printf '%s\n' "${rows[@]}"; fi; } |
         pick "\\\\$host\\$share" "/${dir} · folders open, files download to ~/Downloads") || return
    (( i == 0 )) && return
    if [[ ${kinds[i-1]} == D ]]; then
        browse "$host" "$share" "${dir:+$dir/}${names[i-1]}"
    else
        notify "Downloading ${names[i-1]}…"
        if smb "//$host/$share" -c "cd \"${dir:-/}\"; get \"${names[i-1]}\" \"$HOME/Downloads/${names[i-1]}\"" >/dev/null; then
            notify "Saved to ~/Downloads/${names[i-1]}"
        else
            notify "Download failed"
        fi
        browse "$host" "$share" "$dir"
    fi
}

share_menu() {   # HOST SHARE COMMENT
    local i
    while :; do
        i=$(printf '%s\n' "󰉋  Open in Dolphin" "󰈔  Browse here ›" "󰌆  Log in…${SMB_USER:+ (now: $SMB_USER)}" |
            pick "\\\\$1\\$2" "${3:-shared folder}${SMB_USER:+ · logged in as $SMB_USER}") || return
        case $i in
            0) setsid -f dolphin "smb://${SMB_USER:+$SMB_USER@}$1/$2" >/dev/null 2>&1; exit 0 ;;
            1) browse "$1" "$2" ;;
            2) SMB_USER=$(ask "User" "Username on $1 (DOMAIN\\user also works)" "") || continue
               SMB_PASS=$(ask "Password" "Password for $SMB_USER on $1 — kept only while this menu is open" "" password) || SMB_USER="" ;;
        esac
    done
}

add_server() {
    local t host share rows=() lines=() i
    t=$(ask "Server" "A server name or IP — or \\\\server\\share" "") || return
    t=${t//\\//}; t=${t#//}; t=${t#smb://}
    host=${t%%/*}; share=${t#*/}; [[ $share == "$t" ]] && share=""
    [[ -n $host ]] || return
    if [[ -n $share ]]; then share_menu "$host" "$share" ""; return; fi
    mapfile -t lines < <(shares_of "$host")
    (( ${#lines[@]} )) || { notify "No shares visible on $host as a guest — open \\\\$host\\share directly to log in"; return; }
    for l in "${lines[@]}"; do IFS='|' read -r _ s c <<<"$l"; rows+=("󰉋  \\\\$host\\$s${c:+ · $c}"); done
    i=$(printf '%s\n' "${rows[@]}" | pick "$host" "Shares visible as a guest") || return
    IFS='|' read -r host share c <<<"${lines[i]}"
    share_menu "$host" "$share" "$c"
}

menu() {
    local rows=() lines=() i l h s c
    while :; do
        rows=(); lines=()
        if have_nmap; then rows+=("󰍉  Scan this network for shares"); else rows+=("󰇚  Install nmap · needed to scan for shares"); fi
        rows+=("󰐕  Add a server by name…")
        if [[ -s $LIST ]]; then
            mapfile -t lines <"$LIST"
            for l in "${lines[@]}"; do IFS='|' read -r h s c <<<"$l"; rows+=("󰉋  \\\\$h\\$s${c:+ · $c}"); done
        fi
        i=$(printf '%s\n' "${rows[@]}" | pick "File shares" "$( [[ -f $C/scanned ]] && echo "Last scan: $(age $(( $(date +%s) - $(stat -c %Y "$C/scanned") )))" || echo "Not scanned yet") · Dolphin opens smb:// links") || return
        case $i in
            0) if have_nmap; then scan; else in_terminal "Install nmap" "sudo pacman -S --needed nmap"; return; fi ;;
            1) add_server ;;
            *) IFS='|' read -r h s c <<<"${lines[i-2]}"; share_menu "$h" "$s" "$c" ;;
        esac
    done
}

case ${1:-} in
    --status) status ;;
    *)        toggle_rofi; menu ;;
esac
