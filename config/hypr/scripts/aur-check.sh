#!/usr/bin/env bash
# AUR check — a row in the hub dropdown (sec-picker.sh), after ppk's
# scan-aur-package: look an AUR package over before building it.
#
#   aur-check.sh            the menu
#   aur-check.sh --status   one JSON line for the hub row
#
# What it checks, all read-only:
#   - the AUR's own data (aur.archlinux.org RPC): orphaned, out of date, brand
#     new, few votes, changed in the last days — when hijacks happen
#   - the PKGBUILD and its .install script, for lines that fetch or run code
#     outside the declared sources, decode or eval, enable services, or skip
#     checksums on a download
#   - a local blocklist, ~/.config/auch/aur-blocklist.txt
#   - optionally, a review by the local ollama model — a hint, not a verdict:
#     llm-findings.md measured these models missing shell bugs.
# ppk's script downloaded a public blocklist; that URL is gone (404,
# 2026-10-10) and nothing official replaces it, hence the local file.

# -u and pipefail, but NOT -e — bound to clicks; see clipboard-menu.sh.
set -uo pipefail
MENU_APP="AUR check"; MENU_ICON="󰏗"
source "${BASH_SOURCE[0]%/*}/menu-lib.sh"

AUR="https://aur.archlinux.org"
BLOCKLIST="${XDG_CONFIG_HOME:-$HOME/.config}/auch/aur-blocklist.txt"
AI_MODEL="${AUR_AI_MODEL:-qwen3.5:4b-q8_0}"   # llm-findings.md's pick for the desktop-open case

seed_blocklist() {
    [[ -f $BLOCKLIST ]] && return
    mkdir -p "${BLOCKLIST%/*}"
    cat >"$BLOCKLIST" <<'EOF'
# AUR packages never to build — one name per line; # starts a comment.
# Checked by ~/.config/hypr/scripts/aur-check.sh. Add names as incidents are announced
# (aur-general mailing list, archlinux.org news).
#
# July 2025: these shipped a remote-access trojan (CHAOS RAT); removed from the AUR.
librewolf-fix-bin
firefox-patch-bin
zen-browser-patched-bin
EOF
}
blocked() { seed_blocklist; grep -v '^\s*#' "$BLOCKLIST" | grep -qxF -- "$1"; }

# Lines worth a human look, as "LINE-NO: text" with a reason in front.
suspicious() {   # FILE
    awk '
        /^[[:space:]]*#/ { next }
        { r = "" }
        /(curl|wget)[[:space:]]/               { r = r (r == "" ? "" : "; ") "downloads at build time, outside the checksummed sources" }
        /base64[[:space:]]+(-d|--decode)/      { r = r (r == "" ? "" : "; ") "decodes hidden data" }
        /(^|[^A-Za-z_])eval[[:space:]]/        { r = r (r == "" ? "" : "; ") "eval runs a constructed string" }
        /\|[[:space:]]*(ba|z|da)?sh([[:space:]]|$)/ { r = r (r == "" ? "" : "; ") "pipes into a shell" }
        /python[23]?[[:space:]]+-c/            { r = r (r == "" ? "" : "; ") "runs inline Python" }
        /\/tmp\//                              { r = r (r == "" ? "" : "; ") "uses /tmp" }
        /(nc|ncat|socat)[[:space:]]+-/         { r = r (r == "" ? "" : "; ") "opens a network socket" }
        /systemctl[[:space:]]+(enable|start)/  { r = r (r == "" ? "" : "; ") "enables or starts a service" }
        /crontab|\.bashrc|\.zshrc|\.profile/   { r = r (r == "" ? "" : "; ") "touches startup files" }
        /chmod[[:space:]]+(\+x|[0-7]*7[0-7]*[[:space:]])/ && !/pkgdir/ { r = r (r == "" ? "" : "; ") "makes something executable outside the package" }
        /https?:\/\/([0-9]{1,3}\.){3}[0-9]{1,3}/ { r = r (r == "" ? "" : "; ") "downloads from a bare IP address" }
        /source.*http:\/\// || /^[[:space:]]*"?http:\/\//   { r = r (r == "" ? "" : "; ") "plain-http source (no TLS)" }
        r != "" { printf "%s · %d: %s\n", r, NR, $0 }
    ' "$1" | cut -c1-200
}

status() {
    local n
    n=$(pacman -Qmq 2>/dev/null | grep -c .)
    emit "󰏗" ok "<b>AUR check</b>
Look an AUR package over before you build it.
Installed from outside the repos: $n" "check a package before building it · $n installed from the AUR"
}

