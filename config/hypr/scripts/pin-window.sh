#!/usr/bin/env bash
# Pin/unpin the active window. Runs ASYNC (via exec_cmd) so the hyprctl queries
# don't deadlock the compositor thread.
#
# A window must be floating to be pinned, so float it first (only if it isn't
# already — float() is a toggle), then toggle pin. Pinned windows stay visible
# on every workspace.

# -u and pipefail, but NOT -e. `set -e` changes control flow in ways that
# break the `cmd || fallback` idiom these scripts use throughout, and
# they are bound to keys, so a wrong exit turns a cosmetic bug into a
# dead keybind. -u catches typo'd variable names; every top-level
# positional read was audited and guarded with ${N:-} first.
set -uo pipefail

win=$(hyprctl activewindow -j 2>/dev/null)
[ -z "$win" ] && exit 0

floating=$(printf '%s' "$win" | jq -r .floating)
pinned=$(printf '%s' "$win" | jq -r .pinned)

if [ "$pinned" != "true" ] && [ "$floating" != "true" ]; then
    hyprctl dispatch 'hl.dsp.window.float()' >/dev/null 2>&1
fi
hyprctl dispatch 'hl.dsp.window.pin()' >/dev/null 2>&1
