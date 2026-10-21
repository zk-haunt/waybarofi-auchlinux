#!/usr/bin/env bash
# Security menu — the log viewer and popups behind the security pill in the
# "auchsec" Waybar layout (config/waybar/themes/config_auchsec.jsonc).
#
#   security-menu.sh [logs]                  log viewer (rofi)
#   security-menu.sh firewall | apparmor     that popup
#   security-menu.sh --status logs|firewall|apparmor
#                                            one JSON line for the Waybar module
#
# Everything runs as you and reads only what needs no password: the journal,
# /etc/ufw, /proc and /sys. Root-only views — the audit log, AppArmor's loaded
# rules, ufw's live rules — open in a terminal that asks for sudo there.

# -u and pipefail, but NOT -e — same reasoning as clipboard-menu.sh: this is
# bound to clicks, and `set -e` turns a cosmetic failure into a dead button.
set -uo pipefail

theme="$HOME/.config/rofi/logviewer/style.rasi"

# Error lines that show up on every boot of this laptop and mean nothing
# (checked over four boots, 2026-10-09): the firmware's ACPI bugs, the kernel
# noting this AMD CPU has no Intel TDX, gnome-keyring's PAM hook under SDDM,
# the Wi-Fi driver's multicast notice, and the watchdog line every shutdown
# leaves. Plus the two lines a sudo password prompt logs when it's closed
# unanswered (2026-10-10: two update terminals closed at the prompt read as "4
# new errors") — a wrong password logs "authentication failure" instead, which
# the failed sign-ins count. The log viewer still lists them; they just don't
# count toward the number on the bar. Extended regex — add to it as needed.
NOISE='ACPI (BIOS )?Error|virt/tdx: TDX not supported|gkr-pam: unable to locate daemon control file|multicast RX registrations are not supported|watchdog did not stop|pam_unix\(sudo:auth\): (conversation failed|auth could not identify password)'

# Keys of the watches in config/etc/audit/rules.d/50-auchlinux.rules.
AUDIT_KEYS=(identity sudoers preload systemd-units pacman-hooks modules)

# ── helpers ─────────────────────────────────────────────────────────────────
j()      { journalctl -q --no-pager "$@" 2>/dev/null; }
# "Oct 09 20:02:39 gf kernel: msg" -> "Oct 09 20:02:39  kernel: msg"
tidy()   { sed -E '/^-- /d; s/^([A-Z][a-z]{2} +[0-9]+ [0-9:]{8}) [^ ]+ /\1  /'; }
esc()    { sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'; }   # Pango
notify() { notify-send -a "Security" -u low -t 1500 "󰒃  Security" "$1"; }
# "summary" is extra — Waybar ignores it; sec-picker.sh shows it in its rows.
emit()   { jq -cn --arg text "$1" --arg class "$2" --arg tooltip "$3" --arg summary "${4:-}" \
               '{text: $text, class: $class, alt: $class, tooltip: $tooltip, summary: $summary}'; }

# pick PROMPT MESSAGE — rows on stdin; prints the index of the chosen row, or
# nothing (and fails) on Esc. Opened from sec-picker.sh, SEC_MENU_POS holds a
# -theme-str that anchors every menu under the bar button, like the dropdown.
# One click picks, like the dropdown (rofi's default wants a double click).
pick() { rofi -dmenu -i -no-custom -format i -p "$1" -mesg "$2" -theme "$theme" -me-select-entry '' -me-accept-entry MousePrimary ${SEC_MENU_POS:+-theme-str "$SEC_MENU_POS"}; }

# in_terminal TITLE COMMAND — run COMMAND (bash) in a new kitty, close the menu.
# Output goes through `less` without -F, so a short result doesn't flash shut.
# Anything needing root runs `sudo -v` first, so the password prompt doesn't
# fight `less` for the terminal.
in_terminal() {
    setsid -f kitty --title "$1" bash -c "$2" >/dev/null 2>&1
    exit 0
}

# ── data ────────────────────────────────────────────────────────────────────
count_errors() {   # BOOT-OFFSET -> "NEW NOISE"
    local lines all new
    lines=$(j -b "${1:-0}" -p err -o cat)
    [[ -z $lines ]] && { echo "0 0"; return; }
    all=$(printf '%s\n' "$lines" | wc -l)
    new=$(printf '%s\n' "$lines" | grep -cvE "$NOISE")
    echo "$new $((all - new))"
}

failed_units() {
    systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}'
    systemctl --user --failed --no-legend --plain 2>/dev/null | awk '{print $1 " (user)"}'
}

