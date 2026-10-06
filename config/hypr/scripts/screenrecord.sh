#!/usr/bin/env bash

# Define paths

# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

SAVE_DIR="${XDG_VIDEOS_DIR:-$HOME/Videos}/Recordings"
mkdir -p "$SAVE_DIR"
TIMESTAMP=$(date +'%Y-%m-%d_%H-%M-%S')
FILE_PATH="$SAVE_DIR/recording_$TIMESTAMP.mp4"

# Check if wf-recorder is already running
if pgrep -x "wf-recorder" > /dev/null; then
    # Stop recording gracefully
    pkill -INT -x "wf-recorder"
    # The background watcher of the active recording will handle cleanup, notifications, and waybar refresh
    exit 0
fi

# Parse options
AUDIO_MODE="none" # "none", "sys", "mic", "both"
FULLSCREEN=false
SCALE=false
MENU=false

# Cache file for scale setting persistence
SCALE_CACHE="$HOME/.cache/screenrecord_scale"
current_scale="100%"
if [[ -f "$SCALE_CACHE" ]]; then
    current_scale=$(cat "$SCALE_CACHE")
fi
if [[ "$current_scale" == "50%" ]]; then
    SCALE=true
fi

# If no arguments are passed, show the menu
if [[ $# -eq 0 ]]; then
    MENU=true
fi

while [[ $# -gt 0 ]]; do
    case "${1:-}" in
        --menu|-m)
            MENU=true
            shift
            ;;
        --audio-sys|-as)
            AUDIO_MODE="sys"
            shift
            ;;
        --audio-mic|-am)
            AUDIO_MODE="mic"
            shift
            ;;
        --audio-both|-ab)
            AUDIO_MODE="both"
            shift
            ;;
        --audio|-a)
            AUDIO_MODE="mic" # default to mic
            shift
            ;;
        --fullscreen|-f)
            FULLSCREEN=true
            shift
            ;;
        --area|-g)
            FULLSCREEN=false
            shift
            ;;
        --scale|-s)
            SCALE=true
            shift
            ;;
        *)
            # support legacy positional f argument
            if [[ "${1:-}" == "f" ]]; then
                FULLSCREEN=true
            fi
            shift
            ;;
    esac
done

if [[ "$MENU" = true ]]; then
    theme="$HOME/.config/rofi/powermenu/style.rasi"
    choice="$(printf '󰻂  Area (No Audio)\n󰻂  Area + System Audio\n󰻂  Area + Microphone\n󰻂  Area + System + Mic\n󰵟  Fullscreen (No Audio)\n󰵟  Fullscreen + System Audio\n󰵟  Fullscreen + Microphone\n󰵟  Fullscreen + System + Mic\n󰍉  Scale Resolution: %s' "$current_scale" | rofi -dmenu -i -no-custom -p "Record" -theme "$theme" -theme-str "listview { lines: 9; }")"

    [[ -z "$choice" ]] && exit 0

    if [[ "$choice" == *"Scale Resolution"* ]]; then
        if [[ "$current_scale" == "100%" ]]; then
            echo "50%" > "$SCALE_CACHE"
        else
            echo "100%" > "$SCALE_CACHE"
        fi
        # Re-execute script to refresh the menu
        exec "$0" "$@"
    fi

    case "$choice" in
        *Area\ \(No\ Audio\)*)
            FULLSCREEN=false; AUDIO_MODE="none" ;;
        *Area\ \+\ System\ Audio*)
            FULLSCREEN=false; AUDIO_MODE="sys" ;;
        *Area\ \+\ Microphone*)
            FULLSCREEN=false; AUDIO_MODE="mic" ;;
        *Area\ \+\ System\ \+\ Mic*)
            FULLSCREEN=false; AUDIO_MODE="both" ;;
        *Fullscreen\ \(No\ Audio\)*)
            FULLSCREEN=true; AUDIO_MODE="none" ;;
        *Fullscreen\ \+\ System\ Audio*)
            FULLSCREEN=true; AUDIO_MODE="sys" ;;
        *Fullscreen\ \+\ Microphone*)
            FULLSCREEN=true; AUDIO_MODE="mic" ;;
        *Fullscreen\ \+\ System\ \+\ Mic*)
            FULLSCREEN=true; AUDIO_MODE="both" ;;
    esac
fi

# Build arguments for wf-recorder
ARGS=()

# Audio device setups
MIX_SINK=""
MIX_LOOP_MIC=""
MIX_LOOP_SYS=""

