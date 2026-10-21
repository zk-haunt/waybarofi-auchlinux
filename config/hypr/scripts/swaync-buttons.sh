#!/usr/bin/env bash

# Buttons for the SwayNC control centre (config/swaync/config.json).
#
#   swaync-buttons.sh <toggle>          set it to $SWAYNC_TOGGLE_STATE (true/false), or flip it when unset
#   swaync-buttons.sh <toggle> status   print true/false: the button's update-command
#   swaync-buttons.sh <action>          close the panel, then run it
#
#   toggles: wifi bluetooth airplane mute mic nightlight caffeine record
#            performance balanced power-saver
#   actions: screenshot lock logout power suspend reboot shutdown
#   battery: redraw the battery tile (its update-command does this on every open)
#
# swaync runs every update-command each time the panel opens, so a button's lit
# state is read back from the system, never remembered — a change made from the
# keyboard or the bar shows up correctly the next time the panel is opened.

# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to buttons, so a wrong exit turns a cosmetic bug into a
# dead button. -u catches typo'd variable names.
set -uo pipefail

SCRIPTS="${BASH_SOURCE[0]%/*}"
CAFFEINE_UNIT=auch-caffeine.service
SWAYNC_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/swaync"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/swaync"

# Toggles whose state the panel shows (record is left out: it closes the panel).
PANEL_TOGGLES=(wifi bluetooth airplane mute mic nightlight caffeine performance balanced power-saver)

# swaync is a systemd user service, and anything it spawns lives in its cgroup:
# `systemctl --user restart swaync` (apply-config.sh does one) would kill a
# recording or a lock screen started from the panel. A scope of its own
# outlives the restart; a transient *service* would not do, because systemd
# stops it — wf-recorder included — as soon as screenrecord.sh's main process exits.
launch() {
    if command -v systemd-run > /dev/null 2>&1; then
        systemd-run --user --scope --quiet -- "$@" > /dev/null 2>&1 &
    else
        setsid -f "$@" > /dev/null 2>&1
    fi
}

# The panel sits on the overlay layer: rofi would open underneath it, and a
# screenshot would capture it. Give its 200 ms close transition time to finish.
close_panel() {
    swaync-client -cp > /dev/null 2>&1
    sleep 0.3
}

reopen_panel() {
    close_panel
    swaync-client -op > /dev/null 2>&1
}

# ── Toggle state ──────────────────────────────────────────────
# NetworkManager and bluetoothd notice an rfkill block a beat late, so the
# block itself is checked first.
soft_blocked() { rfkill -n -o SOFT list "$1" 2> /dev/null | grep -qx blocked; }

is_wifi()       { ! soft_blocked wlan && [[ $(nmcli radio wifi 2> /dev/null) == enabled ]]; }
is_bluetooth()  { ! soft_blocked bluetooth && timeout 2 bluetoothctl show 2> /dev/null | grep -q 'Powered: yes'; }
is_mute()       { wpctl get-volume @DEFAULT_AUDIO_SINK@ 2> /dev/null | grep -q MUTED; }
is_mic()        { wpctl get-volume @DEFAULT_AUDIO_SOURCE@ 2> /dev/null | grep -q MUTED; }
is_nightlight() { [[ $(cat "$HOME/.cache/nightlight_state" 2> /dev/null) == on ]]; }
is_caffeine()   { systemctl --user is-active --quiet "$CAFFEINE_UNIT"; }
is_record()     { pgrep -x wf-recorder > /dev/null; }

# Airplane = every radio soft-blocked. No radios at all is not airplane mode.
is_airplane() {
    local soft
    soft="$(rfkill -n -o SOFT list 2> /dev/null)"
    [[ -n $soft ]] && ! grep -qx unblocked <<< "$soft"
}

profile()        { powerprofilesctl get 2> /dev/null; }
is_performance() { [[ $(profile) == performance ]]; }
is_balanced()    { [[ $(profile) == balanced ]]; }
is_power_saver() { [[ $(profile) == power-saver ]]; }

# ── Toggle actions ($1 = wanted state, true/false) ────────────
set_wifi() {
    if [[ $1 == true ]]; then
        rfkill unblock wlan   # airplane mode blocks below NetworkManager
        nmcli radio wifi on
    else
        nmcli radio wifi off
    fi
}

set_bluetooth() {
    if [[ $1 == true ]]; then
        rfkill unblock bluetooth
        # bluetoothd takes a moment to see the controller after the unblock,
        # and refuses power-on until it has.
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            timeout 2 bluetoothctl power on > /dev/null 2>&1 && return 0
            sleep 0.3
        done
        return 1
    else
        timeout 2 bluetoothctl power off > /dev/null 2>&1
    fi
}

# Leaving airplane mode brings Wi-Fi back but leaves Bluetooth off: it is off
# by default on this machine, and an unblock-all would quietly turn it on.
set_airplane() {
    if [[ $1 == true ]]; then
        rfkill block all
    else
        set_wifi true
    fi
}

