#!/usr/bin/env bash
# Network — a row in the hub dropdown (sec-picker.sh): the connection, address,
# VPN, speed, and whether DNS is encrypted and which server answers.
#
#   net-menu.sh            the menu
#   net-menu.sh --status   one JSON line for the hub row
#
# --status makes no network requests: it reads NetworkManager's last known
# connectivity, resolved's state and the interface counters. Speed is the
# average since the previous status call (cached sample).

# -u and pipefail, but NOT -e — bound to clicks; see clipboard-menu.sh.
set -uo pipefail
MENU_APP="Network"; MENU_ICON="󰖩"
source "${BASH_SOURCE[0]%/*}/menu-lib.sh"

C="$AUCH_CACHE/net"; mkdir -p "$C"

dev()  { ip route show default 2>/dev/null | awk '{ for (i = 1; i < NF; i++) if ($i == "dev") { print $(i + 1); exit } }'; }
gw()   { ip route show default 2>/dev/null | awk '{ print $3; exit }'; }
addr() { ip -4 -o addr show dev "$1" 2>/dev/null | awk '{ print $4; exit }'; }
conn() { nmcli -t -f NAME,TYPE,DEVICE connection show --active 2>/dev/null | awk -F: -v d="$1" '$3 == d { print $1 ":" $2; exit }'; }
signal() { nmcli -t -f IN-USE,SIGNAL dev wifi list --rescan no 2>/dev/null | awk -F: '$1 == "*" { print $2; exit }'; }
connectivity() { nmcli -t networking connectivity 2>/dev/null; }   # last known; no request
vpns() { ip -o link show type wireguard up 2>/dev/null | awk -F': ' '{ print $2 }' | paste -sd' ' -; }

dot_on() { resolvectl status 2>/dev/null | awk '/^Global/,/^Link/' | grep -q '+DNSOverTLS'; }
dns_server() { resolvectl status 2>/dev/null | awk '/^Global/,/^Link/' | sed -n 's/^ *Current DNS Server: *//p' | head -n1; }
provider() {
    case ${1%%#*} in
        9.9.9.9|149.112.112.112)         echo Quad9 ;;
        1.1.1.1|1.0.0.1)                 echo Cloudflare ;;
        45.90.28.*|45.90.30.*)           echo NextDNS ;;
        8.8.8.8|8.8.4.4)                 echo Google ;;
        "")                              echo "none" ;;
        *)                               echo "${1%%#*}" ;;
    esac
}

rate() { numfmt --to=iec --suffix=B/s "${1:-0}"; }
# Bytes/s since the previous call, per direction: "RX TX" (0 0 on the first).
speed() {
    local d=$1 now rx tx prev_t prev_rx prev_tx dt
    now=$(date +%s)
    rx=$(<"/sys/class/net/$d/statistics/rx_bytes") tx=$(<"/sys/class/net/$d/statistics/tx_bytes")
    if read -r prev_t prev_rx prev_tx 2>/dev/null <"$C/sample.$d" && (( now > prev_t )); then
        dt=$(( now - prev_t ))
        echo "$(( (rx - prev_rx) / dt )) $(( (tx - prev_tx) / dt ))"
    else
        echo "0 0"
    fi
    echo "$now $rx $tx" >"$C/sample.$d"
}

# The firewall is part of this row — its view is security-menu.sh's — so its
# state is the network's too: off turns the row red, which the shield counts.
firewall_state() {   # -> "CLASS<US>SUMMARY" from security-menu.sh
    "${BASH_SOURCE[0]%/*}/security-menu.sh" --status firewall 2>/dev/null |
        jq -r '[.class // "", .summary // ""] | join("\u001f")'
}

status() {
    local d c name type sig ip cty dns prov vpn rx tx cls summary fwcls fwsum fw
    d=$(dev)
    cty=$(connectivity)
    if [[ -z $d ]]; then
        emit "󰖪" critical "<b>Network · offline</b>
No default route — not connected." "offline"
        return
    fi
    c=$(conn "$d"); name=${c%%:*}; type=${c#*:}
    sig=""; [[ $type == *wireless* ]] && sig=$(signal)
    ip=$(addr "$d"); dns=$(dns_server); prov=$(provider "$dns"); vpn=$(vpns)
    read -r rx tx < <(speed "$d")

    IFS=$'\x1f' read -r fwcls fwsum < <(firewall_state)

    cls=ok
    [[ $cty == limited || $cty == portal ]] && cls=warning
    dot_on || cls=warning
    case $fwcls in
        critical) fw="FIREWALL OFF" ;;
        "")       fw="firewall unknown" ;;
        *)        fw="firewall on" ;;
    esac
    [[ $cty == none || $fwcls == critical ]] && cls=critical
    summary="${name:-$d}${sig:+ ($sig%)} · $fw · DNS $(dot_on && echo encrypted || echo "NOT encrypted") ($prov)${vpn:+ · VPN} · ${ip%/*}"
    emit "󰖩" "$cls" "<b>Network · ${cty:-unknown}</b>
