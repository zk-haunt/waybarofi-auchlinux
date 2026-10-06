#!/usr/bin/env bash
# Camera privacy monitor for Waybar

# 1. Check if hardware shutter is closed (if supported by device)

# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

shutter_closed=false
if command -v v4l2-ctl >/dev/null 2>&1; then
    for dev in /dev/video*; do
        if [[ -e "$dev" ]]; then
            ctrl=$(v4l2-ctl -d "$dev" --get-ctrl=privacy 2>/dev/null)
            if [[ "$ctrl" =~ privacy:\ 1 ]]; then
                shutter_closed=true
                break
            fi
        fi
    done
fi

# 2. Check if any process is actively using /dev/video*
cam_in_use=false
cam_pids=$(fuser /dev/video* 2>/dev/null | tr -s ' ' '\n' | grep -E '^[0-9]+$' | head -n 5)
if [[ -n "$cam_pids" ]]; then
    cam_in_use=true
    app_names=$(ps -o comm= -p $cam_pids 2>/dev/null | paste -sd ', ' -)
fi

if [[ "$cam_in_use" == "true" ]]; then
    echo "{\"text\": \"󰄀\", \"class\": \"camera-active\", \"tooltip\": \"Camera IN USE by: ${app_names:-Unknown}\"}"
elif [[ "$shutter_closed" == "true" ]]; then
    echo "{\"text\": \"󰗟\", \"class\": \"shutter-closed\", \"tooltip\": \"Camera Privacy Shutter: Closed\"}"
else
    echo "{\"text\": \"\", \"class\": \"idle\", \"tooltip\": \"Camera Idle\"}"
fi