set_mute() { wpctl set-mute @DEFAULT_AUDIO_SINK@ "$([[ $1 == true ]] && echo 1 || echo 0)"; }
set_mic()  { wpctl set-mute @DEFAULT_AUDIO_SOURCE@ "$([[ $1 == true ]] && echo 1 || echo 0)"; }

# nightlight.sh only knows "toggle", so only call it when the state differs.
set_nightlight() {
    local now=false
    is_nightlight && now=true
    [[ $1 == "$now" ]] || "$SCRIPTS/nightlight.sh" toggle
}

# An idle lock held by a transient unit: hypridle honours systemd idle
# inhibitors, and the unit survives a swaync restart. This is not the same lock
# as Waybar's coffee button — that one is a Wayland inhibitor living inside
# Waybar, which nothing outside Waybar can read or flip. Either keeps the
# screen awake; each button shows only its own.
set_caffeine() {
    if [[ $1 == true ]]; then
        is_caffeine || systemd-run --user --quiet --collect --unit="$CAFFEINE_UNIT" -- \
            systemd-inhibit --what=idle --who=Caffeine --why="Kept awake from the notification panel" \
            sleep infinity
    else
        systemctl --user stop "$CAFFEINE_UNIT"
    fi
}

# Profiles behave as radio buttons: clicking the lit one again keeps it.
set_performance() { powerprofilesctl set performance; }
set_balanced()    { powerprofilesctl set balanced; }
set_power_saver() { powerprofilesctl set power-saver; }

# screenrecord.sh is itself a toggle: with no arguments it opens its rofi menu,
# and while wf-recorder runs it stops the recording instead.
set_record() {
    local now=false
    is_record && now=true
    [[ $1 == "$now" ]] && return 0
    close_panel
    launch "$SCRIPTS/screenrecord.sh"
}

# ── Battery tile ──────────────────────────────────────────────
# swaync can't show live text: labels are fixed in config.json, and its slider
# widget never applies a getter's value (0.12.6 — even `echo 50` leaves it at
# 0). So the tile is a picture. The battery button's update-command, which
# swaync runs every time the panel opens, renders level, fill and time left to
# a PNG, points battery.css at it and reloads the CSS. The themes @import
# battery.css. It has to be generated because GTK only resolves an absolute
# file:// URL there, and the absolute path holds $HOME.
UPOWER_DEV=/org/freedesktop/UPower/devices/DisplayDevice

upower_prop() {
    busctl get-property org.freedesktop.UPower "$UPOWER_DEV" org.freedesktop.UPower.Device "$1" 2> /dev/null |
        awk '{ print $2 }'
}

# A hex colour from the matugen palette, so the fill follows the wallpaper.
palette() {
    local hex
    hex="$(sed -n "s/^@define-color $1 *\(#[0-9a-fA-F]\{6\}\);.*/\1/p" "$SWAYNC_DIR/colors.css" 2> /dev/null | head -n 1)"
    printf '%s' "${hex:-$2}"
}

# 2950 → "0h 49m"
duration() {
    local s="${1:-0}"
    ((s > 0)) || return 1
    printf '%dh %02dm' $((s / 3600)) $((s % 3600 / 60))
}

render_battery() {
    local pct=0 state sub="" icon w=190 h=44 fill svg png left
    local primary on_primary text
    primary="$(palette primary '#c1c1ff')"
    on_primary="$(palette on-primary '#2a2a60')"
    text="$(palette text '#e4e1e9')"

    mkdir -p "$CACHE_DIR" || return 1
    if [[ $(upower_prop IsPresent) == true ]]; then
        pct="$(upower_prop Percentage)"
        pct="${pct%.*}"
        [[ $pct =~ ^[0-9]+$ ]] || pct=0
        state="$(upower_prop State)"
        # UPower states: 1 charging, 2 discharging, 4 full, 5 pending charge.
        case "$state" in
            1) left="$(duration "$(upower_prop TimeToFull)")" && sub="$left to full" || sub="Charging" ;;
            2) left="$(duration "$(upower_prop TimeToEmpty)")" && sub="$left left" || sub="On battery" ;;
            4) sub="Fully charged" ;;
            5) sub="Plugged in" ;;
        esac
        # nf-md battery glyphs: battery_10 … battery_90 run U+F007A … U+F0082.
        if [[ $state == 1 ]]; then
            icon=$'\U000F0084'
        elif ((pct >= 95)); then
            icon=$'\U000F0079'
        elif ((pct < 10)); then
            icon=$'\U000F0083'
        else
            icon="$(printf "\\U$(printf '%08X' $((0xF007A + pct / 10 - 1)))")"
        fi
    else
        icon=$'\U000F06A5'
        sub="No battery"
    fi
    fill=$((w * pct / 100))

    # The text is drawn twice, clipped to each side of the fill edge: dark on
    # the fill, light past it, so it stays readable at any level.
    local body
    if [[ -n $sub ]]; then
        body="<text x='14' y='29' font-size='18'>$icon</text>
    <text x='40' y='22' font-size='15' font-weight='700'>$pct%</text>
    <text x='40' y='35' font-size='9' fill-opacity='0.8'>$sub</text>"
    else
        body="<text x='14' y='29' font-size='18'>$icon</text>
    <text x='40' y='28' font-size='15' font-weight='700'>$pct%</text>"
    fi
    svg="<svg xmlns='http://www.w3.org/2000/svg' width='$w' height='$h' viewBox='0 0 $w $h'
     font-family='JetBrainsMono Nerd Font'>
  <defs>
    <clipPath id='tile'><rect width='$w' height='$h' rx='12'/></clipPath>
    <clipPath id='on'><rect width='$fill' height='$h'/></clipPath>
    <clipPath id='off'><rect x='$fill' width='$((w - fill))' height='$h'/></clipPath>
  </defs>
  <g clip-path='url(#tile)'>
    <rect width='$w' height='$h' fill='$text' fill-opacity='0.08'/>
    <rect width='$fill' height='$h' fill='$primary'/>
  </g>
  <g clip-path='url(#on)' fill='$on_primary'>$body</g>
  <g clip-path='url(#off)' fill='$text'>$body</g>
