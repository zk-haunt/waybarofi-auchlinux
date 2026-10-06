#!/usr/bin/env bash

# Toggle: if rofi is already running for the user, kill it and exit

# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

if pgrep -u "$USER" -x rofi >/dev/null; then
  pkill -u "$USER" -x rofi
  exit 0
fi

theme="$HOME/.config/rofi/clipboard/style.rasi"
watcher="$HOME/.config/hypr/scripts/clipboard-watch.sh"
favorites_file="$HOME/.cache/cliphist_favorites"

# Image-grid mode. Only ever set as a per-command env assignment by the
# `image-history` case below, and read in three places. Under `set -u` an unset
# read is fatal, which killed plain `clipboard-menu.sh history` (Super+V)
# outright — so give it an explicit default. The per-command assignment still
# wins for that one call.
CLIPHIST_IMAGE_HISTORY="${CLIPHIST_IMAGE_HISTORY:-false}"

"$watcher"

# Generate wallpaper blur, quad, sqre and thmb caches dynamically for Rofi theme styling
auch_cache="$HOME/.cache/auch"
current_wall="$(cat "$HOME/.cache/current_wallpaper" 2>/dev/null)"
if [[ -f "$current_wall" ]]; then
  mkdir -p "$auch_cache"
  blur_file="$auch_cache/wall.blur"
  quad_file="$auch_cache/wall.quad"
  sqre_file="$auch_cache/wall.sqre"
  thmb_file="$auch_cache/wall.thmb"

  # If cached files do not exist, or the wallpaper has updated, regenerate
  if [[ ! -f "$blur_file" || "$current_wall" -nt "$blur_file" ]]; then
    magick "$current_wall"[0] -strip -scale 10% -blur 0x3 -resize 100% "$blur_file"
  fi
  if [[ ! -f "$quad_file" || "$current_wall" -nt "$quad_file" || ! -f "$sqre_file" || "$current_wall" -nt "$sqre_file" || ! -f "$thmb_file" || "$current_wall" -nt "$thmb_file" ]]; then
    magick "$current_wall"[0] -strip -thumbnail 500x500^ -gravity center -extent 500x500 "$sqre_file"
    magick "$sqre_file" \( -size 500x500 xc:white -fill "rgba(0,0,0,0.7)" -draw "polygon 400,500 500,500 500,0 450,0" -fill black -draw "polygon 500,500 500,0 450,500" \) -alpha Off -compose CopyOpacity -composite "$quad_file"
    magick "$current_wall"[0] -strip -resize 1000x "$thmb_file"
  fi
fi

notify() {
  notify-send -a "Clipboard" -u low -t 1200 "󰅇  Clipboard" "$1"
}