# pam_unix logs one "authentication failure" per wrong password — sudo, the
# lock screen, SDDM. Facility 10 (authpriv) first, so the journal can use its
# index instead of grepping a week of everything.
auth_failures() { j SYSLOG_FACILITY=10 --since -7d -g 'authentication failure' "$@"; }

ufw_on() { grep -qx 'ENABLED=yes' /etc/ufw/ufw.conf 2>/dev/null && systemctl is-active -q ufw; }
ufw_policy() { sed -n 's/^DEFAULT_INPUT_POLICY="\(.*\)"/\1/p' /etc/default/ufw 2>/dev/null; }
# "53317/tcp" per allow rule — from ufw's own rule files, which are world-readable.
ufw_allowed() {
    sed -nE 's#^\#\#\# tuple \#\#\# (allow|limit) (tcp|udp|any) ([^ ]+) .* in(_[^ ]+)?$#\3/\2#p' \
        /etc/ufw/user.rules /etc/ufw/user6.rules 2>/dev/null | sort -u
}

# "PROTO ADDRESS:PORT PROCESS" for every socket reachable from the network,
# i.e. not bound to loopback. The process name shows for your own programs only.
listeners() {
    ss -tulnpH 2>/dev/null | awk '{
        addr = $5
        if (addr ~ /^(127\.|\[::1\]|\[::ffff:127\.)/ || addr ~ /%lo:/) next
        proc = "-"
        if (match($0, /users:\(\("[^"]+"/)) proc = substr($0, RSTART + 9, RLENGTH - 10)
        print $1, addr, proc
    }' | sort -u
}

# open_port PROTO PORT — 0 if a ufw allow rule lets it in from the network.
open_port() {
    local rule
    while IFS= read -r rule; do
        [[ $rule == "$2/$1" || $rule == "$2/any" || $rule == "any/any" || $rule == "any/$1" ]] && return 0
    done < <(ufw_allowed)
    return 1
}

aa_on()       { [[ $(cat /sys/module/apparmor/parameters/enabled 2>/dev/null) == Y ]]; }
aa_loaded()   { systemctl is-active -q apparmor; }
# The live mode (/sys/module/apparmor/parameters/mode) is root-only, so this
# reads what the boot line set. A later `printf complain | sudo tee …` isn't seen.
aa_bootmode() { grep -qw 'apparmor.mode=complain' /proc/cmdline && echo complain || echo enforce; }
aa_programs() {   # "LABEL  COMMAND  (pid N)" for every process a rule is attached to
    local pid label
    while read -r pid label; do
        [[ $label == unconfined ]] && continue
        printf '%s  %s  (pid %s)\n' "$label" "$(cat "/proc/$pid/comm" 2>/dev/null)" "$pid"
    done < <(ps -eo pid=,label=)
}

# ── Waybar status ───────────────────────────────────────────────────────────
status_logs() {
    local new noise failed=() fails latest tip text cls summary
    read -r new noise < <(count_errors 0)
    mapfile -t failed < <(failed_units)
    fails=$(auth_failures -o cat | wc -l)
    latest=$(j -b -p err -r -n 200 -o short | tidy | grep -vE "$NOISE" | head -n 5 | cut -c1-90 | esc)

    text="󰺮"; cls=ok
    (( new )) && { text="󱪗 $new"; cls=warning; }
    (( ${#failed[@]} )) && { [[ $text == "󰺮" ]] && text="󱪗"; cls=critical; }

    tip="<b>Logs · this boot</b>
Errors: $new new, $noise known noise
Failed services: $( (( ${#failed[@]} )) && printf '%s ' "${failed[@]}" || echo none)
Failed sign-ins, last 7 days: $fails"
    [[ -n $latest ]] && tip+="

<b>Latest errors</b>
$latest"
    tip+="

<i>Click: log viewer · Right-click: errors in a terminal</i>"
    if (( ${#failed[@]} )); then summary="${#failed[@]} failed service$( (( ${#failed[@]} > 1 )) && echo s)"
    elif (( new )); then summary="$new new error$( (( new > 1 )) && echo s) this boot"
    else summary="nothing new this boot"; fi
    emit "$text" "$cls" "$tip" "$summary"
}

status_firewall() {
    local allowed lst=() l proto addr proc n_open=0 tip
    allowed=$(ufw_allowed | paste -sd, - | sed 's/,/, /g')
    mapfile -t lst < <(listeners)
    for l in "${lst[@]}"; do
        read -r proto addr proc <<<"$l"
        open_port "$proto" "${addr##*:}" && n_open=$((n_open + 1))
    done
    if ufw_on; then
        tip="<b>Firewall · on</b> (ufw)
Incoming: blocked unless allowed ($(ufw_policy))
Allowed in: ${allowed:-nothing}
Listening on the network: ${#lst[@]}, open through the firewall: $n_open

<i>Click: ports and connections</i>"
        emit "󱨑" ok "$tip" "on · $( (( n_open )) && echo "$n_open open to the network" || echo "nothing open to the network")"
    else
        tip="<b>Firewall · OFF</b>
ufw isn't enabled — everything listening is reachable.
Turn it back on: sudo ufw enable

<i>Click: ports and connections</i>"
        emit "󰦞" critical "$tip" "OFF — everything listening is reachable"
    fi
}

status_apparmor() {
    local n mode tip
    n=$(ps -eo label= | grep -cE '\((enforce|complain|kill)\)$')
    if ! aa_on; then
        emit "󰦞" off "<b>AppArmor · off</b>
Not switched on in this boot. The \"AppArmor test\" boot entry turns it on —
make it the default in /boot/loader/loader.conf (manual.md §4) so every boot does.

<i>Click: details</i>" "off this boot"
        return
    fi
    if ! aa_loaded; then
        emit "󰞀" idle "<b>AppArmor · on, no rules loaded</b>
apparmor.service isn't running, so nothing is checked.

<i>Click: details</i>" "on, no rules loaded"
        return
    fi
    mode=$(aa_bootmode)
    if [[ $mode == complain ]]; then
        tip="<b>AppArmor · log-only</b> (complain)
Rules are loaded and log what they would block; nothing is blocked."
        emit "󰞀" complain "$tip
Programs under a blocking/logging rule now: $n
<small>Mode as set at boot.</small>

<i>Click: details</i>" "log-only — rules log, nothing is blocked"
    else
        tip="<b>AppArmor · enforcing</b>
Rules are loaded and block what they don't allow."
        emit "󰕥" enforce "$tip
Programs under a blocking/logging rule now: $n
<small>Mode as set at boot — a later switch via /sys isn't visible here.</small>

<i>Click: details</i>" "enforcing"
    fi
}

# ── views ───────────────────────────────────────────────────────────────────
# detail LINE — the full entry, with Copy.
detail() {
    local i
    i=$(printf '%s\n' "󰆏  Copy" "󰁍  Back" | pick "Entry" "$(printf '%s' "$1" | esc)") || return
    [[ $i == 0 ]] && { printf '%s' "$1" | wl-copy; notify "Copied to the clipboard"; }
}

# show_rows TITLE TERMINAL-COMMAND — rows on stdin, newest first. Feed it with
# `< <(…)`, never a pipe: a pipe runs it in a subshell, where in_terminal's
# `exit` only ends the subshell and the menu pops back up.
show_rows() {
    local title=$1 tcmd=$2 rows=() i
    mapfile -t rows
    while :; do
        i=$( { printf '%s\n' "󰏌  Open the full log in a terminal" "󰁍  Back"
               if (( ${#rows[@]} )); then printf '%s\n' "${rows[@]}"; fi; } |
             pick "$title" "${#rows[@]} entries, newest first — pick one to read it whole") || return
        case $i in
            0) in_terminal "$title" "$tcmd" ;;
            1) return ;;
            *) detail "${rows[i-2]}" ;;
        esac
    done
}

view_journal() {   # TITLE JOURNALCTL-ARGS...
    local title=$1; shift
    show_rows "$title" "journalctl $(printf '%q ' "$@")--no-pager -o short | less -R +G" \
        < <(j "$@" -r -n 500 -o short | tidy)
}

view_failed() {
    local rows=() i unit cmd
    mapfile -t rows < <(failed_units)
    i=$( { printf '%s\n' "󰁍  Back"; if (( ${#rows[@]} )); then printf '%s\n' "${rows[@]}"; fi; } |
         pick "Failed services" "${#rows[@]} failed — pick one to open its status and log") || return
    (( i == 0 )) && return
    unit=${rows[i-1]}
    if [[ $unit == *" (user)" ]]; then
        unit=${unit% (user)}
        cmd="{ systemctl --user status $(printf %q "$unit") --no-pager -l; echo; journalctl --user -b -u $(printf %q "$unit") --no-pager; } 2>&1 | less -R"
    else
        cmd="{ systemctl status $(printf %q "$unit") --no-pager -l; echo; journalctl -b -u $(printf %q "$unit") --no-pager; } 2>&1 | less -R"
    fi
    in_terminal "$unit" "$cmd"
}

view_signins() {
    show_rows "Sign-ins" "last -F | less -R" \
        < <(last -n 50 2>/dev/null | sed '/^$/d; /^wtmp begins/d')
}

menu_audit() {
    local i rows=("󰁍  Back" "󰦝  Summary: events per watch")
    local k; for k in "${AUDIT_KEYS[@]}"; do rows+=("󰈈  $k"); done
    i=$(printf '%s\n' "${rows[@]}" |
        pick "Audit" "Changes to the files auditd watches. Opens a terminal — asks for your password.") || return
    case $i in
        0) return ;;
        1) in_terminal "Audit summary" "sudo -v && sudo aureport --key --summary -i 2>&1 | less -R" ;;
        *) k=${AUDIT_KEYS[i-2]}
           in_terminal "Audit: $k" "sudo -v && sudo ausearch -i -k $k 2>&1 | less -R +G" ;;
    esac
}

menu_apparmor() {
    local i state n mesg
    n=$(aa_programs | grep -cE '\((enforce|complain|kill)\)')
    if ! aa_on; then state="off in this boot"
    elif ! aa_loaded; then state="on, no rules loaded"
    else state="on, rules loaded · mode at boot: $(aa_bootmode)"; fi
    mesg="AppArmor: $state"
    while :; do
        i=$(printf '%s\n' "󰁍  Back" \
                "󰈈  Programs a rule is attached to · $n blocking/logging" \
                "󰒘  Events: would-block (ALLOWED) and blocked (DENIED) · asks password" \
                "󰦝  Loaded rules (aa-status) · asks password" |
            pick "AppArmor" "$mesg") || return
        case $i in
            0) return ;;
            1) show_rows "AppArmor programs" "ps -eo pid,label,comm | grep -v ' unconfined ' | less -R" \
                   < <(aa_programs | sort) ;;
            2) in_terminal "AppArmor events" \
                 'sudo -v && { sudo ausearch -m AVC -i 2>/dev/null | grep -E "apparmor=\"?(DENIED|ALLOWED)" || echo "No AppArmor events — nothing would have been blocked."; } | less -R +G' ;;
            3) in_terminal "AppArmor rules" "sudo -v && sudo aa-status 2>&1 | less -R" ;;
        esac
    done
}

menu_firewall() {
    local i rows=() lst=() l proto addr proc where mesg conns
    mapfile -t lst < <(listeners)
    for l in "${lst[@]}"; do
        read -r proto addr proc <<<"$l"
        if open_port "$proto" "${addr##*:}"; then where="OPEN to the network"; else where="blocked by the firewall"; fi
        rows+=("$(printf '%-4s %-22s %-16s %s' "$proto" "$addr" "$proc" "$where")")
    done
    conns=$(ss -tunH state established 2>/dev/null | grep -cvE '(127\.0\.0\.|\[::1\])')
    if ufw_on; then mesg="Firewall on · incoming $(ufw_policy) unless allowed · allowed in: $(ufw_allowed | paste -sd' ' -)"
    else mesg="<b>Firewall OFF</b> — everything listening below is reachable"; fi
    while :; do
        i=$( { printf '%s\n' "󰁍  Back" "󰌘  Active connections · $conns" "󰏌  Full ufw status · asks password"
               if (( ${#rows[@]} )); then printf '%s\n' "${rows[@]}"; fi; } |
             pick "Firewall" "$mesg") || return
        case $i in
            0) return ;;
            1) show_rows "Connections" "ss -tunp state established | less -R" \
                   < <(ss -tunpH state established 2>/dev/null | grep -vE '(127\.0\.0\.|\[::1\])' |
                       awk '{ proc = "-"; if (match($0, /users:\(\("[^"]+"/)) proc = substr($0, RSTART + 9, RLENGTH - 10)
                              printf "%-4s %-26s → %-26s %s\n", $1, $4, $5, proc }') ;;
            2) in_terminal "ufw status" "sudo -v && sudo ufw status verbose 2>&1 | less -R" ;;
            *) detail "${rows[i-3]}" ;;
        esac
    done
}

menu_logs() {
    local i new noise pnew pnoise nfailed nkern nfails
    while :; do
        read -r new noise < <(count_errors 0)
        read -r pnew pnoise < <(count_errors -1)
        nfailed=$(failed_units | wc -l)
        nkern=$(j -b -k -p warning -o cat | wc -l)
        nfails=$(auth_failures -o cat | wc -l)
        i=$(printf '%s\n' \
                "󰀨  Errors this boot · $new new, $noise known noise" \
                "󰅙  Failed services · $nfailed" \
                "󰘚  Kernel warnings this boot · $nkern" \
                "󰋚  Errors in the previous boot · $pnew new, $pnoise known noise" \
                "󰍂  Sign-ins" \
                "󰣮  Failed sign-ins, last 7 days · $nfails" \
                "󰒘  AppArmor ›" \
                "󰦝  Audit: watched files ›" \
                "󱨑  Firewall and open ports ›" |
            pick "Logs" "Read-only. Entries needing a password open in a terminal.") || return
        case $i in
            0) view_journal "Errors this boot" -b -p err ;;
            1) view_failed ;;
            2) view_journal "Kernel warnings" -b -k -p warning ;;
            3) view_journal "Errors, previous boot" -b -1 -p err ;;
            4) view_signins ;;
            5) view_journal "Failed sign-ins" SYSLOG_FACILITY=10 --since -7d -g "authentication failure" ;;
            6) menu_apparmor ;;
            7) menu_audit ;;
            8) menu_firewall ;;
        esac
    done
}

# ── main ────────────────────────────────────────────────────────────────────
if [[ ${1:-} == --status ]]; then
    case ${2:-} in
        logs)     status_logs ;;
        firewall) status_firewall ;;
        apparmor) status_apparmor ;;
        *) echo "usage: ${0##*/} --status logs|firewall|apparmor" >&2; exit 2 ;;
    esac
    exit 0
fi

# A second click on the bar closes the menu instead of stacking another.
if pgrep -u "$USER" -x rofi >/dev/null; then
    pkill -u "$USER" -x rofi
    exit 0
fi

case ${1:-logs} in
    logs)     menu_logs ;;
    firewall) menu_firewall ;;
    apparmor) menu_apparmor ;;
    -h|--help) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//' ;;
    *) echo "usage: ${0##*/} [logs|firewall|apparmor] | --status logs|firewall|apparmor" >&2; exit 2 ;;
esac
