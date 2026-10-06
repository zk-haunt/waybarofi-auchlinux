#!/usr/bin/env bash
# Waybar workspace pill — status + click, for ONE workspace.
#
# Why this exists instead of waybar's built-in `hyprland/workspaces`:
#
# That module hardcodes the LEGACY hyprlang dispatch strings. Verified straight
# out of the binary (`strings $(command -v waybar)`):
#     dispatch workspace
#     dispatch workspace name:
#     dispatch focusworkspaceoncurrentmonitor
# Hyprland 0.56 with a pure-Lua config parses dispatch commands as Lua, so all
# three are rejected — confirmed at the raw socket level, which is what waybar
# actually writes to:
#     dispatch workspace 3
#     -> error: [string "return hl.dispatch(workspace 3)"]:1: ')' expected near '3'
# So clicking ANY workspace pill was a no-op, not just an empty one.
#
# No Lua shim can rescue the built-in either: `hl.dispatch(workspace 3)` can
# never parse, because `f 3` is not valid Lua (only `f "str"` and `f{...}` are).
# waybar 0.15.0-3 is the newest in the repos, so there is no upstream fix to
# wait for. Hence a custom module using the form that does work:
#     hyprctl dispatch "hl.dsp.focus({workspace = N})"
#
# Usage:
#   ws-button.sh status <n>   -> JSON for a waybar custom module
#   ws-button.sh go <n>       -> switch to workspace n (creates it if absent)
#
# Switching to a workspace that does not exist yet is intentional and correct —
# Hyprland creates it on focus, so an empty workspace is reachable.

set -uo pipefail

WAYBAR_SIGNAL=9   # must match "signal" in the custom/ws* modules

cmd="${1:-}"
n="${2:-}"

# Unconditional invocation log. The open question is whether waybar's
# hyprland/workspaces module runs a custom on-click command at all, or only
# honours its built-in tokens ("activate"). This records every call with its raw
# arguments, so "nothing happened" can be told apart from "ran with bad args".
printf '%s cmd=%q n=%q argv=%q\n' "$(date +%T.%3N)" "$cmd" "$n" "$*" \
    >> "${XDG_CACHE_HOME:-$HOME/.cache}/ws-button.log" 2>/dev/null || true
# If waybar did not substitute {name}, $n arrives as the literal "{name}" —
# say so instead of failing silently, since that is the one unknown in this
# approach.
if [[ ! "$n" =~ ^[0-9]+$ ]]; then
    if [[ "$cmd" == "go" ]]; then
        notify-send -u critical "Workspace" "waybar did not substitute the workspace number (got: '${n}')"
    else
        echo '{"text":"?"}'
    fi
    exit 1
fi

case "$cmd" in
  status)
    # One hyprctl call, parsed once: which workspace is active, and which have
    # windows. Keeping it to a single call matters because waybar runs this
    # per-pill on every signal.
    read -r active < <(hyprctl activeworkspace -j 2>/dev/null \
        | python3 -c "import json,sys
try: print(json.load(sys.stdin)['id'])
except Exception: print(0)")
    occupied="$(hyprctl workspaces -j 2>/dev/null \
        | python3 -c "import json,sys
try: print(' '.join(str(w['id']) for w in json.load(sys.stdin) if w['windows']>0))
except Exception: print('')")"

    class="empty"
    tooltip="Workspace $n (empty) — click to switch"
    if [[ "$n" == "$active" ]]; then
        class="active"
        tooltip="Workspace $n (current)"
    elif [[ " $occupied " == *" $n "* ]]; then
        class="occupied"
        tooltip="Workspace $n — has windows"
    fi
    printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$n" "$class" "$tooltip"
    ;;

  go)
    # The Lua dispatch form. Quoted so the braces reach hyprctl intact.
    if ! out="$(hyprctl dispatch "hl.dsp.focus({workspace = $n})" 2>&1)" \
       || [[ "$out" == *rror* ]]; then
        notify-send -u critical "Workspace" "Failed to switch to $n: ${out:-unknown}"
        exit 1
    fi
    # Refresh every pill so the active highlight moves immediately rather than
    # waiting for the next poll interval.
    pkill -RTMIN+$WAYBAR_SIGNAL waybar 2>/dev/null || true
    ;;

  *)
    echo "usage: ws-button.sh {status|go} <workspace-number>" >&2
    exit 1
    ;;
esac