run_rofi() {
  local prompt="$1"
  shift

  local extra_theme_str=""
  if [[ "$CLIPHIST_IMAGE_HISTORY" == "true" ]]; then
    # Colour names must match what config/rofi/clipboard/style.rasi actually
    # defines. It has no @import, so it only knows main-*/select-*; the matugen
    # names (@foreground, @selected) resolve to nothing here, and @selected-text
    # is not defined anywhere in the repo at all.
    #
    # `configuration { show-icons: true; }` is load-bearing, not tidying. The base
    # theme sets `show-icons: false` in its own configuration block (it is a text
    # dropdown), and that beats the `-show-icons` CLI flag passed below. Combined
    # with `element-text { enabled: false }` here, every element had neither text
    # nor icon to draw — and since elements are transparent, the whole grid was
    # invisible except the one selected row, which shows only because it has a
    # background colour. That is the "grids and nothing else" symptom.
    #
    # Icon size is the thing that makes or breaks this view. At the original
    # 100px, a 1920x1080 screenshot renders as 100x56 — and since most captures
    # are dark terminal/editor content, the cells read as *empty boxes*. rofi was
    # loading them correctly the whole time; they were just too small to see.
    # 200px gives 200x113 for 16:9, which is legible, and 3x3 keeps nine on
    # screen. Window must grow to match or the grid is clipped.
    extra_theme_str="configuration { show-icons: true; } listview { lines: 2; columns: 2; spacing: 4px; } element { enabled: true; orientation: vertical; spacing: 0%; padding: 4px; cursor: pointer; background-color: transparent; text-color: @main-fg; horizontal-align: 0.5; border-radius: 8px; } element-text { enabled: false; } element-icon { size: 190px; spacing: 0%; padding: 0%; cursor: inherit; background-color: transparent; } element selected.normal { background-color: @select-bg; text-color: @select-fg; } window { width: 440px; height: 520px; }"
  fi

  # Centred on the focused monitor, like emoji-picker.sh / glyph-picker.sh and the
  # rest of the rofi menus: the theme declares no `location`, so rofi centres by
  # default and we simply don't override it.
  #
  # This used to anchor to the mouse via get_rofi_pos(), which picked the nearest
  # corner and offset from it *without* accounting for the popup's own size — so
  # with the pointer low on the screen, the bottom half of the menu rendered
  # off-screen. Removed rather than patched: there is no cursor position that is
  # better than centred for a full-height list.
  local final_theme_str="$extra_theme_str"

  local rofi_cmd=(rofi -dmenu -i -no-custom -p "$prompt" -theme "$theme")
  if [[ -n "$final_theme_str" ]]; then
    rofi_cmd+=(-theme-str "$final_theme_str")
  fi

  if [[ "$CLIPHIST_IMAGE_HISTORY" == "true" ]]; then
    rofi_cmd+=(-show-icons -eh 3)
  fi

  "${rofi_cmd[@]}" \
    -kb-custom-1 "Alt+c" \
    -kb-custom-2 "Alt+d" \
    -kb-custom-3 "Alt+n" \
    -kb-custom-4 "Alt+w" \
    -kb-custom-5 "Alt+o" \
    -kb-custom-6 "Alt+v" \
    -kb-custom-7 "Alt+s" \
    "$@"

  local exit_code=$?
  if [[ $exit_code -ne 0 ]]; then
    case "$exit_code" in
      10) printf ":c:o:p:y:" ;;
      11) printf ":d:e:l:e:t:e:" ;;
      12) printf ":f:a:v:" ;;
      13) printf ":w:i:p:e:" ;;
      14) printf ":o:p:t:" ;;
      15) printf ":i:m:g:" ;;
      16) printf ":o:c:r:" ;;
    esac
  fi
}

handle_special_commands() {
  local selected="$1"
  case "$selected" in
    :c:o:p:y:*) exec "$0" history ;;
    :d:e:l:e:t:e:*) exec "$0" delete ;;
    :f:a:v:*) exec "$0" favorites ;;
    :w:i:p:e:*) exec "$0" wipe ;;
    :o:p:t:*) exec "$0" options ;;
    :i:m:g:*) exec "$0" image-history ;;
    :o:c:r:*) exec "$0" scan ;;
  esac
}

history_empty() {
  ! cliphist list >/dev/null 2>&1 || [[ -z "$(cliphist list 2>/dev/null)" ]]
}

paste_string() {
  if ! command -v wtype >/dev/null; then return 0; fi
  local ignore_paste_file="$HOME/.cache/ignore.paste"
  if [[ ! -e "$ignore_paste_file" ]]; then
    mkdir -p "$(dirname "$ignore_paste_file")"
    cat <<EOF >"$ignore_paste_file"
kitty
org.kde.konsole
terminator
XTerm
Alacritty
xterm-256color
EOF
  fi

  local class
  class=$(hyprctl -j activewindow | jq -r '.initialClass')
  if ! grep -Fxq "$class" "$ignore_paste_file"; then
    sleep 0.15
    hyprctl -q dispatch exec 'wtype -M ctrl V -m ctrl'
  fi
}

