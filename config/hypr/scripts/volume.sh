#!/usr/bin/env bash

set -euo pipefail

step="${VOLUME_STEP:-5%}"
volume_limit="${VOLUME_LIMIT:-1.3}"

sink="${VOLUME_SINK:-@DEFAULT_AUDIO_SINK@}"
source="${VOLUME_SOURCE:-@DEFAULT_AUDIO_SOURCE@}"
notify_id="${VOLUME_NOTIFY_ID:-91190}"
mic_notify_id="${MIC_NOTIFY_ID:-91191}"

has() {
  command -v "$1" >/dev/null 2>&1
}

has wpctl || {
  printf 'volume.sh: wpctl is required\n' >&2
  exit 1
}

volume_percent() {
  wpctl get-volume "$sink" | awk '{ printf "%d", $2 * 100 }'
}

is_muted() {
  wpctl get-volume "$sink" | grep -q MUTED
}

# ── Overdrive: true if volume > 100% ──────────────────────────
is_overdrive() {
  local vol
  vol=$(wpctl get-volume "$sink" | awk '{ print $2 }')
  awk -v v="$vol" 'BEGIN { exit (v > 1.0) ? 0 : 1 }'
}

notify_volume() {
  has notify-send || return 0

  local volume="$1"
  local icon=""
  local message="${volume}%"

  if is_muted; then
    icon="󰝟"
    message="Muted"
  elif (( volume == 0 )); then
    icon=""
  elif (( volume < 50 )); then
    icon=""
  elif (( volume > 100 )); then
    # Overdrive mode — warn visually
    icon=""
    message="${volume}% ⚠ Overdrive"
  else
    icon=""
  fi

  notify-send \
    -a "Volume" \
    -r "$notify_id" \
    -u low \
    -t 900 \
    -e \
    -h "int:value:${volume}" \
    -h "string:x-canonical-private-synchronous:volume" \
    -h "string:x-dunst-stack-tag:volume" \
    "$icon  Volume" "$message"
}

# ── Status: JSON output for Waybar custom module ──────────────
status_json() {
  local volume
  volume=$(volume_percent)

  local icon tooltip class

  if is_muted; then
    icon=""
    tooltip="Muted"
    class="muted"
  elif (( volume == 0 )); then
    icon=""
    tooltip="${volume}%"
    class="zero"
  elif (( volume < 50 )); then
    icon=""
    tooltip="${volume}%"
    class="low"
  elif (( volume <= 100 )); then
    icon=""
    tooltip="${volume}%"
    class="normal"
  else
    icon=""
    tooltip="${volume}% — Overdrive active"
    class="overdrive"
  fi

  printf '{"text":"%s %d%%","tooltip":"%s","class":"%s"}\n' \
    "$icon" "$volume" "$tooltip" "$class"
}

case "${1:-}" in
  up)
    local_step="${2:-$step}"
    wpctl set-mute "$sink" 0
    wpctl set-volume -l "$volume_limit" "$sink" "${local_step}+"
    ;;
  down)
    local_step="${2:-$step}"
    wpctl set-volume "$sink" "${local_step}-"
    ;;
  mute)
    wpctl set-mute "$sink" toggle
    ;;
  mic-mute)
    wpctl set-mute "$source" toggle
    # Was `local mic_icon=…` here: `local` outside a function is an error, and
    # under `set -e` the script died on it — so this notification never showed.
    if wpctl get-volume "$source" | grep -q MUTED; then
      muted="Muted";   mic_icon="󰍭"
    else
      muted="Unmuted"; mic_icon="󰍬"
    fi
    has notify-send || exit 0
    notify-send \
      -a "Microphone" \
      -r "$mic_notify_id" \
      -u low \
      -t 900 \
      -e \
      -h "string:x-canonical-private-synchronous:microphone" \
      -h "string:x-dunst-stack-tag:microphone" \
      "$mic_icon  Microphone" "$muted"
    exit 0
    ;;
  status)
    # JSON for Waybar: ./volume.sh status
    status_json
    exit 0
    ;;
  *)
    printf 'Usage: %s {up|down|mute|mic-mute|status}\n' "$0" >&2
    exit 1
    ;;
esac

notify_volume "$(volume_percent)"
