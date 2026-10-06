#!/usr/bin/env bash
# Reports CPU package temperature (Tctl on AMD via k10temp, Package id 0 on Intel
# via coretemp) as a waybar custom-module JSON payload. Resolves the hwmon node
# dynamically since sysfs hwmon numbering isn't stable across reboots.
#
# Icon tiers match lol's HyDE `custom/gpuinfo`/`custom/cpuinfo` weather-style
# icons (~/.local/lib/hyde/gpuinfo.sh generate_json(), same 45/65/85°C
# breakpoints) — read from sysfs directly instead of via hyde-shell.


# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

WARN=70
CRIT=85

find_cpu_temp_input() {
    for hwmon in /sys/class/hwmon/hwmon*; do
        name=$(cat "$hwmon/name" 2>/dev/null)
        case "$name" in
            k10temp)
                for label_file in "$hwmon"/temp*_label; do
                    [[ -f "$label_file" ]] || continue
                    if [[ "$(cat "$label_file")" == "Tctl" ]]; then
                        echo "${label_file/_label/_input}"
                        return 0
                    fi
                done
                ;;
            coretemp)
                for label_file in "$hwmon"/temp*_label; do
                    [[ -f "$label_file" ]] || continue
                    if [[ "$(cat "$label_file")" == "Package id 0" ]]; then
                        echo "${label_file/_label/_input}"
                        return 0
                    fi
                done
                ;;
        esac
    done
    return 1
}

# Visible bar icon: thermometer fill level (matches lol's $thermo).
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

temp_input=$(find_cpu_temp_input)
if [[ -z "$temp_input" || ! -f "$temp_input" ]]; then
    echo '{"text":"","tooltip":"No CPU temperature sensor found","class":"hidden"}'
    exit 0
fi

raw=$(cat "$temp_input")
temp_c=$(( raw / 1000 ))
icon=$(thermo_icon "$temp_c")
emoji=$(weather_icon "$temp_c")

class="normal"
(( temp_c >= CRIT )) && class="critical"
(( temp_c >= WARN && temp_c < CRIT )) && class="warning"

# 5°C-bucket class for the color gradient, matching lol's cpuinfo.css
# (temp-0, temp-5, temp-10 ... temp-100).
temp_bucket=$(( (temp_c / 5) * 5 ))
(( temp_bucket < 0 )) && temp_bucket=0
(( temp_bucket > 100 )) && temp_bucket=100

cpu_model=$(lscpu | awk -F': ' '/Model name/ {gsub(/^ *| *$| CPU.*/,"",$2); print $2}')
max_mhz=$(lscpu | awk '/CPU max MHz/ { sub(/\..*/,"",$4); print $4}')
cur_mhz=$(awk '/cpu MHz/ {sum+=$NF; count++} END {if (count>0) printf "%.0f", sum/count}' /proc/cpuinfo)

tooltip="${emoji} ${cpu_model}\n${icon} Temperature: ${temp_c}°C"
[[ -n "$cur_mhz" && -n "$max_mhz" ]] && tooltip+="\n Clock Speed: ${cur_mhz}/${max_mhz} MHz"

# No icon in the visible text — the thermometer lives on gputemp (to our right
# in sys-group) so it renders *between* the two temps, matching lol's layout
# (cpuinfo text = bare "{temp}°C", gpuinfo text = "{thermo} {temp}°C").
printf '{"text":"%s°C", "tooltip":"%s", "class":["%s","temp-%s"]}\n' "$temp_c" "$tooltip" "$class" "$temp_bucket"