copy_item() {
  local item="$1"

  if [[ "$item" == *"[[ binary data"* ]]; then
    printf '%s' "$item" | cliphist decode | wl-copy
    notify "Copied binary item"
    paste_string
  else
    printf '%s' "$item" | cliphist decode | wl-copy
    notify "Copied to clipboard"
    paste_string
  fi
}

show_history() {
  local selected
  if [[ "$CLIPHIST_IMAGE_HISTORY" == "true" ]]; then
    # Piped STRAIGHT into rofi — never through a variable.
    #
    # rofi's icon protocol separates the display row from `icon\x1f<path>` with a
    # NUL byte, and bash's $( ) strips NUL. Capturing this list first therefore
    # removed every icon marker and the grid rendered as blank cells: measured
    # 104 rows in, 0 NUL bytes out. The row text still looked right, which is why
    # this survived several wrong diagnoses (window height, icon size, load time).
    #
    # Image-only, because this mode disables element-text: text entries would all
    # render as the same anonymous `text-x-generic` icon with nothing to tell them
    # apart.
    selected="$(AUCH_CLIPHIST_IMAGE_ONLY=true python3 "$HOME/.config/hypr/scripts/cliphist-image.py" \
                 | run_rofi "History" -selected-row 2)"
  else
    selected="$( { printf ':favorites:\t📌 Favorites\n'
                   printf ':options:\t⚙️ Options\n'
                   cliphist list
                 } | run_rofi "History" -selected-row 2 )"
  fi

  [[ -z "$selected" ]] && exit 0

  handle_special_commands "$selected"

  case "$selected" in
    :favorites:*) view_favorites ;;
    :options:*) show_options ;;
    *)
      copy_item "$selected"
      ;;
  esac
}

delete_items() {
  if history_empty; then
    notify "History is empty."
    return
  fi

  local selected
  selected="$(cliphist list | run_rofi "Delete" -multi-select -display-columns 2)"
  [[ -z "$selected" ]] && return

  handle_special_commands "$selected"

  while IFS= read -r item; do
    [[ -n "$item" ]] && printf '%s' "$item" | cliphist delete
  done <<< "$selected"

  notify "Deleted selected item(s)"
}

ensure_favorites_file() {
  mkdir -p "$(dirname "$favorites_file")"
  touch "$favorites_file"
}

favorite_preview() {
  base64 --decode <<< "$1" | tr '\n' ' '
}

add_favorite() {
  if history_empty; then
    notify "History is empty."
    return
  fi

  ensure_favorites_file

  local item decoded encoded
  item="$(cliphist list | run_rofi "Add Favorite" -display-columns 2)"
  [[ -z "$item" ]] && return

  handle_special_commands "$item"

  decoded="$(printf '%s' "$item" | cliphist decode)"
  encoded="$(printf '%s' "$decoded" | base64 -w 0)"

  if grep -Fxq "$encoded" "$favorites_file"; then
    notify "Already in favorites"
  else
    printf '%s\n' "$encoded" >> "$favorites_file"
    notify "Added to favorites"
  fi
}

view_favorites() {
  ensure_favorites_file

  if [[ ! -s "$favorites_file" ]]; then
    notify "No favorites yet."
    return
  fi

  local previews selected index encoded
  previews="$(while IFS= read -r encoded; do favorite_preview "$encoded"; printf '\n'; done < "$favorites_file")"
  selected="$(printf '%s' "$previews" | run_rofi "Favorites")"
  [[ -z "$selected" ]] && return

  handle_special_commands "$selected"

  index="$(printf '%s' "$previews" | grep -nxF "$selected" | cut -d: -f1 | head -n 1)"
  [[ -z "$index" ]] && return

  encoded="$(sed -n "${index}p" "$favorites_file")"
  base64 --decode <<< "$encoded" | wl-copy
  notify "Copied favorite"
  paste_string
}

