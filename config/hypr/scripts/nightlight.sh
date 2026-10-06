#!/usr/bin/env bash

# ── Constants ─────────────────────────────────────────────────

# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

TEMP="${NIGHTLIGHT_TEMP:-4000}"       # Default colour temp (K)
GAMMA="${NIGHTLIGHT_GAMMA:-80}"       # Default gamma (%)
RESET_TEMP=6500                       # Neutral daylight temp for reset
STATE_FILE="$HOME/.cache/nightlight_state"
TEMP_FILE="$HOME/.cache/nightlight_temp"    # Stores last-used temp
GAMMA_FILE="$HOME/.cache/nightlight_gamma"  # Stores last-used gamma
WAYBAR_SIGNAL=8

# ── Helpers ───────────────────────────────────────────────────
ensure_state() {
    [[ -f "$STATE_FILE" ]] || echo "off" > "$STATE_FILE"
}

update_waybar() {
    pkill -RTMIN+$WAYBAR_SIGNAL waybar
}

current_temp() {
    [[ -f "$TEMP_FILE" ]] && cat "$TEMP_FILE" || echo "$TEMP"
}

current_gamma() {
    [[ -f "$GAMMA_FILE" ]] && cat "$GAMMA_FILE" || echo "$GAMMA"
}

# ── Core actions ──────────────────────────────────────────────
start_nightlight() {
    local temp="${1:-$(current_temp)}"
    local gamma="${2:-$(current_gamma)}"

    pkill -x hyprsunset 2>/dev/null
    sleep 0.1
    hyprsunset -t "$temp" -g "$gamma" >/dev/null 2>&1 &
    echo "on"    > "$STATE_FILE"
    echo "$temp"  > "$TEMP_FILE"
    echo "$gamma" > "$GAMMA_FILE"
    notify-send -u low "🌙 Night Light" "${temp}K | Gamma ${gamma}%"
}

stop_nightlight() {
    pkill -x hyprsunset 2>/dev/null
    sleep 0.1
    # Safety reset — forces screen back to neutral if hyprsunset
    # didn't clean up properly on exit
    hyprsunset -t "$RESET_TEMP" >/dev/null 2>&1 &
    sleep 0.3
    pkill -x hyprsunset 2>/dev/null
    echo "off" > "$STATE_FILE"
    notify-send -u low "☀️ Night Light Disabled"
}

# ── Commands ──────────────────────────────────────────────────
case "${1:-}" in
    toggle)
        ensure_state
        state=$(cat "$STATE_FILE")
        if [[ "$state" == "on" ]]; then
            stop_nightlight
        else
            start_nightlight
        fi
        update_waybar
        ;;

    set)
        # Usage: nightlight.sh set <temp_K> [gamma_%]
        # Example: nightlight.sh set 3200
        #          nightlight.sh set 3200 70
        if [[ -z "${2:-}" ]]; then
            printf 'Usage: %s set <temp_K> [gamma_%%]\n' "$0" >&2
            exit 1
        fi
        start_nightlight "$2" "${3:-$GAMMA}"
        echo "on" > "$STATE_FILE"
        update_waybar
        ;;

    warmer)
        t=$(current_temp); g=$(current_gamma)
        new_t=$(( t - 200 ))
        (( new_t < 1000 )) && new_t=1000
        start_nightlight "$new_t" "$g"
        echo "on" > "$STATE_FILE"
        update_waybar
        ;;

    cooler)
        t=$(current_temp); g=$(current_gamma)
        new_t=$(( t + 200 ))
        (( new_t > 6500 )) && new_t=6500
        [[ "$new_t" -ge 6500 ]] && stop_nightlight && update_waybar && exit 0
        start_nightlight "$new_t" "$g"
        echo "on" > "$STATE_FILE"
        update_waybar
        ;;

    gamma-up)
        # Increase gamma by 5% (brighter)
        g=$(current_gamma); t=$(current_temp)
        new_g=$(( g + 5 ))
        (( new_g > 100 )) && new_g=100
        start_nightlight "$t" "$new_g"
        echo "on" > "$STATE_FILE"
        update_waybar
        ;;

    gamma-down)
        # Decrease gamma by 5% (dimmer)
        g=$(current_gamma); t=$(current_temp)
        new_g=$(( g - 5 ))
        (( new_g < 10 )) && new_g=10
        start_nightlight "$t" "$new_g"
        echo "on" > "$STATE_FILE"
        update_waybar
        ;;

    status)
        ensure_state
        state=$(cat "$STATE_FILE")
        t=$(current_temp)
        if [[ "$state" == "on" ]]; then
            printf '{"text":"","class":"on","tooltip":"Night Light ON (%sK)"}\n' "$t"
        else
            printf '{"text":"","class":"off","tooltip":"Night Light OFF"}\n'
        fi
        ;;

    *)
        printf 'Usage: %s {toggle|set <K> [gamma]|warmer|cooler|gamma-up|gamma-down|status}\n' "$0" >&2
        exit 1
        ;;
esac