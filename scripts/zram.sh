#!/usr/bin/env bash
# =============================================================================
#  Compressed swap in RAM (zram) for AuchLinux
#
#  Why: this machine ran with no swap at all, and the kernel journal shows five
#  OOM kills between 2026-08-10 and 2026-10-02. At every one, page cache had
#  been squeezed to 1–9 MiB — i.e. every program was re-reading its own code
#  from disk — because with no swap, idle anonymous memory (background tabs,
#  Electron apps) can never leave RAM, so cache is the only thing left to drop.
#  zram gives that idle memory somewhere to go, compressed, without touching the
#  SSD. It will not save a single runaway tab; it absorbs ordinary peaks.
#
#  Installs three files from config/etc/:
#    systemd/zram-generator.conf         /dev/zram0 as swap, zstd, up to 8 GiB
#    sysctl.d/99-vm-zram-parameters.conf  swap eagerly — it is cheap now
#    tmpfiles.d/zswap-off.conf            zswap off (it would double-compress)
#
#  Usage:
#     ./scripts/zram.sh            # apply (re-runs itself with sudo)
#     ./scripts/zram.sh --status   # show swap / zram / zswap state
#     ./scripts/zram.sh --revert   # remove it again
#
#  Idempotent. Also run by install-packages.sh step 11. A changed zram-size in
#  the config takes effect at the next boot, not on a re-run.
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ETC_SRC="$REPO_DIR/config/etc"
FILES=(
    systemd/zram-generator.conf
    sysctl.d/99-vm-zram-parameters.conf
    tmpfiles.d/zswap-off.conf
)

c(){ printf '\033[0;36m[zram]\033[0m %s\n' "$*"; }
ok(){ printf '\033[0;32m[ok]\033[0m   %s\n' "$*"; }
warn(){ printf '\033[1;33m[!]\033[0m    %s\n' "$*"; }

status() {
    echo "swap devices:"; swapon --show 2>/dev/null | sed 's/^/  /' || true
    [[ -n "$(swapon --show --noheadings 2>/dev/null)" ]] || echo "  (none)"
    command -v zramctl >/dev/null && { echo "zram:"; zramctl 2>/dev/null | sed 's/^/  /'; }
    echo "zswap enabled: $(cat /sys/module/zswap/parameters/enabled 2>/dev/null || echo n/a)"
    sysctl vm.swappiness vm.watermark_boost_factor vm.watermark_scale_factor vm.page-cluster
}

case "${1:-apply}" in
    --status) status; exit 0 ;;
    apply|--revert) ;;
    *) echo "Usage: $0 [--status|--revert]" >&2; exit 1 ;;
esac

# Re-exec as root if needed (after --status, which does not need it).
[[ $EUID -eq 0 ]] || exec sudo "$0" "$@"

if [[ "${1:-apply}" == --revert ]]; then
    c "Reverting zram swap..."
    swapoff /dev/zram0 2>/dev/null || true
    systemctl stop systemd-zram-setup@zram0.service 2>/dev/null || true
    for f in "${FILES[@]}"; do rm -f "/etc/$f"; done
    echo Y > /sys/module/zswap/parameters/enabled 2>/dev/null || true
    systemctl daemon-reload
    ok "Removed. The vm.* sysctl values return to defaults at the next boot."
    exit 0
fi

for f in "${FILES[@]}"; do
    [[ -f "$ETC_SRC/$f" ]] || { warn "missing $ETC_SRC/$f — run from a full repo checkout"; exit 1; }
done

pacman -Qq zram-generator &>/dev/null || pacman -S --needed --noconfirm zram-generator

c "Installing config..."
for f in "${FILES[@]}"; do
    install -Dm644 "$ETC_SRC/$f" "/etc/$f"
done

# Apply now as well as at every boot.
systemd-tmpfiles --create /etc/tmpfiles.d/zswap-off.conf
sysctl -q -p /etc/sysctl.d/99-vm-zram-parameters.conf

# daemon-reload re-runs the generator, which creates systemd-zram-setup@zram0
# and dev-zram0.swap; starting the swap unit pulls in the setup service.
systemctl daemon-reload
systemctl start dev-zram0.swap

if swapon --show --noheadings 2>/dev/null | grep -q zram0; then
    ok "zram swap active"
else
    warn "zram0 is not active — check: systemctl status systemd-zram-setup@zram0 dev-zram0.swap"
fi
status
