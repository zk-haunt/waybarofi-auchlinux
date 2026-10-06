#!/usr/bin/env bash
# =============================================================================
#  Virt-Manager / QEMU / KVM setup for Arch Linux (auchlinux)
#
#  Installs the full virtualization stack, adds you to the libvirt/kvm groups,
#  enables the libvirt daemon, and autostarts the default NAT network so VMs
#  get internet out of the box.
#
#  Usage:
#     ./scripts/virt/virt-manager.sh                 # NAT setup (safe, recommended)
#     ./scripts/virt/virt-manager.sh --bridge <if>   # also build a host bridge (br0)
#                                                # over <if> for near-native LAN
#                                                # access (wired only, see notes)
#
#  After it finishes: log out / back in (for the new groups) and launch
#  `virt-manager`. The connection is qemu:///system.
# =============================================================================

set -euo pipefail

# ─── Color helpers (match term-n-font.sh) ────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; RESET='\033[0m'
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()      { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()     { echo -e "${RED}[ERR]${RESET}   $*" >&2; }
section() { echo -e "\n${BOLD}━━━ $* ━━━${RESET}"; }

BRIDGE_IF=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --bridge) BRIDGE_IF="${2:-}"; shift 2 || { err "--bridge needs an interface name"; exit 1; } ;;
        -h|--help) sed -n '2,18p' "$0" | sed 's/^#//'; exit 0 ;;
        *) err "Unknown argument: $1"; exit 1 ;;
    esac
done

[[ $EUID -eq 0 ]] && { err "Run as your normal user (it calls sudo itself), not root."; exit 1; }

# ─── 1. Pre-flight: CPU virtualization ───────────────────────────────────────
section "Checking hardware virtualization"
if grep -qE '\b(vmx|svm)\b' /proc/cpuinfo; then
    grep -q '\bsvm\b' /proc/cpuinfo && ok "AMD-V (svm) supported." || ok "Intel VT-x (vmx) supported."
else
    warn "No vmx/svm flag found. Enable virtualization (SVM/VT-x) in your BIOS/UEFI,"
    warn "otherwise VMs will run slowly under TCG emulation. Continuing anyway."
fi

# ─── 2. Install the stack ────────────────────────────────────────────────────
section "Installing QEMU / libvirt / virt-manager"
PKGS=(
    qemu-full          # full QEMU (all arches, UEFI, audio, usb redirection)
    libvirt            # virtualization API + daemon
    virt-manager       # GUI front-end
    virt-install       # CLI VM creation (used by kvm.sh / win11.sh)
    virt-viewer        # lightweight SPICE/VNC console viewer
    edk2-ovmf          # UEFI firmware for guests (Secure Boot / Windows 11)
    swtpm              # software TPM 2.0 (required by Windows 11 guests)
    dnsmasq            # DHCP/DNS for the default NAT network
    iptables-nft       # libvirt's firewall backend (replaces legacy iptables)
    dmidecode          # host SMBIOS info for libvirt
    bridge-utils       # bridge tooling
    openbsd-netcat     # remote qemu+ssh:// connections
)
info "Packages: ${PKGS[*]}"
# iptables-nft conflicts with the legacy iptables package; --noconfirm accepts the swap.
sudo pacman -S --needed --noconfirm "${PKGS[@]}"
ok "Packages installed."

# ─── 3. Groups ───────────────────────────────────────────────────────────────
section "Adding $USER to libvirt + kvm groups"
sudo usermod -aG libvirt,kvm "$USER"
ok "Added (takes effect after next login)."

# ─── 4. libvirt socket permissions (passwordless for the libvirt group) ──────
section "Configuring libvirt socket access"
CONF=/etc/libvirt/libvirtd.conf
sudo sed -i \
    -e 's/^#\?unix_sock_group = .*/unix_sock_group = "libvirt"/' \
    -e 's/^#\?unix_sock_rw_perms = .*/unix_sock_rw_perms = "0770"/' \
    "$CONF"
ok "Socket group=libvirt, perms=0770."

# ─── 5. Enable the daemon ────────────────────────────────────────────────────
section "Enabling libvirtd"
sudo systemctl enable --now libvirtd.service
# virtlogd is socket-activated by libvirtd; make sure its socket is up.
sudo systemctl enable --now virtlogd.socket 2>/dev/null || true
ok "libvirtd running and enabled at boot."