delete_favorite() {
  ensure_favorites_file

  if [[ ! -s "$favorites_file" ]]; then
    notify "No favorites to remove."
    return
  fi

  local previews selected index
  previews="$(while IFS= read -r encoded; do favorite_preview "$encoded"; printf '\n'; done < "$favorites_file")"
  selected="$(printf '%s' "$previews" | run_rofi "Remove Favorite")"
  [[ -z "$selected" ]] && return

  handle_special_commands "$selected"

  index="$(printf '%s' "$previews" | grep -nxF "$selected" | cut -d: -f1 | head -n 1)"
  [[ -z "$index" ]] && return

  sed -i "${index}d" "$favorites_file"
  notify "Removed favorite"
}

manage_favorites() {
  local action
  action="$(printf 'Add Favorite\nRemove Favorite\nClear Favorites\n' | run_rofi "Favorites")"

  [[ -z "$action" ]] && return
  handle_special_commands "$action"

  case "$action" in
    "Add Favorite") add_favorite ;;
    "Remove Favorite") delete_favorite ;;
    "Clear Favorites")
      local confirm
      confirm="$(printf 'No\nYes\n' | run_rofi "Clear Favorites?")"
      handle_special_commands "$confirm"
      [[ "$confirm" == "Yes" ]] && : > "$favorites_file" && notify "Favorites cleared"
      ;;
    *) notify "Unrecognised Favorites choice: $action" ;;
  esac
}

wipe_history() {
  local confirm
  confirm="$(printf 'No\nYes\n' | run_rofi "Clear History?")"
  [[ -z "$confirm" ]] && return
  handle_special_commands "$confirm"
  if [[ "$confirm" == "Yes" ]]; then
    cliphist wipe
    notify "History cleared"
  fi
}

scan_image() {
  local runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/cliphist"
  mkdir -p "$runtime_dir"
  local image_path="${runtime_dir}/cliphist_ocr.png"

  local index
  index="$(AUCH_CLIPHIST_IMAGE_ONLY=true python3 "$HOME/.config/hypr/scripts/cliphist-image.py" | head -n1 | awk '{print $1}')"

  if [[ -z "$index" ]]; then
    notify "OCR Error: No images in clipboard history"
    return 1
  fi

  cliphist decode "$index" > "$image_path"
  if [[ ! -s "$image_path" ]]; then
    notify "OCR Error: Failed to decode image data"
    return 1
  fi

  notify "Scanning latest image from clipboard..."

  local tesseract_output
  tesseract_output=$(tesseract --psm 6 --oem 3 -l eng "$image_path" stdout 2>/dev/null)

  if [[ -n "$tesseract_output" ]]; then
    printf "%s" "$tesseract_output" | wl-copy
    notify "OCR Success: ${#tesseract_output} symbols recognized"
  else
    notify "OCR Error: No text recognized in image"
  fi
}

# QR payload from the most recent clipboard image. Deliberately the clipboard
# counterpart to Super+Q (screenshot.sh sq), which snips a fresh screen region:
# same tool, different source. Useful when the code already went through the
# clipboard — a screenshot someone sent you, say — and is no longer on screen.
decode_qr() {
  command -v zbarimg >/dev/null 2>&1 || { notify "QR Error: zbarimg not installed (pacman -S zbar)"; return 1; }

  local runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/cliphist"
  mkdir -p "$runtime_dir"
  local image_path="${runtime_dir}/cliphist_qr.png"

  local index
  index="$(AUCH_CLIPHIST_IMAGE_ONLY=true python3 "$HOME/.config/hypr/scripts/cliphist-image.py" | head -n1 | awk '{print $1}')"

  if [[ -z "$index" ]]; then
    notify "QR Error: No images in clipboard history"
    return 1
  fi

  cliphist decode "$index" > "$image_path"
  if [[ ! -s "$image_path" ]]; then
    notify "QR Error: Failed to decode image data"
    return 1
  fi

  notify "Decoding QR from latest clipboard image..."

  # --raw drops zbar's "QR-Code:" prefix so the clipboard holds just the payload.
  # screenshot.sh's `qr` keeps the prefix; this is the better behaviour of the two.
  local qr_output
  qr_output="$(zbarimg --quiet --raw "$image_path" 2>/dev/null)"

  if [[ -n "$qr_output" ]]; then
    printf '%s' "$qr_output" | wl-copy
    notify "QR decoded: ${#qr_output} characters copied"
  else
    notify "QR Error: No QR code found in image"
  fi
}

