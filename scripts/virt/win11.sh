#!/usr/bin/env bash

# Windows 11 KVM guest with best-performance settings (virtio everything),
# following the usual KVM/virt-manager approach:
#   virtio disk + network, host-passthrough CPU, UEFI + TPM 2.0 (Win11
#   requirements), Hyper-V enlightenments (added automatically by
#   virt-install for Windows guests), virtio-win driver ISO attached.
#
# Prereq: run ./kvm.sh once first (installs QEMU/libvirt/virt-manager).
#
# Usage:
#   ./win11.sh drivers                  # download the virtio-win driver ISO
#   ./win11.sh create <win11.iso>       # create & boot the VM from your Win11 ISO
#   ./win11.sh destroy                  # delete the VM and its disk (asks first)
#   ./win11.sh destroy --yes            # same, skipping the confirmation
#
# Get the Win11 ISO ("Download Windows 11 Disk Image") from:
#   https://www.microsoft.com/software-download/windows11

set -euo pipefail

VM_NAME="win11"
VIRTIO_ISO="$HOME/Downloads/virtio-win.iso"
VIRTIO_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/latest-virtio/virtio-win.iso"

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user." >&2
    exit 1
fi

drivers() {
    # No official checksum feed for "latest-virtio" like Arch's b2sums.txt,
    # so just reuse whatever's already there (rm it first to force a refetch).
    if [[ -s $VIRTIO_ISO ]]; then
        echo "Existing virtio-win ISO at $VIRTIO_ISO — skipping download."
        echo "(delete it first if you want to re-fetch the latest drivers.)"
        return 0
    fi
    echo "Downloading virtio-win driver ISO to $VIRTIO_ISO ..."
    curl -L --fail --progress-bar -o "$VIRTIO_ISO" "$VIRTIO_URL"
    echo "Done."
}

create() {
    WIN_ISO="${1:-}"
    [[ -f $WIN_ISO ]] || { echo "Usage: ./win11.sh create <path-to-win11.iso>"; exit 1; }
    [[ -f $VIRTIO_ISO ]] || { echo "No virtio-win ISO — run './win11.sh drivers' first."; exit 1; }

    echo "Creating Windows 11 VM (8G RAM, 6 vCPUs, 64G virtio disk, UEFI+TPM)..."
    virt-install \
        --connect qemu:///system \
        --name "$VM_NAME" \
        --memory 8192 \
        --vcpus 6 \
        --cpu host-passthrough \
        --os-variant win11 \
        --boot uefi \
        --tpm default \
        --disk size=64,format=qcow2,bus=virtio,discard=unmap \
        --disk "path=$VIRTIO_ISO,device=cdrom" \
        --cdrom "$WIN_ISO" \
        --network network=default,model=virtio \
        --graphics spice \
        --video qxl \
        --autoconsole graphical

    cat <<'EOT'

During Windows setup:
  1. When no disk is shown: "Load driver" -> Browse -> virtio-win CD ->
     amd64\w11  (viostor). The virtio disk then appears.
  2. If network is required during OOBE, load NetKVM\w11\amd64 the same way
     (or press Shift+F10 and run:  OOBE\BYPASSNRO  to skip).

After first boot (inside Windows):
  3. Open the virtio-win CD and run  virtio-win-gt-x64.msi  (all drivers +
     guest agent -> proper display resize, clipboard, ballooning).
  4. Windows Update once, then it's ready.

Manage the VM from virt-manager, or:
  virsh --connect qemu:///system start win11 && virt-viewer --connect qemu:///system win11
EOT
}

destroy() {
    local force="${1:-}"

    if ! virsh --connect qemu:///system dominfo "$VM_NAME" &>/dev/null; then
        echo "No VM named '$VM_NAME' is defined — nothing to remove."
        return 0
    fi

    # --remove-all-storage is unrecoverable and a Win11 guest accumulates real
    # state (installed apps, licence activation, documents), unlike the
    # throwaway archtest VM. So require the word "yes" typed in full: a stray
    # Enter or a mistyped `y` must not wipe a 64G disk.
    # Same guard shape as config/hypr/scripts/usb-backup.sh:78-79, which is the
    # repo's existing convention for an irreversible action.
    if [[ "$force" != "--yes" && "$force" != "-y" ]]; then
        echo "About to PERMANENTLY delete VM '$VM_NAME' and all of its storage:"
        echo
        virsh --connect qemu:///system domblklist "$VM_NAME" 2>/dev/null | sed '1,2d' | while read -r target source; do
            [[ -n "${source:-}" && "$source" != "-" ]] || continue
            printf '    %-8s %s' "$target" "$source"
            [[ -f "$source" ]] && printf '  (%s)' "$(du -h "$source" 2>/dev/null | cut -f1)"
            printf '\n'
        done
        echo
        echo "This cannot be undone."
        read -rp 'Type "yes" to confirm: ' reply
        if [[ "$reply" != "yes" ]]; then
            echo "Aborted — nothing was removed."
            return 1
        fi
    fi

    virsh --connect qemu:///system destroy "$VM_NAME" >/dev/null 2>&1 || true
    virsh --connect qemu:///system undefine "$VM_NAME" --nvram --remove-all-storage
    echo "VM '$VM_NAME' and its disk removed."
}

case "${1:-}" in
    drivers) drivers ;;
    create)  shift; create "${1:-}" ;;
    destroy) shift; destroy "${1:-}" ;;
    # Print the header comment block as usage. Driven by "is it a comment?"
    # rather than a hardcoded line range, which silently truncates the moment
    # anyone adds a usage line above.
    *) awk 'NR>2 { if (/^#/) print; else exit }' "$0"; exit 1 ;;
esac
