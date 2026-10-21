#!/usr/bin/env bash
# =============================================================================
#  Local LLMs with ollama — CPU-only, on demand, memory-capped.
#
#  This laptop's iGPU (Lucienne) has no ROCm support, so models run on the CPU
#  and live in system RAM next to the desktop. Two rules come out of the
#  2026-10-07 benchmark (llm-findings.md):
#
#    On demand, never at boot — run as a boot service it kept a 6 GB model
#      resident and crash-looped. Start it when you want it.
#    Memory-capped — config/etc/systemd/system/ollama.service.d/ caps the
#      runner's prompt cache at 1 GiB (default 8 GiB) and the whole service
#      at 9G, so a long session can't freeze the desktop.
#
#  Usage:   ./scripts/ollama.sh        (as yourself — asks for sudo)
#  Then:    sudo systemctl start ollama
#           ollama run qwen3.5:9b
#           sudo systemctl stop ollama
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DROPIN=systemd/system/ollama.service.d/50-auchlinux-memory.conf

sudo pacman -S --needed --noconfirm ollama

sudo install -Dm644 "$REPO_DIR/config/etc/$DROPIN" "/etc/$DROPIN"
sudo systemctl daemon-reload
sudo systemctl disable ollama >/dev/null 2>&1 || true

# A running service only picks up the new limits on restart.
if systemctl is-active --quiet ollama; then
    sudo systemctl restart ollama
fi

echo "ollama installed, off at boot, memory-capped:"
systemctl show ollama -p MemoryMax -p MemorySwapMax --no-pager | sed 's/^/  /'
echo "  prompt cache: LLAMA_ARG_CACHE_RAM=$(systemctl show ollama -p Environment --value | grep -oE 'LLAMA_ARG_CACHE_RAM=[0-9]+' | cut -d= -f2) MiB"
echo
echo "Use it:  sudo systemctl start ollama && ollama run qwen3.5:9b"
echo "Stop:    sudo systemctl stop ollama"