# How long Hyprland keeps compositing a layer-shell surface after it closes.
#
# hyprpicker's freeze grabs whatever is still on screen, so launching the OCR
# region selector straight after rofi exits catches the menu mid-slide-out.
# Polling `hyprctl layers` does NOT solve it: the surface leaves that list ~10ms
# after rofi exits while the close animation keeps drawing a snapshot. The only
# honest wait is the animation's own duration.
#
# Read it instead of hardcoding, because this repo ships switchable animation
# presets and layersOut differs between them (8 => 800ms in the current one).
# Hyprland expresses speed in 100ms units; a leaf at speed 0 inherits its parent.
layer_close_delay() {
  hyprctl -j animations 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    anims = d[0] if d and isinstance(d[0], list) else d
    by = {a["name"]: a for a in anims if isinstance(a, dict)}
except Exception:
    print("0.85"); raise SystemExit
def speed(leaf, parent):
    a = by.get(leaf) or {}
    if not a.get("enabled", True):
        return 0.0
    s = float(a.get("speed") or 0)
    if s <= 0:
        s = float((by.get(parent) or {}).get("speed") or 0)
    return s
ms = max(speed("layersOut", "layers"), speed("fadeLayersOut", "fadeLayers")) * 100
print("%.2f" % (min(max(ms * 1.15, 120), 1500) / 1000.0 if ms else 0.12))
' 2>/dev/null || echo "0.85"
}

show_options() {
  local action
  # Ordered least-to-most destructive: the three read-only actions first, then
  # favourites, then the two that delete things. Delete last so a stray Enter on
  # a freshly-opened menu cannot wipe an entry.
  action="$(printf 'Image History\nOCR Scan Image\nQR Decode Image\nManage Favorites\nClear History\nDelete\n' | run_rofi "Options")"

  [[ -z "$action" ]] && return
  handle_special_commands "$action"

  case "$action" in
    "Image History") exec "$0" image-history ;;
    # Region-select OCR, the same path as Super+O: freeze the screen with
    # hyprpicker, drag a region, tesseract it to the clipboard. rofi has already
    # exited by the time this runs (the command substitution above returned), so
    # the picker overlay cannot capture the menu itself.
    # The clipboard-image version is still available as `clipboard-menu.sh scan`.
    "OCR Scan Image")
      # Let the menu finish animating away before the freeze, or it is captured
      # in the region selector. See layer_close_delay() above.
      sleep "$(layer_close_delay)"
      exec "$HOME/.config/hypr/scripts/poc/screenshot.sh" sc
      ;;
    "QR Decode Image") decode_qr ;;
    "Manage Favorites") manage_favorites ;;
    "Clear History") wipe_history ;;
    "Delete") delete_items ;;
    *) notify "Unrecognised Options choice: $action" ;;
  esac
}

case "${1:-}" in
  delete | -d | --delete) delete_items ;;
  favorites | -f | --favorites) view_favorites ;;
  manage-favorites | -mf | --manage-fav) manage_favorites ;;
  wipe | -w | --wipe) wipe_history ;;
  image-history | -i | --image-history)
    CLIPHIST_IMAGE_HISTORY=true show_history
    ;;
  scan | -s | --scan-image) scan_image ;;
  qr | -q | --qr-decode) decode_qr ;;
  options | -o | --options) show_options ;;
  "" | history | -c | --copy) show_history ;;
  *)
    printf 'Usage: %s [history|options|image-history|delete|favorites|manage-favorites|wipe|scan]\n' "$0" >&2
    exit 1
    ;;
esac
