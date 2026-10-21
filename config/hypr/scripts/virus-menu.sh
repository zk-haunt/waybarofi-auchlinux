#!/usr/bin/env bash
# Virus scan — a row in the hub dropdown (sec-picker.sh), after ppk's
# Clamav-Pacman: scan a folder with ClamAV, then deal with what it finds.
#
#   virus-menu.sh               the menu
#   virus-menu.sh --status      one JSON line for the hub row
#   virus-menu.sh scan PATH     (internal) run in the terminal: scan, keep results
#
# ClamAV's real use here is files passing through — downloads, USB sticks,
# phone transfers — rather than the system itself. For each find: look it up
# on VirusTotal (only the file's SHA-256 leaves the machine, never the file),
# move it to quarantine (kept, unreadable, restorable), or delete it.

# -u and pipefail, but NOT -e — bound to clicks; see clipboard-menu.sh.
set -uo pipefail
MENU_APP="Virus scan"; MENU_ICON="󰒃"
source "${BASH_SOURCE[0]%/*}/menu-lib.sh"

C="$AUCH_CACHE/virus"; mkdir -p "$C"
Q="${XDG_DATA_HOME:-$HOME/.local/share}/auch/quarantine"
SELF="$HOME/.config/hypr/scripts/virus-menu.sh"

have_clam() { command -v clamscan >/dev/null; }
threats()   { sed -n 's/: \(.*\) FOUND$/|\1/p' "$C/last.log" 2>/dev/null; }   # "path|signature"

scan() {   # PATH — runs inside the terminal
    local path=$1
    echo "Scanning $path — infected files are listed as they're found."; echo
    clamscan -r -i --stdout "$path" | tee "$C/last.log.tmp"
    mv "$C/last.log.tmp" "$C/last.log"
    printf '%s\t%s\n' "$(date +%s)" "$path" >"$C/last.meta"
}

