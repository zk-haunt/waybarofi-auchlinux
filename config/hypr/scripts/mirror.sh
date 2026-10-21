#!/usr/bin/env bash
# Android screen mirroring + control via scrcpy (USB or Wi-Fi), audio included.
# scrcpy 2.0+ forwards audio natively on Android 11+; older phones can use sndcpy.
#
#   mirror.sh                 — mirror the connected phone (ANDROID_SERIAL picks one)
#   mirror.sh switch          — USB → Wi-Fi: scrcpy turns on adb's TCP mode on the
#                               phone, reconnects over it and mirrors; unplug after
#   mirror.sh wifi <ip[:port]>— mirror a phone already listening on Wi-Fi (port 5555
#                               after a switch, or Android 11+ wireless debugging)
#   mirror.sh audio           — forward phone audio only, no screen (sndcpy)
#   mirror.sh stop            — close mirror + drop wireless adb connection
#
# Tips: enable "USB debugging" in Developer options. For Wi-Fi the phone must be
# on the same network, and listening: either `switch` once over USB (lasts until
# the phone restarts), or Android 11+ Wireless debugging, paired once — the
# phone menu (phone-menu.sh) walks through both.
set -uo pipefail

have(){ command -v "$1" &>/dev/null; }
notify(){ notify-send -a "Phone Mirror" "$@"; }

ensure_adb() {
    have adb || { notify -u critical "android-tools (adb) not installed — run install-packages.sh"; exit 1; }
    adb start-server >/dev/null 2>&1
}

# Common scrcpy flags: keep the phone awake, and title the window — the phone
# menu finds it by that, and hyprland.lua floats "Phone" at phone size while
# "Phone · tiled" matches no rule and tiles. Which one comes from the phone
# menu (its Tile/Float row, or how the window was when mirroring stopped).
# The phone's own screen stays on — MIRROR_SCREEN_OFF=1 turns it off while
# mirroring to save battery; Alt+Shift+O in the window turns it back on.
title="Phone"
[[ $(cat "${XDG_CACHE_HOME:-$HOME/.cache}/auch/phone/mirror-layout" 2>/dev/null) == tile ]] && title="Phone · tiled"
SCRCPY_OPTS=(--stay-awake --window-title="$title")
[[ ${MIRROR_SCREEN_OFF:-} == 1 ]] && SCRCPY_OPTS+=(--turn-screen-off)

case "${1:-}" in
    ""|usb)
        have scrcpy || { notify -u critical "scrcpy not installed — run install-packages.sh"; exit 1; }
        ensure_adb
        case "$(adb get-state 2>/dev/null)" in
            device) : ;;
            unauthorized) notify -u critical "Unauthorized — accept the USB-debugging prompt on the phone."; exit 1 ;;
            *) notify -u critical "No phone over USB. Plug in + enable USB debugging."; exit 1 ;;
        esac
        notify "Mirroring the phone"
        exec scrcpy "${SCRCPY_OPTS[@]}"
        ;;
    switch)
        have scrcpy || { notify -u critical "scrcpy not installed"; exit 1; }
        ensure_adb
        notify "Switching to Wi-Fi…"
        exec scrcpy --select-usb --tcpip "${SCRCPY_OPTS[@]}"
        ;;
    wifi)
        ip="${2:-}"; [ -z "$ip" ] && { echo "usage: mirror.sh wifi <ip[:port]>"; exit 1; }
        [[ "$ip" == *:* ]] || ip="$ip:5555"
        have scrcpy || { notify -u critical "scrcpy not installed"; exit 1; }
        ensure_adb
        notify "Connecting to $ip…"
        adb connect "$ip" >/dev/null 2>&1
        exec scrcpy --tcpip="$ip" "${SCRCPY_OPTS[@]}"
        ;;
    audio)
        have sndcpy || { notify -u critical "Install 'sndcpy' from the AUR (or use plain mirror for Android 11+ audio)"; exit 1; }
        ensure_adb
        notify "Forwarding phone audio"
        exec sndcpy
        ;;
    stop)
        pkill -x scrcpy 2>/dev/null
        pkill -x sndcpy 2>/dev/null
        have adb && adb disconnect >/dev/null 2>&1
        notify "Stopped"
        ;;
    *)
        echo "usage: mirror.sh [usb] | switch | wifi <ip[:port]> | audio | stop"
        ;;
esac
