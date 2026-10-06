#!/usr/bin/env bash

# VTube face-tracking pipeline (native Linux, no Proton):
#
#   webcam (/dev/video0)
#     -> OpenSeeFace tracker            (UDP 127.0.0.1:11573)
#     -> Inochi Session avatar window   (renders your .inp model)
#     -> wf-recorder region capture     -> /dev/video10 virtual cam
#     -> use "Phone Camera" device in Meet/Discord/OBS
#
# Why this stack: VTube Studio via Proton has broken webcam passthrough;
# Inochi Session is a native VTuber renderer that understands OpenSeeFace
# tracking directly.
#
# Usage:
#   ./vtube.sh setup      # install tracker + Inochi Creator/Session
#   ./vtube.sh run        # start tracker + avatar window
#   ./vtube.sh cam        # mirror the Session window into /dev/video10
#   ./vtube.sh stop       # stop everything
#
# One-time in Inochi Session: load your model (.inp), then
# Settings -> Tracking -> add "OpenSeeFace" source (port 11573).
# Make/export models with inochi-creator (example models: inochi2d.com).

set -euo pipefail

CAM_DEV="${VTUBE_CAM:-/dev/video0}"       # real webcam
LOOPDEV="${VTUBE_LOOPDEV:-/dev/video10}"  # virtual cam (v4l2loopback)
OSF_DIR="$HOME/.local/share/openseeface"
OSF_PORT=11573

have() { command -v "$1" >/dev/null 2>&1; }

setup() {
    echo "[1/3] Installing Inochi Creator + Session (AUR/chaotic)..."
    paru -S --needed --noconfirm inochi-session inochi-creator-bin

    echo
    echo "[2/3] Installing OpenSeeFace..."
    if paru -S --needed --noconfirm openseeface-git 2>/dev/null; then
        echo "Packaged OpenSeeFace installed."
    else
        echo "Package failed — falling back to a local venv install..."
        [[ -d $OSF_DIR ]] || git clone --depth 1 https://github.com/emilianavt/OpenSeeFace "$OSF_DIR"
        python -m venv "$OSF_DIR/venv"
        "$OSF_DIR/venv/bin/pip" install --upgrade pip
        "$OSF_DIR/venv/bin/pip" install onnxruntime opencv-python-headless pillow numpy
    fi

    echo
    echo "[3/3] Checking the virtual camera..."
    if [[ ! -e $LOOPDEV ]]; then
        echo "$LOOPDEV missing — v4l2loopback isn't loaded (install-packages.sh sets it up)."
        echo "Load it now with:  sudo modprobe v4l2loopback devices=1 video_nr=10 card_label=\"Phone Camera\" exclusive_caps=1"
    else
        echo "$LOOPDEV ready."
    fi
    echo
    echo "Setup done. Next: ./vtube.sh run"
}

tracker_cmd() {
    if have facetracker; then
        echo "facetracker"
    elif [[ -x $OSF_DIR/venv/bin/python ]]; then
        echo "$OSF_DIR/venv/bin/python $OSF_DIR/facetracker.py"
    else
        return 1
    fi
}

run() {
    cmd=$(tracker_cmd) || { echo "OpenSeeFace not installed — run './vtube.sh setup' first."; exit 1; }
    if ! pgrep -f "facetracker" >/dev/null; then
        echo "Starting OpenSeeFace tracker on $CAM_DEV (UDP $OSF_PORT)..."
        # model 3: best quality; drop to -M 1 on weak CPUs
        setsid $cmd -c "${CAM_DEV##*video}" -W 640 -H 480 --model 3 \
            --discard-after 0 --scan-every 30 -v 0 -s 1 -P 1 >/dev/null 2>&1 &
    else
        echo "Tracker already running."
    fi

    if ! pgrep -f inochi-session >/dev/null; then
        echo "Starting Inochi Session..."
        setsid inochi-session >/dev/null 2>&1 &
    else
        echo "Inochi Session already running."
    fi
    echo
    echo "Load your model + enable the OpenSeeFace tracking source in Session,"
    echo "position the window, then:  ./vtube.sh cam"
}

cam() {
    have wf-recorder || { echo "wf-recorder not installed."; exit 1; }
    [[ -e $LOOPDEV ]] || { echo "$LOOPDEV missing — see './vtube.sh setup'."; exit 1; }

    geo=$(hyprctl clients -j | python3 -c '
import json, sys
for c in json.load(sys.stdin):
    if "inochi-session" in (c.get("class") or "").lower():
        x, y = c["at"]; w, h = c["size"]
        print(f"{x},{y} {w}x{h}")
        break
')
    [[ -n $geo ]] || { echo "No Inochi Session window found — run './vtube.sh run' first."; exit 1; }

    pkill -f "wf-recorder.*$LOOPDEV" 2>/dev/null || true
    echo "Mirroring Session window ($geo) into $LOOPDEV — Ctrl+C to stop."
    exec wf-recorder -g "$geo" --muxer=v4l2 --codec=rawvideo --pixel-format=yuv420p --file="$LOOPDEV"
}

stop() {
    pkill -f "wf-recorder.*$LOOPDEV" 2>/dev/null || true
    pkill -f facetracker 2>/dev/null || true
    pkill -x inochi-session 2>/dev/null || true
    echo "VTube pipeline stopped."
}

case "${1:-}" in
    setup) setup ;;
    run)   run ;;
    cam)   cam ;;
    stop)  stop ;;
    *) sed -n '3,23p' "$0"; exit 1 ;;
esac