status() {
    local when path n
    if ! have_clam; then
        emit "󰒃" missing "<b>Virus scan</b>
Needs ClamAV — open this row to install it." "needs ClamAV — tap to install"
        return
    fi
    if ! IFS=$'\t' read -r when path 2>/dev/null <"$C/last.meta"; then
        emit "󰒃" none "<b>Virus scan</b>
No scan yet." "no scan yet"
        return
    fi
    n=$(threats | grep -c .)
    if (( n )); then
        emit "󰒃 $n" warning "<b>Virus scan · $n found</b>
In ${path/#$HOME/\~}, $(age $(( $(date +%s) - when )))" "$n threat$( ((n == 1)) || echo s) found in ${path/#$HOME/\~} · $(age $(( $(date +%s) - when )))"
    else
        emit "󰒃" ok "<b>Virus scan · clean</b>
${path/#$HOME/\~}, $(age $(( $(date +%s) - when )))" "clean · ${path/#$HOME/\~} · $(age $(( $(date +%s) - when )))"
    fi
}

start_scan() {   # PATH
    [[ -d $1 || -f $1 ]] || { notify "Not found: $1"; return; }
    in_terminal "Virus scan" "'$SELF' scan '$1'"
}

quarantine() {   # FILE
    local dest
    mkdir -p "$Q"; chmod 700 "$Q"
    dest="$Q/$(date +%Y%m%d-%H%M%S)-$(basename "$1")"
    mv -- "$1" "$dest" && chmod 000 "$dest" && printf '%s\t%s\n' "$dest" "$1" >>"$Q/index.tsv" &&
        notify "Quarantined: $(basename "$1")"
}

threat_menu() {   # PATH SIGNATURE
    local i sum
    i=$(printf '%s\n' "󰖟  Look it up on VirusTotal · sends only its SHA-256" "󰀦  Move to quarantine · kept, unreadable, restorable" "󰆴  Delete it" "󰁍  Leave it" |
        pick "Threat" "$(printf '%s' "$2 in ${1/#$HOME/\~}" | esc)") || return
    case $i in
        0) sum=$(sha256sum -- "$1" | cut -d' ' -f1) && xdg-open "https://www.virustotal.com/gui/file/$sum" >/dev/null 2>&1 & ;;
        1) quarantine "$1" ;;
        2) confirm "Delete $(basename "$1") for good?" && rm -f -- "$1" && notify "Deleted $(basename "$1")" ;;
    esac
}

results() {
    local lines=() rows=() i p s
    mapfile -t lines < <(threats)
    for l in "${lines[@]}"; do IFS='|' read -r p s <<<"$l"; rows+=("$( [[ -e $p ]] && echo 󰀦 || echo 󰄬)  ${p/#$HOME/\~} · $s"); done
    i=$( { echo "󰁍  Back"; if (( ${#rows[@]} )); then printf '%s\n' "${rows[@]}"; fi; } |
         pick "Last scan" "${#rows[@]} found · 󰄬 = already moved or deleted") || return
    (( i == 0 )) && return
    IFS='|' read -r p s <<<"${lines[i-1]}"
    [[ -e $p ]] || { notify "Already gone: $p"; return; }
    threat_menu "$p" "$s"
}

quarantine_menu() {
    local rows=() entries=() i dest orig
    [[ -f $Q/index.tsv ]] && while IFS=$'\t' read -r dest orig; do [[ -e $dest ]] && { entries+=("$dest|$orig"); rows+=("󰀦  ${orig/#$HOME/\~}"); }; done <"$Q/index.tsv"
    (( ${#rows[@]} )) || { notify "Quarantine is empty"; return; }
    i=$(printf '%s\n' "${rows[@]}" | pick "Quarantine" "Pick a file to restore or delete it") || return
    IFS='|' read -r dest orig <<<"${entries[i]}"
    i=$(printf '%s\n' "󰑐  Restore to ${orig/#$HOME/\~}" "󰆴  Delete for good" | pick "Quarantine" "$(basename "$orig")") || return
    case $i in
        0) confirm "Put it back? ClamAV flagged it." && chmod 600 "$dest" && mv -- "$dest" "$orig" && notify "Restored ${orig/#$HOME/\~}" ;;
        1) confirm "Delete it for good?" && rm -f -- "$dest" && notify "Deleted" ;;
    esac
}

menu() {
    local i path when
    if ! have_clam; then
        i=$(printf '%s\n' "󰇚  Install ClamAV · in a terminal (then a ~200 MB signature download)" |
            pick "Virus scan" "Scanning needs ClamAV") || return
        in_terminal "Install ClamAV" "sudo pacman -S --needed clamav && sudo freshclam"; return
    fi
    while :; do
        i=$(printf '%s\n' "󰉍  Scan Downloads" "󰋜  Scan my home folder · slow" "󰉋  Scan a folder…" \
                "󰀦  Last results · $(threats | grep -c .) found ›" "󰒃  Quarantine ›" \
                "󰑐  Update signatures (freshclam)" "󰔟  Keep signatures updated · daily service" |
            pick "Virus scan" "$(IFS=$'\t' read -r when path 2>/dev/null <"$C/last.meta" && echo "Last scan: ${path/#$HOME/\~}, $(age $(( $(date +%s) - when )))" || echo "No scan yet")") || return
        case $i in
            0) start_scan "$HOME/Downloads"; return ;;
            1) start_scan "$HOME"; return ;;
            2) path=$(ask "Folder" "Full path of a folder or file to scan" "$HOME/") || continue
               start_scan "${path/#\~/$HOME}"; return ;;
            3) results ;;
            4) quarantine_menu ;;
            5) in_terminal "freshclam" "sudo freshclam"; return ;;
            6) in_terminal "freshclam service" "sudo systemctl enable --now clamav-freshclam.service && systemctl status clamav-freshclam.service --no-pager"; return ;;
        esac
    done
}

case ${1:-} in
    --status) status ;;
    scan)     scan "${2:?path}" ;;
    *)        toggle_rofi; menu ;;
esac