# ─── 6. Default NAT network ──────────────────────────────────────────────────
section "Starting the default NAT network"
if ! sudo virsh net-info default &>/dev/null; then
    # Some installs ship the XML but don't define it; define from the template.
    TMPL=/etc/libvirt/qemu/networks/default.xml
    [[ -f "$TMPL" ]] && sudo virsh net-define "$TMPL" || warn "default.xml template not found; create a network in virt-manager."
fi
sudo virsh net-autostart default 2>/dev/null || true
sudo virsh net-start default 2>/dev/null || true
sudo virsh net-info default &>/dev/null && ok "Default NAT network active + autostart on." \
    || warn "Could not start 'default' network — add one via virt-manager → Edit → Connection Details → Virtual Networks."

# ─── 7. Default connection URI for the GUI ───────────────────────────────────
section "Setting qemu:///system as the default URI"
mkdir -p "$HOME/.config/libvirt"
LIBVIRT_CONF="$HOME/.config/libvirt/libvirt.conf"
if ! grep -q '^uri_default' "$LIBVIRT_CONF" 2>/dev/null; then
    echo 'uri_default = "qemu:///system"' >> "$LIBVIRT_CONF"
fi
ok "virt-manager will connect to qemu:///system."

# ─── 8. Let libvirt-qemu read ISOs/disks kept under $HOME ────────────────────
section "Granting libvirt-qemu traverse access to \$HOME"
# qemu:///system runs guests as the unprivileged 'libvirt-qemu' user, not you.
# Home directories are typically 700/750/770 (no 'other' bit), so it can't
# even traverse into $HOME to reach an ISO in ~/Downloads — libvirt will chown
# the file to libvirt-qemu but still fail with "Permission denied" opening it.
# An execute-only ACL on $HOME fixes this without making it readable/listable
# by anyone, and without copying multi-GB ISOs into /var/lib/libvirt/images.
if command -v setfacl >/dev/null 2>&1; then
    sudo setfacl -m u:libvirt-qemu:x "$HOME"
    ok "libvirt-qemu can now traverse \$HOME (execute-only, not read/list)."
else
    warn "setfacl not found (pacman -S acl) — libvirt-qemu may fail to open ISOs under \$HOME."
fi

# ─── 9. Optional: host bridge for near-native networking ─────────────────────
if [[ -n "$BRIDGE_IF" ]]; then
    section "Creating host bridge br0 over $BRIDGE_IF"
    warn "Bridging gives VMs their own LAN IP (best performance) but:"
    warn "  • does NOT work on Wi-Fi — use a wired interface only;"
    warn "  • briefly drops connectivity while the uplink moves onto the bridge."
    if ! command -v nmcli >/dev/null; then
        err "nmcli (NetworkManager) not found — skipping bridge. Default NAT still works."
    elif ! ip link show "$BRIDGE_IF" &>/dev/null; then
        err "Interface '$BRIDGE_IF' not found (see: ip -br link). Skipping bridge."
    else
        info "Building NetworkManager bridge br0 and enslaving $BRIDGE_IF…"
        sudo nmcli connection add type bridge ifname br0 con-name br0 stp no
        sudo nmcli connection add type ethernet ifname "$BRIDGE_IF" master br0 con-name "br0-slave-$BRIDGE_IF"
        sudo nmcli connection up br0
        # Expose the bridge to libvirt as a network named "host-bridge".
        BR_XML="$(mktemp)"
        cat > "$BR_XML" <<'EOF'
<network>
  <name>host-bridge</name>
  <forward mode="bridge"/>
  <bridge name="br0"/>
</network>
EOF
        sudo virsh net-define "$BR_XML"
        sudo virsh net-autostart host-bridge
        sudo virsh net-start host-bridge 2>/dev/null || true
        rm -f "$BR_XML"
        ok "Bridge ready. In virt-manager, set the NIC source to network 'host-bridge'."
    fi
fi

# ─── Done ────────────────────────────────────────────────────────────────────
section "Setup complete"
echo
echo "  Next steps:"
echo "    1. Log out and back in (so the libvirt/kvm groups apply)."
echo "    2. Launch:  virt-manager"
echo "    3. New VM → pick an ISO → it'll use the default NAT network for internet."
echo
echo "  Windows 11 guests: choose firmware 'UEFI x86_64 (…OVMF…)' and add a TPM"
echo "  device (Emulated, TPM 2.0, swtpm) in the VM's hardware settings."
echo
[[ -z "$BRIDGE_IF" ]] && info "For a LAN-visible VM later (wired only): ./scripts/virt/virt-manager.sh --bridge <iface>"
