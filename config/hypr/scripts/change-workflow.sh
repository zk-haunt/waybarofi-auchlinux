#!/usr/bin/env bash
# Pick a workflow preset via rofi and apply it live (Super + Ctrl + W).
#
# Was completely broken. The old version ran:
#     hyprctl --batch "source $CONF"
# `source` is a hyprlang keyword and this config is pure Lua, so Hyprland
# rejected it and the `|| hyprctl reload` fallback simply re-read the Lua config,
# discarding the preset. It then wrote state and notified "Active: gaming"
# unconditionally — so the menu looked like it worked and never did.
#
# Now: one `hyprctl eval` into config/hypr/hyprland/workflows.lua, which holds
# the five presets as Lua tables. One IPC round-trip, applied atomically, and
# success is checked before anything is claimed.

set -uo pipefail

theme="$HOME/.config/rofi/powermenu/style.rasi"
# State lives under XDG_STATE_HOME, not /tmp: the old location meant your choice
# silently reset on every reboot. Also outside ~/.config, so apply-config.sh's
# rsync --delete cannot reach it.
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/hypr"
STATE_FILE="$STATE_DIR/workflow"

# Icons are nf-md-* from JetBrainsMono Nerd Font, as \U escapes. Each label is
# defined once and used in BOTH the menu and the dispatch lookup.
ICON_DEFAULT=$'\U000F062E'     # nf-md-tune
ICON_GAMING=$'\U000F0E5F'      # nf-md-controller
ICON_POWERSAVER=$'\U000F032A'  # nf-md-leaf
ICON_SNAPPY=$'\U000F0241'      # nf-md-flash
ICON_EDITING=$'\U000F03EB'     # nf-md-pencil

declare -A DESCRIPTIONS=(
  [default]="${ICON_DEFAULT}  Default — balanced gaps, blur, animations"
  [gaming]="${ICON_GAMING}  Gaming — no blur, no gaps, max FPS"
  [powersaver]="${ICON_POWERSAVER}  Powersaver — no animations, no blur, min power"
  [snappy]="${ICON_SNAPPY}  Snappy — fast animations, lightweight"
  [editing]="${ICON_EDITING}  Editing — wide layout, focused, calm"
)
ORDER=(default gaming powersaver snappy editing)

# One-time migration from the old /tmp state.
if [[ -f /tmp/hypr-workflow.state && ! -f "$STATE_FILE" ]]; then
    mkdir -p "$STATE_DIR"
    cp /tmp/hypr-workflow.state "$STATE_FILE" 2>/dev/null || true
    rm -f /tmp/hypr-workflow.state
fi

CURRENT="$(cat "$STATE_FILE" 2>/dev/null || echo default)"

MENU=""
for key in "${ORDER[@]}"; do
    MENU+="${DESCRIPTIONS[$key]}"$'\n'
done

# printf '%s' not "$MENU" as a format string — a '%' in any description would
# otherwise corrupt the menu.
CHOICE="$(printf '%s' "$MENU" | rofi -dmenu -i -no-custom -p "Workflow  [$CURRENT]" -theme "$theme" -theme-str "listview { lines: 5; }")"
[[ -z "$CHOICE" ]] && exit 0

KEY=""
for k in "${ORDER[@]}"; do
    [[ "${DESCRIPTIONS[$k]}" == "$CHOICE" ]] && { KEY="$k"; break; }
done
if [[ -z "$KEY" ]]; then
    notify-send -u critical "Workflow" "Unrecognised menu choice: $CHOICE"
    exit 1
fi

# Validate before it reaches Lua; the name is interpolated into a Lua string.
[[ "$KEY" =~ ^[a-z]+$ ]] || { notify-send -u critical "Workflow" "Bad preset name: $KEY"; exit 1; }

# package.loaded is cleared first so an edit to workflows.lua takes effect on the
# very next switch. Without it `require` returns the module cached at first use
# and your edits appear to do nothing until Hyprland reloads — which is exactly
# the kind of silent no-op this script is being fixed for. Re-parsing one small
# Lua file per switch costs nothing measurable.
#
# Note `hyprctl eval` prints "ok" and DISCARDS the Lua return value, so success
# cannot be read from the returned string. A raised error does reach stdout as
# "error: ...", which is what the check below relies on.
out="$(hyprctl eval "package.loaded['hyprland/workflows'] = nil; return require('hyprland/workflows').apply('$KEY')" 2>&1)"
rc=$?
if (( rc != 0 )) || [[ "$out" == *rror* || "$out" == *unknown\ workflow* ]]; then
    notify-send -u critical "Workflow: failed to apply $KEY" "${out:-hyprctl eval exited $rc}"
    exit 1
fi

# Only record state and claim success once the apply actually worked.
mkdir -p "$STATE_DIR"
printf '%s\n' "$KEY" > "$STATE_FILE"
notify-send -i preferences-system "Workflow" "Active: $KEY" -t 2000
