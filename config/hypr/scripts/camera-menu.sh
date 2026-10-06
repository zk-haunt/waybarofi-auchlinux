#!/usr/bin/env bash
# Rofi camera menu (Super+Alt+C): physical webcam + phone-as-webcam actions.

# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

theme="$HOME/.config/rofi/launcher/style.rasi"
S="$HOME/.config/hypr/scripts"

opt=$(printf '%s\n' \
    "󰄀  Webcam preview" \
    "󰄄  Webcam snapshot" \
    "󰢑  Webcam settings" \
    "󰄀  Phone camera (USB)" \
    "󰄀  Phone camera (Wi-Fi)" \
    "󰜺  Stop phone camera" \
    | rofi -dmenu -i -no-custom -p "Camera" -theme "$theme")

case "$opt" in
    *"Webcam preview")    setsid "$S/webcam.sh" view >/dev/null 2>&1 & ;;
    *"Webcam snapshot")   "$S/webcam.sh" snap ;;
    *"Webcam settings")   setsid "$S/webcam.sh" gui >/dev/null 2>&1 & ;;
    *"Phone camera (USB)")
        # scrcpy opens its own preview window; just run it detached.
        setsid "$S/phone-camera.sh" usb >/dev/null 2>&1 & ;;
    *"Phone camera (Wi-Fi)")
        ip=$(rofi -dmenu -p "Phone IP[:port]" -theme "$theme" -mesg "From the IP Webcam app, e.g. 192.168.1.42:8080" </dev/null)
        [ -n "$ip" ] && setsid kitty --title PhoneCam -e "$S/phone-camera.sh" start "$ip" >/dev/null 2>&1 &
        ;;
    *"Stop phone"*)       "$S/phone-camera.sh" stop ;;
esac