check() {   # PKG
    local pkg=$1 info pb inst insf rows=() acts=() now flags=() i
    notify "Asking the AUR about $pkg…"
    info=$(curl -fsS --max-time 15 "$AUR/rpc/v5/info?arg%5B%5D=$(jq -rn --arg s "$pkg" '$s|@uri')" 2>/dev/null) ||
        { notify "Couldn't reach the AUR"; return; }
    if [[ $(jq -r '.resultcount' <<<"$info") == 0 ]]; then
        flags+=("󰀦  Not in the AUR — removed, renamed or never existed. Don't build a copy found elsewhere.")
        blocked "$pkg" && flags+=("󰀦  On your blocklist")
        printf '%s\n' "${flags[@]}" | list_rows "$pkg" "No such AUR package"
        return
    fi
    now=$(date +%s)
    local name ver maint votes pop first mod ood url desc
    # \x1f, not a tab: bash collapses empty tab-separated fields, and an orphan's
    # maintainer is empty — every later field would shift.
    IFS=$'\x1f' read -r name ver maint votes pop first mod ood url desc < <(jq -r '.results[0] |
        [.Name, .Version, (.Maintainer // ""), .NumVotes, .Popularity, .FirstSubmitted, .LastModified,
         (.OutOfDate // ""), (.URL // ""), (.Description // "")] | map(tostring) | join("\u001f")' <<<"$info")

    blocked "$pkg"           && flags+=("󰀦  ON YOUR BLOCKLIST — don't build it")
    [[ -z $maint ]]          && flags+=("󰀦  Orphaned: nobody maintains it — anyone can adopt it and change it")
    [[ -n $ood ]]            && flags+=("󰀪  Flagged out of date $(age $((now - ood)))")
    (( now - first < 30 * 86400 )) && flags+=("󰀦  Brand new: first submitted $(age $((now - first)))")
    (( votes < 5 ))          && flags+=("󰀪  Few votes ($votes) — few people have looked at it")
    (( now - mod < 3 * 86400 )) && flags+=("󰋽  Changed $(age $((now - mod))) — read what changed before building")

    pb=$(curl -fsS --max-time 15 "$AUR/cgit/aur.git/plain/PKGBUILD?h=$pkg" 2>/dev/null)
    local tmp; tmp=$(mktemp -d)
    printf '%s\n' "$pb" >"$tmp/PKGBUILD"
    insf=$(sed -n "s/^install=//p" "$tmp/PKGBUILD" | tr -d "\"'" | sed "s/\$pkgname/$pkg/g; s/\${pkgname}/$pkg/g" | head -n1)
    if [[ -n $insf ]]; then
        inst=$(curl -fsS --max-time 15 "$AUR/cgit/aur.git/plain/$insf?h=$pkg" 2>/dev/null)
        printf '%s\n' "$inst" >"$tmp/install"
    fi
    if grep -q "SKIP" "$tmp/PKGBUILD" && grep -E '^\s*source' -A5 "$tmp/PKGBUILD" | grep -qE 'https?://' \
       && ! grep -E '^\s*source' -A5 "$tmp/PKGBUILD" | grep -qE '(git|hg|svn|bzr)\+'; then
        flags+=("󰀪  Some checksums are SKIP for a plain download — that file isn't verified")
    fi
    while IFS= read -r l; do flags+=("󰈔  PKGBUILD · $l"); done < <(suspicious "$tmp/PKGBUILD")
    [[ -s $tmp/install ]] && while IFS= read -r l; do flags+=("󰈔  $insf · $l"); done < <(suspicious "$tmp/install")
    (( ${#flags[@]} )) || flags+=("󰄬  Nothing flagged — still read the PKGBUILD; this is a filter, not a guarantee")

    rows=("${flags[@]}" "󰈙  Read the PKGBUILD"); acts=("${flags[@]/*/noop}" "pkgbuild")
    [[ -s $tmp/install ]] && { rows+=("󰈙  Read the install script ($insf)"); acts+=("install"); }
    rows+=("󰚩  Ask the local AI to review it · $AI_MODEL" "󰖟  Open on aur.archlinux.org" "󰆏  Copy the clone command")
    acts+=("ai" "web" "clone")
    while :; do
        i=$(printf '%s\n' "${rows[@]}" | pick "$name" "$ver · $( [[ -n $maint ]] && echo "maintained by $maint" || echo orphaned) · $votes votes · since $(date -d "@$first" +%F) · updated $(age $((now - mod)))${desc:+ · $desc}") || break
        case ${acts[i]} in
            pkgbuild) in_pager "PKGBUILD · $pkg" "cat '$tmp/PKGBUILD'"; sleep 0.5 ;;
            install)  in_pager "$insf · $pkg" "cat '$tmp/install'"; sleep 0.5 ;;
            web)      xdg-open "$AUR/packages/$pkg" >/dev/null 2>&1 & ;;
            clone)    printf 'git clone %s/%s.git' "$AUR" "$pkg" | wl-copy && notify "Copied: git clone $AUR/$pkg.git" ;;
            ai)       ai_review "$pkg" "$tmp"; sleep 0.5 ;;
            *)        printf '%s' "${rows[i]}" | wl-copy && notify "Copied" ;;
        esac
    done
    # The pagers read from $tmp; give them a moment before it goes.
    ( sleep 600; rm -rf "$tmp" ) >/dev/null 2>&1 &
}

ai_review() {   # PKG DIR
    local prompt="You are reviewing an Arch Linux AUR package for supply-chain attacks. Read the PKGBUILD (and install script, if present) below. List every line that downloads or runs code outside the declared source array, decodes or obfuscates data (base64, eval), writes outside the package directory, enables services, adds startup entries, or sends data off the machine. For each, quote the line and say in one sentence why it matters. If nothing is suspicious, say so in one line. Do not describe what the package does otherwise."
    in_terminal "AI review · $1" "
        started=0
        if ! systemctl is-active -q ollama; then
            echo 'ollama is off — starting it (asks your password):'; sudo systemctl start ollama || exit 1; started=1; sleep 2
        fi
        if ! ollama list 2>/dev/null | grep -q '^${AI_MODEL} '; then
            echo 'Model ${AI_MODEL} is not installed. Pull it first:  ollama pull ${AI_MODEL}'
        else
            echo '── ${AI_MODEL} on $1 · a hint, not a verdict: local models miss shell bugs ──'; echo
            { printf '%s\n\n' \"$prompt\"; echo '--- PKGBUILD ---'; cat '$2/PKGBUILD'; [ -s '$2/install' ] && { echo '--- install script ---'; cat '$2/install'; }; } |
                ollama run '${AI_MODEL}' --think=false
        fi
        [ \$started = 1 ] && { echo; echo 'Stopping ollama again.'; sudo systemctl stop ollama; }"
}

installed() {   # every AUR package installed, in one RPC request
    local pkgs=() q info rows=() p
    mapfile -t pkgs < <(pacman -Qmq 2>/dev/null)
    (( ${#pkgs[@]} )) || { printf '%s\n' "Nothing installed from outside the repos." | list_rows "Installed" "pacman -Qm"; return; }
    q=$(printf '&arg%%5B%%5D=%s' "${pkgs[@]}")
    info=$(curl -fsS --max-time 20 "$AUR/rpc/v5/info?${q#&}" 2>/dev/null) || { notify "Couldn't reach the AUR"; return; }
    for p in "${pkgs[@]}"; do
        if blocked "$p"; then rows+=("󰀦  $p — ON YOUR BLOCKLIST")
        elif ! jq -e --arg p "$p" '.results[] | select(.Name == $p)' <<<"$info" >/dev/null; then rows+=("󰀦  $p — no longer in the AUR (removed or renamed)")
        elif [[ $(jq -r --arg p "$p" '.results[] | select(.Name == $p) | .Maintainer // ""' <<<"$info") == "" ]]; then rows+=("󰀪  $p — orphaned")
        else rows+=("󰄬  $p"); fi
    done
    printf '%s\n' "${rows[@]}" | list_rows "Installed" "${#pkgs[@]} packages from outside the repos"
}

menu() {
    local i clip pkg
    while :; do
        i=$(printf '%s\n' "󰏗  Check a package…" "󰒃  Check what's installed from the AUR · $(pacman -Qmq 2>/dev/null | grep -c .)" "󰈔  Edit the blocklist" |
            pick "AUR check" "Read-only: the AUR's data, the PKGBUILD and your blocklist") || return
        case $i in
            0) clip=$(wl-paste --no-newline 2>/dev/null | head -c 80)
               [[ $clip =~ ^[a-z0-9@._+-]+$ ]] || clip=""
               pkg=$(ask "Package" "AUR package name${clip:+ — filled in from the clipboard}" "$clip") || continue
               pkg=${pkg//[[:space:]]/}
               [[ $pkg =~ ^[a-z0-9@._+-]+$ ]] || { notify "\"$pkg\" isn't a valid package name"; continue; }
               check "$pkg" ;;
            1) installed ;;
            2) seed_blocklist; setsid -f kitty --title "AUR blocklist" nano "$BLOCKLIST" >/dev/null 2>&1; exit 0 ;;
        esac
    done
}

case ${1:-} in
    --status) status ;;
    *)        toggle_rofi; menu ;;
esac
