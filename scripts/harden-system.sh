#!/usr/bin/env bash
# =============================================================================
#  System hardening for AuchLinux — plansecurity.md P1 (firewall) and P4
#  (sysctl, coredumps, removable media, auditd), plus the cheap fixes from the
#  2026-10-06 Lynis report (time sync, unused kernel modules, audit rules,
#  /boot permissions).
#
#  The config files live in the repo under config/etc/ and are installed to
#  their real /etc paths here. They are NOT handled by apply-config.sh, which
#  only syncs ~/.config — system files need root and must not be rsynced with
#  --delete.
#
#  Usage:   ./scripts/harden-system.sh      (as yourself — it calls sudo)
#
#  Run by install-packages.sh step 9, and safe to run on its own any time:
#  everything is idempotent — re-running re-installs identical files and
#  re-asserts the same ufw rules.
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ETC="$REPO_DIR/config/etc"

BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
info() { echo -e "${BLUE}[+] $*${NC}"; }
warn() { echo -e "${YELLOW}[!] $*${NC}"; }

# Not as root: the informant check below needs the real user, and sudo is
# requested per command anyway.
if [[ $EUID -eq 0 ]]; then
    echo "Run this as yourself, not root — it asks for sudo where needed." >&2
    exit 1
fi

info "Applying system hardening (plansecurity.md P1/P4)..."

# ── sysctl ────────────────────────────────────────────────────────────────
# Kernel/network hardening without swapping kernels. P5 explicitly rejects
# linux-hardened (breaks the v4l2loopback DKMS module and costs gaming FPS), so
# this is where the realistic gain comes from.
if [[ -f "$ETC/sysctl.d/99-hardening.conf" ]]; then
    sudo install -Dm644 "$ETC/sysctl.d/99-hardening.conf" /etc/sysctl.d/99-hardening.conf
    sudo sysctl --system >/dev/null 2>&1 \
        && info "  sysctl: 99-hardening.conf applied" \
        || warn "  sysctl --system reported errors"
fi

# ── coredumps ─────────────────────────────────────────────────────────────
# A core dump can contain anything that was in a process's memory — decrypted
# documents, tokens, and for KeePassXC the unlocked database. Storage=none keeps
# the crash record without keeping the core.
if [[ -f "$ETC/systemd/coredump.conf.d/disable.conf" ]]; then
    sudo install -Dm644 "$ETC/systemd/coredump.conf.d/disable.conf" \
        /etc/systemd/coredump.conf.d/disable.conf
    sudo systemctl daemon-reload
    info "  coredumps: disabled (Storage=none)"
fi

# ── removable media ───────────────────────────────────────────────────────
# nosuid,nodev,noexec for USB sticks and SD cards, so a prepared drive cannot
# carry a setuid binary or a smuggled device node. Deliberately NOT applied to
# /tmp: makepkg has no BUILDDIR here, so noexec on /tmp breaks every AUR build.
if [[ -f "$ETC/udisks2/mount_options.conf" ]]; then
    sudo install -Dm644 "$ETC/udisks2/mount_options.conf" /etc/udisks2/mount_options.conf
    sudo systemctl restart udisks2 2>/dev/null || true
    info "  udisks2: removable media mounted nosuid,nodev,noexec"
fi

# ── kernel modules ────────────────────────────────────────────────────────
# Rare network protocols (auto-loadable by any user via socket()) and FireWire,
# none of which a laptop uses. Reasons per module are in the file.
if [[ -f "$ETC/modprobe.d/50-auchlinux-blacklist.conf" ]]; then
    sudo install -Dm644 "$ETC/modprobe.d/50-auchlinux-blacklist.conf" \
        /etc/modprobe.d/50-auchlinux-blacklist.conf
    info "  modules: sctp, rds, tipc and firewire blocked from loading"
fi

# ── auditd ────────────────────────────────────────────────────────────────
# Enabled AND given rules: with an empty ruleset it ran and recorded nothing
# (Lynis ACCT-9630). The ruleset is deliberately small — see the file.
if pacman -Qq audit &>/dev/null; then
    if [[ -f "$ETC/audit/rules.d/50-auchlinux.rules" ]]; then
        sudo install -Dm640 "$ETC/audit/rules.d/50-auchlinux.rules" \
            /etc/audit/rules.d/50-auchlinux.rules
        sudo mkdir -p /etc/pacman.d/hooks   # watched by the rules, so it must exist
    fi
    sudo systemctl enable --now auditd >/dev/null 2>&1 \
        && info "  auditd: enabled" \
        || warn "  auditd: could not enable"
    # Show auditctl's own error on failure — "failed" alone isn't actionable.
    if _out="$(sudo augenrules --load 2>&1)"; then
        info "  auditd: $(sudo auditctl -l 2>/dev/null | grep -vc '^No rules') rule(s) loaded"
    else
        warn "  auditd: loading rules reported an error:"
        printf '%s\n' "$_out" | tail -5 | sed 's/^/      /'
        echo "      Rules now loaded: $(sudo auditctl -l 2>/dev/null | grep -vc '^No rules') of $(grep -cE '^-[wa] ' "$ETC/audit/rules.d/50-auchlinux.rules")"
    fi
