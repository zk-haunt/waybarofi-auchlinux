#!/usr/bin/env bash

set -euo pipefail

SNAPSHOT_DIR="$HOME/.cache/snapshots"
mkdir -p "$SNAPSHOT_DIR"

# Derive the repo from this script's own location ($REPO/scripts/backup-config.sh)
# rather than hardcoding a path. The old hardcoded /home/newpr/auchlinux silently
# skipped the repo half of every snapshot for any other user.
REPO_DIR="$(cd -- "$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")/.." && pwd)"

# Snapshots are extracted with `tar -xzf -C /`, so the paths *inside* the tarball
# have to match the real home they will be restored into. Build them from $HOME
# instead of a literal username, or a restore lands in some other user's home.
REL_HOME="${HOME#/}"          # onmeds   -> home/onmeds
TAR_ROOT="${REL_HOME%%/*}"    # home/onmeds -> home  (root -> root)

get_snapshots() {
  find "$SNAPSHOT_DIR" -maxdepth 1 -name "*.tar.gz" -printf "%T@ %p\n" | sort -n -r | awk '{print $2}'
}

list_snapshots() {
  echo "Available Snapshots:"
  echo "--------------------"
  local i=1
  local snapshots=($(get_snapshots))
  for snap in "${snapshots[@]}"; do
    local size
    size=$(du -sh "$snap" | awk '{print $1}')
    local date
    date=$(date -r "$snap" "+%Y-%m-%d %H:%M:%S")
    printf "%2d) %-45s [Size: %-6s] [Date: %s]\n" "$i" "$(basename "$snap")" "$size" "$date"
    ((i++))
  done
  if [[ ${#snapshots[@]} -eq 0 ]]; then
    echo "No snapshots found."
  fi
}

create_snapshot() {
  local prefix="${1:-snapshot}"
  local timestamp
  timestamp=$(date +'%Y-%m-%d_%H-%M-%S')
  local filename="${prefix}_${timestamp}.tar.gz"
  local filepath="$SNAPSHOT_DIR/$filename"
  
  echo "Creating snapshot of configurations..."
  
  local TEMP_DIR
  TEMP_DIR=$(mktemp -d)
  
  mkdir -p "$TEMP_DIR/$REL_HOME/.config"
  mkdir -p "$TEMP_DIR/$REL_HOME/$(basename "$REPO_DIR")/config"
  
  # Sync configs excluding large cached folders
  rsync --archive \
    --exclude="BraveSoftware" \
    --exclude="chromium" \
    --exclude="google-chrome" \
    --exclude="zen" \
    --exclude="spotify" \
    --exclude="discord" \
    --exclude="slack" \
    --exclude="Code - OSS" \
    --exclude="Code" \
    --exclude="VSCodium" \
    --exclude="*.bak-*" \
    "$HOME/.config/" "$TEMP_DIR/$REL_HOME/.config/"

  if [[ -d "$REPO_DIR/config" ]]; then
    rsync --archive "$REPO_DIR/config/" "$TEMP_DIR/$REL_HOME/$(basename "$REPO_DIR")/config/"
  fi

  tar -czf "$filepath" -C "$TEMP_DIR" "$TAR_ROOT"
  rm -rf "$TEMP_DIR"
  
  local size
  size=$(du -sh "$filepath" | awk '{print $1}')
  
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Backup Utility" "Snapshot Created" "Saved $(basename "$filepath") ($size)"
  fi
  echo "Snapshot successfully created: $filepath ($size)"
}

restore_snapshot() {
  local target="${1:-}"
  local snapshots=($(get_snapshots))
  
  if [[ ${#snapshots[@]} -eq 0 ]]; then
    echo "No snapshots available to restore."
    exit 1
  fi
  
  local selected=""
  if [[ -z "$target" ]]; then
    # Interactive selection
    if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]] && command -v rofi >/dev/null 2>&1; then
      # Rofi interactive selection
      local rofi_opts=()
      local i=1
      for snap in "${snapshots[@]}"; do
        local size
        size=$(du -sh "$snap" | awk '{print $1}')
        local date
        date=$(date -r "$snap" "+%Y-%m-%d %H:%M:%S")
        rofi_opts+=("$i) $(basename "$snap") ($size | $date)")
        ((i++))
      done
      
      local theme="$HOME/.config/rofi/powermenu/style.rasi"
      local choice
      choice="$(printf "%s\n" "${rofi_opts[@]}" | rofi -dmenu -i -no-custom -p "Restore" -theme "$theme" -theme-str "listview { lines: ${#snapshots[@]}; }")"
      [[ -z "$choice" ]] && exit 0
      
      # Extract index
      local idx
      idx=$(echo "$choice" | awk -F')' '{print $1}' | tr -d ' ')
      selected="${snapshots[$((idx-1))]}"
    else
      # Terminal interactive selection
      list_snapshots
      echo ""
      read -p "Enter snapshot number to restore (or q to quit): " choice
      if [[ "$choice" == "q" || -z "$choice" ]]; then
        exit 0
      fi
      if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ${#snapshots[@]} )); then
        echo "Invalid selection."
        exit 1
      fi
      selected="${snapshots[$((choice-1))]}"
    fi
  else
    # Check if target is a number (index)
    if [[ "$target" =~ ^[0-9]+$ ]]; then
      local idx="$target"
      if (( idx < 1 || idx > ${#snapshots[@]} )); then
        echo "Invalid index $idx. Only ${#snapshots[@]} snapshots available."
        exit 1
      fi
      selected="${snapshots[$((idx-1))]}"
    else
      # Target is a filename
      if [[ -f "$target" ]]; then
        selected="$target"
      elif [[ -f "$SNAPSHOT_DIR/$target" ]]; then
        selected="$SNAPSHOT_DIR/$target"
      else
        echo "Snapshot file not found: $target"
        exit 1
      fi
    fi
  fi
  
  if [[ -n "$selected" ]]; then
    # Double check confirmation
    local confirm_restore=false
    if [[ -n "${WAYLAND_DISPLAY:-}" || -n "${DISPLAY:-}" ]] && command -v rofi >/dev/null 2>&1; then
      local theme="$HOME/.config/rofi/powermenu/style.rasi"
      local confirm_choice
      confirm_choice="$(printf 'No\nYes\n' | rofi -dmenu -i -no-custom -p "Restore $(basename "$selected")?" -theme "$theme" -theme-str "listview { lines: 2; }")"
      if [[ "$confirm_choice" == "Yes" ]]; then
        confirm_restore=true
      fi
    else
      read -p "Are you sure you want to restore $(basename "$selected")? [y/N]: " yn
      if [[ "$yn" =~ ^[yY]$ ]]; then
        confirm_restore=true
      fi
    fi
    
    if [[ "$confirm_restore" = true ]]; then
      # 1. Create a safety snapshot of current state
      echo "Taking safety backup of current state..."
      create_snapshot "safety_before_restore"
      
      # 2. Extract snapshot relative to /
      echo "Restoring snapshot $(basename "$selected")..."
      tar -xzf "$selected" -C /
      
      # 3. Reload config if running
      if pgrep -x "Hyprland" > /dev/null; then
        hyprctl reload || true
      fi
      
      if command -v notify-send >/dev/null 2>&1; then
        notify-send -a "Backup Utility" "Restore Complete" "Successfully restored config from $(basename "$selected")"
      fi
      echo "Restore complete!"
    else
      echo "Restore cancelled."
    fi
  fi
}

# Command dispatcher
case "${1:-}" in
  create)
    create_snapshot
    ;;
  --list|-l)
    list_snapshots
    ;;
  --restore|-r)
    restore_snapshot "${2:-}"
    ;;
  --help|-h)
    printf "Usage: %s {create|--list|--restore [filename/index]}\n" "$0"
    ;;
  *)
    # Default to create
    create_snapshot
    ;;
esac
