#!/usr/bin/env bash

# Pick a Hypr3D world via Rofi and load it live (SUPER + H, or SUPER + CTRL + 3).
# The worlds are listed in hyprland/hypr3d-worlds.lua; this writes the choice to
# ~/.local/state/hypr3d/world and re-runs hyprland/hypr3d.lua, which loads it.

# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names.
set -uo pipefail

theme="$HOME/.config/rofi/powermenu/style.rasi"
WORLDS="$HOME/.config/hypr/hyprland/hypr3d-worlds.lua"
DATA="${XDG_DATA_HOME:-$HOME/.local/share}/hypr3d"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/hypr3d/world"

notify() { notify-send -a 'Hypr3D' -i 'dialog-information' -u low "$@"; }

CURRENT="$(cat "$STATE" 2> /dev/null)"
CURRENT="${CURRENT:-virtualcity}"

# "id<TAB>name<TAB>about" for every world whose model is on disk ("none" has no file).
mapfile -t ROWS < <(lua - "$WORLDS" "$DATA" << 'LUA'
local worlds = dofile(arg[1])
for _, w in ipairs(worlds) do
    local present = w.path == nil
    if w.path then
        local f = io.open(arg[2] .. "/" .. w.path, "r")
        if f then f:close(); present = true end
    end
    if present then print(w.id .. "\t" .. w.name .. "\t" .. (w.about or "")) end
end
LUA
)

if ((${#ROWS[@]} == 0)); then
    notify 'Hypr3D' "No worlds found (is $WORLDS there?)"
    exit 1
fi

IDS=() NAMES=() LABELS=()
for row in "${ROWS[@]}"; do
    IFS=$'\t' read -r id name about <<< "$row"
    IDS+=("$id")
    NAMES+=("$name")
    mark='   '
    [[ $id == "$CURRENT" ]] && mark='●  '
    LABELS+=("$mark$name${about:+  ·  $about}")
done

# -format i: rofi prints the row number, which maps back to the id.
idx="$(printf '%s\n' "${LABELS[@]}" | rofi -dmenu -i -no-custom -format i -p "World" -theme "$theme")"
[[ -z $idx ]] && exit 0
CHOICE="${IDS[$idx]}"
NAME="${NAMES[$idx]}"

mkdir -p "${STATE%/*}" && printf '%s\n' "$CHOICE" > "$STATE"

# `hyprctl eval` prints "ok" or "error: <message>" and drops return values, so
# questions are asked with error(): the message is the answer.
if [[ "$(hyprctl eval 'assert(hl.plugin and hl.plugin.hypr3d, "unloaded")' 2>&1)" != ok ]]; then
    notify "World: $NAME" 'Hypr3D is not loaded; this world opens once it is (hyprpm reload -n).'
    exit 0
fi

# Leave the room before switching. Its on-state hook saves the blur setting on entry
# and restores it on exit; re-running hypr3d.lua while inside would register a fresh
# hook that saves "blur off" as the setting to restore.
was_open=false
if [[ "$(hyprctl eval 'if hl.plugin.hypr3d.active() then error("open", 0) end' 2>&1)" == "error: open" ]]; then
    was_open=true
    hyprctl eval 'hl.plugin.hypr3d.close()' > /dev/null
    sleep 1 # the closing transition
fi

# Re-run only the Hypr3D module: `hyprctl reload` would redo the whole config.
out="$(hyprctl eval 'package.loaded["hyprland/hypr3d-worlds"] = nil; package.loaded["hyprland/hypr3d"] = nil; require("hyprland/hypr3d")' 2>&1)"
if [[ $out != ok ]]; then
    notify-send -a 'Hypr3D' -u critical "Couldn't load $NAME" "$out"
    exit 1
fi

$was_open && hyprctl eval 'hl.plugin.hypr3d.open()' > /dev/null
notify "World: $NAME" "$($was_open && echo 'Loaded.' || echo 'Open it with Super + Alt + 3.')"