${name:-$d} on $d${sig:+, signal $sig%}
Firewall: ${fwsum:-unknown}
Address: ${ip:-none} · gateway $(gw)
DNS: $(dot_on && echo "encrypted (DNS over TLS)" || echo "NOT encrypted") · $prov ${dns%%#*}
VPN: ${vpn:-none}
Speed: ↓ $(rate "$rx") ↑ $(rate "$tx") (average since last check)" "$summary"
}

menu() {
    local i d c name type sig ip dns rx1 tx1 rx2 tx2 rx tx pub fwcls fwsum
    while :; do
        IFS=$'\x1f' read -r fwcls fwsum < <(firewall_state)
        d=$(dev)
        if [[ -n $d ]]; then
            c=$(conn "$d"); name=${c%%:*}; type=${c#*:}
            sig=""; [[ $type == *wireless* ]] && sig=$(signal)
            ip=$(addr "$d"); dns=$(dns_server)
            # A one-second sample for the menu, not the status cache.
            rx1=$(<"/sys/class/net/$d/statistics/rx_bytes"); tx1=$(<"/sys/class/net/$d/statistics/tx_bytes")
            sleep 1
            rx2=$(<"/sys/class/net/$d/statistics/rx_bytes"); tx2=$(<"/sys/class/net/$d/statistics/tx_bytes")
            rx=$((rx2 - rx1)); tx=$((tx2 - tx1))
        fi
        i=$(printf '%s\n' \
                "󰖩  Connection: ${name:-none}${type:+ · ${type/802-11-wireless/Wi-Fi}}${sig:+ · signal $sig%}" \
                "󰩟  Address: ${ip:-none} · gateway $(gw)" \
                "󰒃  DNS: $(dot_on && echo "encrypted (DNS over TLS)" || echo "NOT encrypted") · $(provider "$dns") ${dns%%#*}" \
                "󰦝  VPN: $(vpns | sed 's/^$/none/')" \
                "󰓅  Speed now: ↓ $(rate "${rx:-0}") ↑ $(rate "${tx:-0}")" \
                "󰇧  Show my public IP · asks api.ipify.org" \
                "󰑐  Check connectivity now" \
                "$( [[ $fwcls == critical ]] && echo "󰦞  Firewall · OFF" || echo "󱨑  Firewall · ${fwsum:-unknown}") · ports and connections ›" \
                "󰜉  Restart networking" |
            pick "Network" "NetworkManager: $(connectivity) · a pick on the first five copies it") || return
        case $i in
            0|1|2|3|4) printf '%s' "$(sed -n "$((i + 1))p" < <(printf '%s\n' \
                            "${name:-none} ${type:-}" "${ip:-none} gw $(gw)" "${dns:-none}" "$(vpns)" "↓ $(rate "${rx:-0}") ↑ $(rate "${tx:-0}")"))" |
                           wl-copy && notify "Copied" ;;
            5) pub=$(curl -fsS --max-time 8 https://api.ipify.org 2>/dev/null)
               if [[ -n $pub ]]; then printf '%s' "$pub" | wl-copy; notify "Public IP: $pub (copied)"
               else notify "Couldn't reach api.ipify.org"; fi ;;
            6) notify "NetworkManager says: $(nmcli networking connectivity check 2>/dev/null || echo unknown)" ;;
            7) exec "${BASH_SOURCE[0]%/*}/security-menu.sh" firewall ;;
            8) confirm "Restart networking? Wi-Fi and the VPN drop for a few seconds — audio and video streams will stall." &&
                   { nmcli networking off && sleep 1 && nmcli networking on && notify "Networking restarted"; } ;;
        esac
    done
}

case ${1:-} in
    --status) status ;;
    *)        toggle_rofi; menu ;;
esac
