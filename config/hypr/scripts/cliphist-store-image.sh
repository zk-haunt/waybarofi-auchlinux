#!/usr/bin/env bash
# Clipboard-history capture for IMAGES — store, then keep only the newest few.
#
# Used as the `wl-paste --type image --watch` target (see clipboard-watch.sh)
# instead of bare `cliphist store`, which kept every image forever: 104 of them
# by 2026-10-07, ~119 MB of history DB, plus a decoded copy of each in
# $XDG_RUNTIME_DIR/cliphist (94 MB of RAM, since /run is tmpfs) that made the
# Super+Shift+V image grid stall on open.
#
# Text history is untouched: cliphist's own size limit (default 750 entries)
# still governs it, and text goes through cliphist-store-filtered.sh.
#
# Override the count with AUCH_CLIPHIST_KEEP_IMAGES in the environment.

set -uo pipefail

KEEP="${AUCH_CLIPHIST_KEEP_IMAGES:-7}"

cliphist store || exit $?

# `cliphist list` is newest-first; image entries look like
#   704<TAB>[[ binary data 243 KiB png 721x821 ]]
# Everything after the first $KEEP of those goes. `cliphist delete` reads the
# list lines on stdin, and does nothing when the input is empty.
cliphist list \
    | grep -E $'^[0-9]+\t\\[\\[ binary data .*(png|jpe?g|bmp|gif|webp)' \
    | tail -n +"$((KEEP + 1))" \
    | cliphist delete