cleanup_audio() {
    [[ -n "${MIX_LOOP_MIC:-}" ]] && pactl unload-module "$MIX_LOOP_MIC" 2>/dev/null || true
    [[ -n "${MIX_LOOP_SYS:-}" ]] && pactl unload-module "$MIX_LOOP_SYS" 2>/dev/null || true
    [[ -n "${MIX_SINK:-}" ]] && pactl unload-module "$MIX_SINK" 2>/dev/null || true
}

setup_audio() {
    case "$AUDIO_MODE" in
        mic)
            if command -v pactl >/dev/null 2>&1; then
                local mic
                mic=$(pactl get-default-source 2>/dev/null)
                if [[ -n "$mic" ]]; then
                    ARGS+=("-a" "$mic")
                else
                    ARGS+=("-a")
                fi
            else
                ARGS+=("-a")
            fi
            ;;
        sys)
            if command -v pactl >/dev/null 2>&1; then
                local sys
                sys="$(pactl get-default-sink 2>/dev/null).monitor"
                if [[ -n "$sys" ]]; then
                    ARGS+=("-a" "$sys")
                else
                    ARGS+=("-a")
                fi
            else
                ARGS+=("-a")
            fi
            ;;
        both)
            if command -v pactl >/dev/null 2>&1; then
                # Create null sink and loopbacks to record mixed system + mic audio
                MIX_SINK=$(pactl load-module module-null-sink sink_name=screenrecord_mix sink_properties=device.description="Screenrecord_Mix" 2>/dev/null || echo "")
                local mic sys
                mic=$(pactl get-default-source 2>/dev/null || echo "")
                sys=$(pactl get-default-sink 2>/dev/null || echo "")
                if [[ -n "$MIX_SINK" && -n "$mic" && -n "$sys" ]]; then
                    MIX_LOOP_MIC=$(pactl load-module module-loopback source="$mic" sink=screenrecord_mix latency_msec=1 2>/dev/null || echo "")
                    MIX_LOOP_SYS=$(pactl load-module module-loopback source="${sys}.monitor" sink=screenrecord_mix latency_msec=1 2>/dev/null || echo "")
                    ARGS+=("-a" "screenrecord_mix.monitor")
                else
                    cleanup_audio
                    ARGS+=("-a")
                fi
            else
                ARGS+=("-a")
            fi
            ;;
    esac
}

setup_audio

if [ "$SCALE" = true ]; then
    # Downscale resolution to half (iw/2:ih/2)
    ARGS+=("-F" "scale=iw/2:ih/2")
fi

case "$AUDIO_MODE" in
    none) audio_desc="No Audio" ;;
    mic) audio_desc="Microphone" ;;
    sys) audio_desc="System Audio" ;;
    both) audio_desc="System + Mic" ;;
esac

scale_desc=""
if [ "$SCALE" = true ]; then
    scale_desc=" (50% scale)"
fi

if [ "$FULLSCREEN" = true ]; then
    notify-send -a "Screen Recorder" -i "video-x-generic" "Recording Started" "Recording full screen ($audio_desc)$scale_desc. Press shortcut again to stop."
    # Start wf-recorder in background
    wf-recorder "${ARGS[@]}" -f "$FILE_PATH" >/dev/null 2>&1 &
    REC_PID=$!
else
    # If not running, start recording by selecting an area
    notify-send -a "Screen Recorder" -i "video-x-generic" "Select Area" "Drag a box to start recording, or press Escape to cancel."
    GEOM=$(slurp)

    # Check if geometry selection was cancelled
    if [ -z "$GEOM" ]; then
        cleanup_audio
        notify-send -a "Screen Recorder" -i "dialog-error" "Recording Cancelled" "No area was selected."
        exit 1
    fi

    notify-send -a "Screen Recorder" -i "video-x-generic" "Recording Started" "Recording selected area ($audio_desc)$scale_desc. Press shortcut again to stop."

    # Start wf-recorder in background
    wf-recorder "${ARGS[@]}" -g "$GEOM" -f "$FILE_PATH" >/dev/null 2>&1 &
    REC_PID=$!
fi

# Trigger Waybar refresh to show recording status instantly
sleep 0.2
pkill -RTMIN+9 waybar || true

# Watcher background process to clean up audio modules and send notifications
(
    while kill -0 "$REC_PID" 2>/dev/null; do
        sleep 0.5
    done
    cleanup_audio
    notify-send -a "Screen Recorder" -i "video-x-generic" "Recording Stopped" "Video saved to $SAVE_DIR"
    pkill -RTMIN+9 waybar || true
) &
