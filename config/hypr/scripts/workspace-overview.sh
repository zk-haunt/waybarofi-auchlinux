#!/usr/bin/env bash
# Workspace overview / switcher (Super + A).
#
# Replaces the hyprexpo plugin bind. hyprexpo was REMOVED from
# hyprwm/hyprland-plugins upstream (verified 2026-10-02: the repo now builds only
# borders-plus-plus, csgo-vulkan-fix, hyprbars and hyprfocus), and Hyprland 0.56
# has no native expo, so there was nothing left for Super+A to call.
#
# This is deliberately NOT a plugin: no compile step, and nothing to rebuild
# after every Hyprland update — which is the standing cost that made hyprpm
# plugins a poor fit for one keybind.
#
# Dispatch uses the Lua form. `hyprctl dispatch workspace N` is legacy hyprlang
# syntax that this Lua-config Hyprland rejects outright:
#     error: [string "return hl.dispatch(workspace 3)"]:1: ')' expected near '3'
# Switching to a workspace that does not exist yet is intentional — Hyprland
# creates it on focus, so empty workspaces are reachable.

set -uo pipefail

theme="$HOME/.config/rofi/powermenu/style.rasi"

# How many workspaces to always offer, even when empty. Matches waybar's
# persistent-workspaces so the bar and this menu agree.
MIN_WORKSPACES=${WORKSPACE_OVERVIEW_MIN:-5}

# nf-md-* glyphs, as \U escapes so the file survives an editor without the font.
# Chosen to be distinguishable at a glance: solid / half / outline. The
# circle-slice family all look alike at this size, which defeats the point.
ICON_ACTIVE=$'\U000F0AA5'    # nf-md-circle-medium   — filled: current
ICON_BUSY=$'\U000F0765'      # nf-md-circle-slice-6  — half:   has windows
ICON_EMPTY=$'\U000F09DE'     # nf-md-circle-outline  — hollow: empty

command -v hyprctl >/dev/null 2>&1 || { notify-send -u critical "Workspaces" "hyprctl not found"; exit 1; }

# One hyprctl call each, parsed together: which workspace is active, how many
# windows each holds, and the app classes on them for the preview text.
menu="$(
python3 - "$MIN_WORKSPACES" "$ICON_ACTIVE" "$ICON_BUSY" "$ICON_EMPTY" <<'PY'
import json, subprocess, sys
from collections import defaultdict

minws   = int(sys.argv[1])
i_act, i_busy, i_empty = sys.argv[2], sys.argv[3], sys.argv[4]

def hypr(*args):
    try:
        return json.loads(subprocess.run(["hyprctl", *args, "-j"],
                                         capture_output=True, text=True).stdout)
    except Exception:
        return []

active = 0
try:
    active = hypr("activeworkspace")["id"]
except Exception:
    pass

counts = {w["id"]: w["windows"] for w in hypr("workspaces") if isinstance(w, dict)}
apps = defaultdict(list)
for c in hypr("clients"):
    wid = c.get("workspace", {}).get("id")
    # Strip the reverse-DNS prefix flatpaks use, so "app.zen_browser.zen" reads
    # as "zen" rather than swamping the line.
    cls = (c.get("class") or "?").split(".")[-1]
    if wid is not None:
        apps[wid].append(cls)

# Offer the persistent range plus anything that exists beyond it (special
# workspaces have negative ids and are reached another way, so skip those).
ids = sorted(set(range(1, minws + 1)) | {i for i in counts if i > 0})

for i in ids:
    n = counts.get(i, 0)
    if i == active:
        icon, note = i_act, "current"
    elif n:
        icon, note = i_busy, ", ".join(dict.fromkeys(apps[i]))[:42]
    else:
        icon, note = i_empty, "empty"
    # Field 1 is the id and is what dispatch reads; the rest is cosmetic. Using
    # a sentinel field instead of matching the whole display string means a
    # label edit can never break selection.
    print(f"{i}\x1f{icon}  {i}   {note}")
PY
)"

[[ -z "$menu" ]] && { notify-send -u critical "Workspaces" "Could not read workspace state"; exit 1; }

lines=$(printf '%s\n' "$menu" | wc -l)
choice="$(printf '%s\n' "$menu" | cut -d$'\x1f' -f2 \
    | rofi -dmenu -i -no-custom -p "Workspace" -format i \
           -theme "$theme" -theme-str "listview { lines: ${lines}; columns: 1; }")"

# -format i returns the row INDEX, so the id comes from the same list rather
# than from parsing the display text back out.
[[ -z "$choice" ]] && exit 0
target="$(printf '%s\n' "$menu" | sed -n "$((choice + 1))p" | cut -d$'\x1f' -f1)"

[[ "$target" =~ ^[0-9]+$ ]] || { notify-send -u critical "Workspaces" "Unrecognised selection: $choice"; exit 1; }

if ! out="$(hyprctl dispatch "hl.dsp.focus({workspace = $target})" 2>&1)" || [[ "$out" == *rror* ]]; then
    notify-send -u critical "Workspaces" "Could not switch to $target: ${out:-dispatch failed}"
    exit 1
fi