fi

# ── time sync ─────────────────────────────────────────────────────────────
# install.sh only turns NTP on inside the live-USB environment, so an installed
# system had no time sync at all (found 2026-10-06: 22 s behind and drifting;
# Lynis TIME-3104). A wrong clock breaks DNSSEC validation (harden-dns.sh), TLS
# certificate checks and 2FA codes. systemd-timesyncd ships with systemd.
sudo timedatectl set-ntp true \
    && info "  time: NTP sync on (systemd-timesyncd)" \
    || warn "  time: could not enable NTP"

# ── /boot permissions ─────────────────────────────────────────────────────
# systemd-boot keeps a random seed on the ESP, and genfstab writes the vfat
# /boot entry with fmask=0022,dmask=0022 — so every user can read the seed and
# the kernels. bootctl itself calls that a security hole. 0077 makes /boot
# root-only. vfat cannot change its masks on a live remount, hence the
# umount/mount; if /boot is busy the change simply applies at the next boot.
#
# Check the live mount rather than trusting a successful umount/mount: if any
# other mount namespace (a sandboxed service with its own copy of the mount
# table) still holds /boot, the kernel reuses that mount — old masks and all —
# and only a reboot applies the new ones. Seen on this machine 2026-10-06.
boot_masks_now() {
    if findmnt -no OPTIONS /boot 2>/dev/null | grep -q 'fmask=0077'; then
        info "  /boot: root-only (fmask/dmask 0077)"
    else
        info "  /boot: fstab is set to root-only; takes effect at the next reboot"
    fi
}
FSTAB_BOOT_RE='^[^#[:space:]]+[[:space:]]+/boot[[:space:]]+vfat[[:space:]]'
if grep -qE "${FSTAB_BOOT_RE}.*fmask=0022" /etc/fstab; then
    sudo cp -p /etc/fstab /etc/fstab.pre-auchlinux
    sudo sed -i -E "\%${FSTAB_BOOT_RE}% { s/fmask=0022/fmask=0077/; s/dmask=0022/dmask=0077/ }" /etc/fstab
    if ! sudo findmnt --verify --tab-file /etc/fstab >/dev/null 2>&1; then
        sudo cp -p /etc/fstab.pre-auchlinux /etc/fstab
        warn "  /boot: fstab failed verification after the edit — restored, nothing changed"
    else
        sudo systemctl daemon-reload
        if sudo umount /boot 2>/dev/null; then
            if sudo mount /boot; then
                boot_masks_now   # reports what the LIVE mount ended up with
            else
                # Never leave /boot unmounted: a kernel upgrade would then write
                # into the root filesystem's empty /boot directory and the next
                # boot would load a kernel that doesn't match its modules.
                sudo cp -p /etc/fstab.pre-auchlinux /etc/fstab
                sudo systemctl daemon-reload
                sudo mount /boot
                warn "  /boot: remount failed — fstab restored and /boot remounted as before"
            fi
        else
            info "  /boot: fstab updated; /boot is busy, so root-only applies at the next boot"
        fi
    fi
elif grep -qE "${FSTAB_BOOT_RE}.*fmask=0077" /etc/fstab; then
    boot_masks_now
fi

# ── fwupd: firmware metadata ─────────────────────────────────────────────
# The timer only downloads LVFS's public firmware catalogue (hourly check, at
# most one download a day, run as the sandboxed `fwupd` user) and matches it
# against this machine's hardware locally. It never installs anything:
# `fwupdmgr get-updates` lists what's available and `fwupdmgr update` applies
# it, by hand, because BIOS/SSD flashes need AC power and a reboot.
# The extra --no-block start fetches the catalogue now rather than within the
# next 1–2 hours, so get-updates has an answer straight after this script.
if pacman -Qq fwupd &>/dev/null; then
    sudo systemctl enable --now fwupd-refresh.timer >/dev/null 2>&1 \
        && sudo systemctl start --no-block fwupd-refresh.service \
        && info "  fwupd: metadata refresh timer enabled" \
        || warn "  fwupd: could not enable fwupd-refresh.timer"
