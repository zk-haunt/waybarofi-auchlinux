#!/usr/bin/env bash


# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

# Text goes through cliphist-store-filtered.sh rather than `cliphist store`
# directly, so password-manager copies are never written to the history. See
# that script for why the filter cannot live in cliphist itself.
#
# The pgrep guards match on the FILTER script name now; they previously matched
# "cliphist store", which would still match the old-style process and let a
# second watcher start alongside it.
STORE_TEXT="$HOME/.config/hypr/scripts/cliphist-store-filtered.sh"

if ! pgrep -u "$USER" -f "wl-paste.*--type text.*cliphist-store-filtered" >/dev/null; then
  # Kill any watcher left from the old unfiltered setup, or both would run and
  # the unfiltered one would keep storing secrets.
  pkill -u "$USER" -f "wl-paste.*--type text.*cliphist store" 2>/dev/null
  wl-paste --type text --watch "$STORE_TEXT" >/dev/null 2>&1 &
fi

# Images are not filtered: a password manager does not offer image/* with the
# hint, and screenshots are the whole point of image history.
if ! pgrep -u "$USER" -f "wl-paste.*--type image.*cliphist store" >/dev/null; then
  wl-paste --type image --watch cliphist store >/dev/null 2>&1 &
fi