</svg>"

    # A new file name every time: GTK may keep a decoded image for a URL it
    # has already loaded, and the reload has to pick up the new picture.
    png="$CACHE_DIR/battery-$(date +%s%N).png"
    rsvg-convert -z 2 -o "$png" <<< "$svg" || return 1
    find "$CACHE_DIR" -maxdepth 1 -name 'battery-*.png' ! -path "$png" -delete
    cat > "$SWAYNC_DIR/battery.css" << EOF
/* Generated by hypr/scripts/swaync-buttons.sh each time the panel opens. */
.control-center .widget-buttons-grid.power flowboxchild:first-child > button.toggle {
  background-image: url("file://${png// /%20}");
}
EOF
    swaync-client -rs > /dev/null 2>&1
}

# " wifi=1 bluetooth=0 ..." for every toggle the panel shows.
snapshot() {
    local t
    for t in "${PANEL_TOGGLES[@]}"; do
        "is_${t//-/_}" && printf ' %s=1' "$t" || printf ' %s=0' "$t"
    done
}

# ── Dispatch ──────────────────────────────────────────────────
name="${1:-}"
fn="${name//-/_}"

case "$name" in
    battery)
        # A toggle only for the update-command hook; it is never lit. A click
        # just redraws the tile.
        render_battery
        if [[ ${2:-} == status ]]; then echo false; fi
        ;;
    record)
        if [[ ${2:-} == status ]]; then
            is_record && echo true || echo false
            exit 0
        fi
        want="${SWAYNC_TOGGLE_STATE:-}"
        [[ -n $want ]] || { is_record && want=false || want=true; }
        set_record "$want"
        ;;
    wifi | bluetooth | airplane | mute | mic | nightlight | caffeine | performance | balanced | power-saver)
        if [[ ${2:-} == status ]]; then
            "is_$fn" && echo true || echo false
            exit 0
        fi
        want="${SWAYNC_TOGGLE_STATE:-}"
        [[ -n $want ]] || { "is_$fn" && want=false || want=true; }

        # Some buttons move others: airplane mode turns Wi-Fi and Bluetooth off,
        # Wi-Fi on ends airplane mode, a new power profile un-picks the old one.
        # swaync re-reads button states only when the panel opens, so when the
        # system no longer matches what the panel shows — another button moved,
        # or this one failed (Bluetooth refusing to power on) — reopen it.
        bit=0
        [[ $want == true ]] && bit=1
        before="$(snapshot)"
        expected="${before/ $name=[01]/ $name=$bit}"
        "set_$fn" "$want"
        sleep 0.3   # NetworkManager and bluetoothd follow rfkill asynchronously
        [[ "$(snapshot)" == "$expected" ]] || reopen_panel
        ;;
    screenshot)
        close_panel
        launch "$SCRIPTS/screenshot_lol.sh" s
        ;;
    lock | logout | suspend | reboot | shutdown)
        # Through power-menu.sh, so every one but lock gets its confirm step
        # (No preselected).
        close_panel
        action="$name"
        [[ $name == reboot ]] && action=restart
        launch "$SCRIPTS/power-menu.sh" "$action"
        ;;
    power)
        close_panel
        launch "$SCRIPTS/power-menu.sh"
        ;;
    *)
        printf 'Usage: %s <toggle> [status]   toggles: wifi bluetooth airplane mute mic nightlight caffeine record performance balanced power-saver\n' "$0" >&2
        printf '       %s <action>            actions: screenshot lock logout power suspend reboot shutdown\n' "$0" >&2
        printf '       %s battery [status]    redraw the battery tile\n' "$0" >&2
        exit 1
        ;;
esac
