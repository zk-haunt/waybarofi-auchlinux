#!/usr/bin/env bash
# Waybar VPN module: status + click-toggle for WireGuard profiles managed by
# NetworkManager. Import a provider config once with:
#   nmcli connection import type wireguard file <config.conf>
# The module stays hidden until at least one wireguard profile exists.


# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

first_wg() { nmcli -t -f NAME,TYPE connection show | awk -F: '$2=="wireguard"{print $1; exit}'; }
active_wg() { nmcli -t -f NAME,TYPE connection show --active | awk -F: '$2=="wireguard"{print $1; exit}'; }

if [[ ${1:-} == "toggle" ]]; then
    # Capture stderr and the exit status instead of discarding both. nmcli
    # reports real, actionable failures here ("Failed to create WireGuard
    # interface ... Operation not supported" when the running kernel's module
    # tree is stale after an upgrade, auth failures, a dead endpoint), and
    # swallowing them meant a click on the bar did nothing at all with no hint
    # why. Always refresh waybar, but say so when the action failed.
    active="$(active_wg)"
    rc=0
    if [[ -n $active ]]; then
        err="$(nmcli connection down "$active" 2>&1 >/dev/null)" || rc=$?
        verb="disconnect from"
        target="$active"
    else
        target="$(first_wg)"
        if [[ -z $target ]]; then
            notify-send -u low "VPN" "No WireGuard profile found.\nImport one: nmcli connection import type wireguard file <config.conf>"
            exit 0
        fi
        err="$(nmcli connection up "$target" 2>&1 >/dev/null)" || rc=$?
        verb="connect to"
    fi

    pkill -RTMIN+10 waybar

    if (( rc != 0 )); then
        notify-send -u critical "VPN: failed to ${verb} ${target}" "${err:-nmcli exited $rc}"
        exit "$rc"
    fi
    exit 0
fi

# Icons are nf-md-* (Material Design), matching the other waybar modules, and
# written as \U escapes so they survive an editor without the font. Both states
# previously had a bare space here, so the pill rendered blank either way and
# there was no way to tell connected from disconnected.
ICON_ON=$'\U000F0582'    # nf-md-vpn
ICON_OFF=$'\U000F099C'   # nf-md-shield-off-outline

active="$(active_wg)"
if [[ -n $active ]]; then
    printf '{"text":"%s","class":"connected","tooltip":"VPN connected: %s\\nClick to disconnect"}\n' "$ICON_ON" "$active"
elif [[ -n "$(first_wg)" ]]; then
    printf '{"text":"%s","class":"disconnected","tooltip":"VPN off (%s)\\nClick to connect"}\n' "$ICON_OFF" "$(first_wg)"
else
    printf '{"text":""}\n'
fi
