#!/usr/bin/env bash
# Clipboard-history capture filter — drops password-manager copies.
#
# plansecurity.md P7: "Clipboard history: clear on lock / exclude secrets."
#
# The problem: `wl-paste --watch cliphist store` records EVERYTHING, so every
# password copied out of KeePassXC lands in a searchable, on-disk history
# (~/.cache/cliphist/db, default 750 entries). KeePassXC's own
# ClearClipboardTimeout wipes the live clipboard after 10s, but by then cliphist
# has already stored a copy — the timeout does nothing about the history.
#
# The fix: KeePassXC marks its clipboard offers with the MIME type
# `x-kde-passwordManagerHint` (verified present in /usr/bin/keepassxc). This
# wrapper checks for that offer and refuses to store it. cliphist itself has no
# such filter — `cliphist` exposes only store/list/decode/delete/wipe plus size
# limits, so this has to happen at capture time.
#
# Used as the --watch target instead of `cliphist store` directly.

set -uo pipefail

# wl-paste --watch pipes the new clipboard content on stdin, but the MIME list
# has to be asked for separately. --no-newline keeps binary payloads intact.
types="$(wl-paste --list-types 2>/dev/null || true)"

case "$types" in
    *x-kde-passwordManagerHint*)
        # A password manager offered this. Drop it: consume stdin so wl-paste
        # does not see a broken pipe, and store nothing.
        cat >/dev/null
        exit 0
        ;;
esac

exec cliphist store
