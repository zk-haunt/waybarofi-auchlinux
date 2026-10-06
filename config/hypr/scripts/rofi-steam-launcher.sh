#!/usr/bin/env bash

# Auchlinux Rofi Steam Game Launcher

# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

theme="$HOME/.config/rofi/powermenu/style.rasi"

# Default Steam paths
steam_paths=(
    "$HOME/.local/share/Steam"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
)

library_folders=()

# Find all standard and custom library folders
for path in "${steam_paths[@]}"; do
    if [[ -d "$path" ]]; then
        # Add main steamapps directory
        if [[ -d "$path/steamapps" ]]; then
            library_folders+=("$path/steamapps")
        fi
        # Check for custom library folders in libraryfolders.vdf
        vdf_file="$path/steamapps/libraryfolders.vdf"
        if [[ -f "$vdf_file" ]]; then
            # Extract paths from VDF file: "path" "/some/directory"
            while read -r line; do
                if [[ "$line" =~ \"path\"[[:space:]]+\"([^\"]+)\" ]]; then
                    lib_dir="${BASH_REMATCH[1]}/steamapps"
                    if [[ -d "$lib_dir" ]]; then
                        library_folders+=("$lib_dir")
                    fi
                fi
            done < "$vdf_file"
        fi
    fi
done

# Remove duplicate library paths
if [[ ${#library_folders[@]} -gt 0 ]]; then
    library_folders=($(echo "${library_folders[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
fi

# Collect games
games_list=""
declare -A game_ids

for lib in "${library_folders[@]}"; do
    # Using nullglob so if no manifests exist, the glob resolves to empty rather than literal wildcard string
    shopt -s nullglob
    for acf in "$lib"/appmanifest_*.acf; do
        [[ -f "$acf" ]] || continue
        
        # Parse AppID
        appid=$(grep -E '"appid"' "$acf" | awk -F '"' '{print $4}')
        # Parse Game Name
        name=$(grep -E '"name"' "$acf" | awk -F '"' '{print $4}')
        
        [[ -n "$appid" && -n "$name" ]] || continue
        
        # Filter out runtimes, compatibility tools, and common packages
        if [[ "$name" =~ "Proton" || "$name" =~ "Steam Linux Runtime" || "$name" =~ "SteamVR" || "$name" =~ "Steamworks" || "$name" =~ "Common Redistributables" || "$name" =~ "Soundtrack" ]]; then
            continue
        fi
        
        # Add to list
        games_list+="$name\n"
        game_ids["$name"]="$appid"
    done
    shopt -u nullglob
done

# If no games found
if [[ -z "$games_list" ]]; then
    notify-send -u critical "Steam Launcher" "No installed games found!"
    exit 1
fi

# Sort and run Rofi
selected=$(echo -e "$games_list" | sed '/^$/d' | sort | rofi -dmenu -i -no-custom -p "Steam Launcher" -theme "$theme")

# Launch the selected game
if [[ -n "$selected" ]]; then
    appid="${game_ids[$selected]}"
    if [[ -n "$appid" ]]; then
        notify-send -u low "Steam Launcher" "Launching $selected..."
        if command -v steam &>/dev/null; then
            steam "steam://rungameid/$appid" &
        elif command -v flatpak &>/dev/null && flatpak list | grep -q "com.valvesoftware.Steam"; then
            flatpak run com.valvesoftware.Steam "steam://rungameid/$appid" &
        else
            notify-send -u critical "Steam Launcher" "Steam command not found!"
        fi
    fi
fi
