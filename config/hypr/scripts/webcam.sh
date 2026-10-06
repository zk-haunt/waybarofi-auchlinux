#!/usr/bin/env bash
# Physical webcam helper. Default device /dev/video0 (override with WEBCAM_DEV).
#   webcam.sh list   — list capture devices (v4l2-ctl)
#   webcam.sh view   — live preview (mpv, low latency)
#   webcam.sh gui    — guvcview control panel (exposure/brightness/etc.)
#   webcam.sh snap   — save a single frame to ~/Pictures

# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

dev="${WEBCAM_DEV:-/dev/video0}"

have(){ command -v "$1" &>/dev/null; }

case "${1:-view}" in
    list)
        v4l2-ctl --list-devices
        ;;
    view)
        have mpv || { notify-send -u critical "Webcam" "mpv not installed"; exit 1; }
        exec mpv --profile=low-latency --untimed --no-cache --title="Webcam" "av://v4l2:$dev"
        ;;
    gui)
        # Prefer guvcview; fall back to qv4l2 (Qt) if it isn't installed.
        if have guvcview; then
            exec guvcview -d "$dev"
        elif have qv4l2; then
            exec qv4l2 -d "$dev"
        else
            notify-send -u critical "Webcam" "No control GUI (install guvcview or qv4l2)"; exit 1
        fi
        ;;
    snap)
        out="$HOME/Pictures/webcam_$(date +%y%m%d_%H%M%S).jpg"
        if ffmpeg -hide_banner -loglevel error -y -f v4l2 -i "$dev" -frames:v 1 "$out"; then
            notify-send -i "$out" "Webcam" "Snapshot saved to $out"
        else
            notify-send -u critical "Webcam" "Snapshot failed (is the camera in use?)"
        fi
        ;;
    *)
        echo "usage: webcam.sh [list|view|gui|snap]"; exit 1
        ;;
esac
