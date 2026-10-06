#!/usr/bin/env bash
# Reports AMD/NVIDIA GPU temperature as a waybar custom-module JSON payload.
# Resolves the hwmon node dynamically (sysfs hwmon numbering isn't stable
# across reboots) instead of hardcoding a path like /sys/class/hwmon/hwmon6.
#
# Icon tiers + tooltip layout match lol's HyDE `custom/gpuinfo` module
# (~/.local/lib/hyde/gpuinfo.sh generate_json()) — same weather-style icon
# breakpoints (45/65/85°C), same "Name / Temperature / Utilization / Power"
# tooltip shape — just read from sysfs directly instead of via hyde-shell.


# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

WARN=75
CRIT=90

find_gpu_hwmon() {
    for hwmon in /sys/class/hwmon/hwmon*; do
        name=$(cat "$hwmon/name" 2>/dev/null)
        if [[ "$name" == "amdgpu" || "$name" == "nvidia" ]]; then
            echo "$hwmon"
            return 0
        fi
    done
    return 1
}

# Visible bar icon: thermometer fill level (matches lol's $thermo, the icon
# actually shown in "text" — not the weather icon, that's tooltip-only below).
thermo_icon() {
    local t=$1
    if (( t >= 85 )); then echo ""
    elif (( t >= 65 )); then echo ""
    elif (( t >= 45 )); then echo ""
    else echo ""
    fi
}

# Tooltip-only icon: weather glyph (matches lol's $emoji).
weather_icon() {
    local t=$1
    if (( t >= 85 )); then echo ""
    elif (( t >= 65 )); then echo ""
    elif (( t >= 45 )); then echo "☁"
    else echo "❄"
    fi
}

hwmon_dir=$(find_gpu_hwmon)
if [[ -z "$hwmon_dir" || ! -f "$hwmon_dir/temp1_input" ]]; then
    echo '{"text":"","tooltip":"No GPU temperature sensor found","class":"hidden"}'
    exit 0
fi

raw=$(cat "$hwmon_dir/temp1_input")
temp_c=$(( raw / 1000 ))
icon=$(thermo_icon "$temp_c")
emoji=$(weather_icon "$temp_c")

class="normal"
(( temp_c >= CRIT )) && class="critical"
(( temp_c >= WARN && temp_c < CRIT )) && class="warning"

# 5°C-bucket class for the color gradient, matching lol's gpuinfo.css
# (temp-0, temp-5, temp-10 ... temp-100).
temp_bucket=$(( (temp_c / 5) * 5 ))
(( temp_bucket < 0 )) && temp_bucket=0
(( temp_bucket > 100 )) && temp_bucket=100

gpu_name=$(lspci -nn | grep -Ei "VGA|3D" | grep -m1 -i "1002" | sed -E 's/.*Inc\. //; s/ *\[[^]]*\]//g; s/ *\([^)]*\)//g')
[[ -z "$gpu_name" ]] && gpu_name="GPU"

utilization=""
for card in /sys/class/drm/card*/device; do
    if [[ "$(readlink -f "$card")" == "$(readlink -f "$hwmon_dir/device")" ]]; then
        [[ -f "$card/gpu_busy_percent" ]] && utilization=$(cat "$card/gpu_busy_percent")
        break
    fi
done

power_w=""
[[ -f "$hwmon_dir/power1_input" ]] && power_w=$(awk -v p="$(cat "$hwmon_dir/power1_input")" 'BEGIN{printf "%.1f", p/1000000}')

tooltip="${emoji} ${gpu_name}\n${icon} Temperature: ${temp_c}°C"
[[ -n "$utilization" ]] && tooltip+="\n Utilization: ${utilization}%"
[[ -n "$power_w" ]] && tooltip+="\n󱪉 Power Usage: ${power_w} W"

# Thermometer icon leads this module's text so it sits *between* the CPU temp
# (bare number, to our left) and this GPU temp — the single shared thermometer,
# exactly like lol's gpuinfo text "{thermo} {temp}°C". Module gap comes from
# waybar's default group spacing, not a leading space.
printf '{"text":"%s %s°C", "tooltip":"%s", "class":["%s","temp-%s"]}\n' "$icon" "$temp_c" "$tooltip" "$class" "$temp_bucket"