fi

# ── informant: stay OUT of its group ─────────────────────────────────────
# The package creates an `informant` group that can write /var/lib/informant.dat
# (0664 root:informant). That file is a Python pickle, and the pacman hook loads
# it as root before every upgrade. A pickle can carry code, so group membership
# would let anything running as this user — an npm install script, an editor
# extension — plant one and get root at the next `pacman -Syu`, no password.
# The only gain is running `informant read` without sudo; not worth it.
if pacman -Qq informant &>/dev/null; then
    if [[ " $(id -nG "$USER") " == *" informant "* ]]; then
        warn "  informant: $USER is in the 'informant' group — that is a"
        echo "      passwordless path to root (see the comment above this check)."
        echo "      Remove it: sudo gpasswd -d $USER informant"
    else
        info "  informant: news gate active; read news with: sudo informant read"
    fi
fi

# ── firewall: ufw ─────────────────────────────────────────────────────────
# Replaced the hand-written nftables ruleset on 2026-10-02. ufw's own
# before.rules/before6.rules already cover the carve-outs that ruleset spelled
# out by hand — loopback anti-spoofing, established/related, the ICMPv4 set, the
# full ICMPv6 neighbour-discovery set (without which IPv6 breaks), and the DHCP
# client. The old rulesets were deleted; they are in git history.
#
# Ports opened below are opt-ins, each with a reason. Anything not listed stays
# closed, which is the point.
UFW_ALLOW=(
    "53317/tcp"   # LocalSend — file transfers
    "53317/udp"   # LocalSend — peer discovery. BOTH halves are needed: without
                  # UDP this machine never appears in another device's list.
)
if pacman -Qq ufw &>/dev/null; then
    # Never leave two managers fighting over netfilter.
    sudo systemctl disable --now nftables >/dev/null 2>&1 || true

    sudo ufw --force default deny incoming >/dev/null
    sudo ufw --force default allow outgoing >/dev/null
    for _port in "${UFW_ALLOW[@]}"; do
        info "  ufw: allow $_port"
        sudo ufw allow "$_port" >/dev/null
    done

    # IPV6=yes is the Arch default, but losing it breaks IPv6 neighbour
    # discovery, which looks like "the network is broken" rather than a firewall
    # problem — so assert it rather than assume.
    sudo sed -i 's/^IPV6=.*/IPV6=yes/' /etc/default/ufw 2>/dev/null || true

    # ufw applies its OWN kernel settings (IPT_SYSCTL=/etc/ufw/sysctl.conf)
    # every time it starts — after systemd-sysctl at boot — and that file sets
    # rp_filter=1 (strict) and log_martians=0. So it silently overrode
    # 99-hardening.conf, including the deliberate loose rp_filter=2 that
    # split-tunnel WireGuard needs (found 2026-10-06 via Lynis: live all=1).
    # Everything else in ufw's file repeats ours or the kernel default, so
    # blank it: ufw-init skips an empty IPT_SYSCTL, and 99-hardening.conf
    # becomes the one place kernel settings come from.
    sudo sed -i 's|^IPT_SYSCTL=.*|IPT_SYSCTL=|' /etc/default/ufw 2>/dev/null || true

    sudo systemctl enable --now ufw >/dev/null 2>&1
    sudo ufw --force enable >/dev/null
    # Put our values back over anything ufw applied before IPT_SYSCTL was blanked.
    sudo sysctl --system >/dev/null 2>&1 || true
    info "  ufw: default deny incoming, allow outgoing"
    sudo ufw status verbose 2>/dev/null | sed 's/^/      /'
fi

# NOTE deliberately NOT automated here:
#   AppArmor      — needs a bootloader edit (append to the lsm= line in
#                   /boot/loader/entries/arch-zen.conf, which has none today),
#                   a reboot, then days of complain-mode tuning. plansecurity.md
#                   P3 warns that enforcing blind can break a Hyprland rice.
#   Secure Boot / TPM — P6, deliberately skipped.
#   fwupdmgr update / lynis audit system — interactive and judgement-based.
#                   The fwupd refresh timer above only fetches metadata.
#
# Lynis suggestions deliberately NOT taken (2026-10-06 report), so they are not
# re-litigated: separate /home and /var partitions (needs a reinstall), USB
# storage off (usb-backup.sh needs it), compilers root-only (breaks Rust/Go/node
# work), password ageing and PAM strength rules (single-user machine), a legal
# login banner, remote log host, process accounting, AIDE (a rolling release
# changes files daily; `pacman -Qkk` covers packaged files), core-dump limits in
# limits.conf (systemd-coredump Storage=none already discards them).
