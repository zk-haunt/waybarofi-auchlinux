#!/usr/bin/env bash


# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

wallpaper_dir="$HOME/Pictures/wallpapers"
theme="$HOME/.config/rofi/wallpaper/style.rasi"
state_file="$HOME/.cache/current_wallpaper"

find_wallpapers() {
  find "$wallpaper_dir" -maxdepth 2 -type f \
    \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.bmp' -o -iname '*.gif' \) \
    -printf '%P\n' | sort
}

wallpaper_menu() {
  while IFS= read -r wallpaper; do
    printf '%s\0icon\x1f%s/%s\n' "$wallpaper" "$wallpaper_dir" "$wallpaper"
  done
}

if ! pgrep -x awww-daemon >/dev/null; then
  awww-daemon >/dev/null 2>&1 &
  sleep 0.2
fi

choice="$(find_wallpapers | wallpaper_menu | rofi -dmenu -i -no-custom -show-icons -p "Wallpaper" -theme "$theme")"
[[ -z "$choice" ]] && exit 0

wallpaper="$wallpaper_dir/$choice"

if [[ ! -f "$wallpaper" ]]; then
  notify-send -u low "Wallpaper" "File not found: $choice"
  exit 1
fi

awww img "$wallpaper" --resize crop --transition-type grow --transition-pos center --transition-duration 1
printf '%s\n' "$wallpaper" > "$state_file"
ln -sf "$wallpaper" "$HOME/.cache/current_wallpaper_image"
notify-send -u low -t 1200 "Wallpaper" "$choice"

# Generate color palette dynamically using matugen
if command -v matugen >/dev/null 2>&1; then
  matugen image "$wallpaper" --source-color-index 0 >/dev/null 2>&1 || true
  
  # Reload apps to apply new color palette dynamically
  (
    # Reload Kitty instances
    if pgrep -u "$USER" -x "kitty" >/dev/null; then
      pkill -u "$USER" -USR1 kitty || true
    fi
  ) &
fi

# Generate wallpaper blur, quad, sqre and thmb caches dynamically for Rofi theme styling
(
  auch_cache="$HOME/.cache/auch"
  mkdir -p "$auch_cache"
  blur_file="$auch_cache/wall.blur"
  quad_file="$auch_cache/wall.quad"
  sqre_file="$auch_cache/wall.sqre"
  thmb_file="$auch_cache/wall.thmb"

  magick "$wallpaper"[0] -strip -scale 10% -blur 0x3 -resize 100% "$blur_file"
  magick "$wallpaper"[0] -strip -thumbnail 500x500^ -gravity center -extent 500x500 "$sqre_file"
  magick "$sqre_file" \( -size 500x500 xc:white -fill "rgba(0,0,0,0.7)" -draw "polygon 400,500 500,500 500,0 450,0" -fill black -draw "polygon 500,500 500,0 450,500" \) -alpha Off -compose CopyOpacity -composite "$quad_file"
  magick "$wallpaper"[0] -strip -resize 1000x "$thmb_file"
) &
