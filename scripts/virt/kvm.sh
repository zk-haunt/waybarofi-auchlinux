#!/usr/bin/env bash

# KVM/QEMU + virt-manager setup, plus a throwaway Arch VM for testing the
# auchlinux installer end-to-end.
#
# Usage:
#   ./kvm.sh                     # install & enable the virtualization stack (one-time,
#                                 # delegates to virt-manager.sh — single source of truth)
#   ./kvm.sh iso                 # download + verify the latest Arch ISO (~/Downloads)
#   ./kvm.sh create               # create & boot the "archtest" UEFI VM from the Arch ISO
#   ./kvm.sh create <iso> [name]  # create & boot a VM from ANY other ISO (name is
#                                  # derived from the filename if you don't give one)
#   ./kvm.sh destroy [name]        # delete a VM and its disk (asks first; default: archtest)
#   ./kvm.sh destroy [name] --yes  # same, skipping the confirmation
#
# Optional spec flags for `create` (defaults: 4G RAM, 4 vCPUs, 40G disk).
# They can go before or after the ISO/name arguments:
#   --ram  <MB|nG>   memory, e.g. --ram 8192  or  --ram 8G
#   --cpus <n>       vCPU count, e.g. --cpus 6
#   --disk <GB>      disk size, e.g. --disk 80
#
#   ./kvm.sh create --ram 8G --cpus 6 --disk 80
#   ./kvm.sh create ~/Downloads/other.iso myvm --ram 8G
#
# Inside the archtest VM, test the installer with:
#   pacman -Sy git && git clone <auchlinux remote> && cd auchlinux && ./install.sh

set -euo pipefail

VM_NAME="archtest"
ISO_PATH="$HOME/Downloads/archlinux-x86_64.iso"
MIRROR="https://geo.mirror.pkgbuild.com/iso/latest"

# Defaults when no spec flags are passed.
DEF_RAM=4096      # MB
DEF_CPUS=4
DEF_DISK=40       # GB

if [[ $EUID -eq 0 ]]; then
    echo "Run this as your normal user (it uses sudo where needed)." >&2
    exit 1
fi

setup() {
    # The full stack setup (packages, groups, socket perms, default NAT
    # network, qemu:///system URI, optional --bridge) lives in
    # virt-manager.sh; delegate so the two scripts can't drift apart.
    "$(dirname "$0")/virt-manager.sh"

    echo
    echo "Next, for the throwaway installer-test VM:  ./kvm.sh iso && ./kvm.sh create"
}

iso() {
    mkdir -p "$(dirname "$ISO_PATH")"

    verify() {
        curl -sL --fail "$MIRROR/b2sums.txt" | grep " archlinux-x86_64.iso\$" \
            | (cd "$(dirname "$ISO_PATH")" && b2sum -c -) >/dev/null 2>&1
    }

    if [[ -f "$ISO_PATH" ]] && verify; then
        echo "Existing ISO at $ISO_PATH matches the latest checksum — skipping download."
        return 0
    fi

    echo "Downloading latest Arch ISO to $ISO_PATH ..."
    curl -L --fail --progress-bar -o "$ISO_PATH" "$MIRROR/archlinux-x86_64.iso"

    echo "Verifying checksum..."
    if verify; then
        echo "ISO verified."
    else
        echo "WARNING: could not verify the ISO checksum." >&2
        exit 1
    fi
}

create() {
    local iso="" name=""
    local ram="$DEF_RAM" cpus="$DEF_CPUS" disk="$DEF_DISK"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --ram|--cpus|--disk)
                [[ -n ${2:-} ]] || { echo "$1 needs a value (e.g. $1 8)" >&2; exit 1; }
                case "$1" in
                    --ram)  ram="$2"  ;;
                    --cpus) cpus="$2" ;;
                    --disk) disk="$2" ;;
                esac
                shift 2 ;;
            -*) echo "Unknown option: $1 (see './kvm.sh' for usage)" >&2; exit 1 ;;
            *)
                if   [[ -z $iso  ]]; then iso="$1"
                elif [[ -z $name ]]; then name="$1"
                else echo "Unexpected argument: $1" >&2; exit 1
                fi
                shift ;;
        esac
    done

    # --ram takes plain MB (8192) or a friendlier G suffix (8G).
    [[ $ram =~ ^([0-9]+)[Gg]$ ]] && ram=$(( ${BASH_REMATCH[1]} * 1024 ))

    local spec
    for spec in "ram:$ram" "cpus:$cpus" "disk:$disk"; do
        [[ ${spec#*:} =~ ^[1-9][0-9]*$ ]] \
            || { echo "--${spec%%:*} must be a positive integer (got '${spec#*:}')" >&2; exit 1; }
    done

    iso="${iso:-$ISO_PATH}"
    [[ -f "$iso" ]] || { echo "No ISO at $iso — run './kvm.sh iso' first, or pass a path."; exit 1; }

    local os_variant="generic"
    if [[ "$iso" == "$ISO_PATH" ]]; then
        # Already checksum-verified by `./kvm.sh iso` against Arch's b2sums.txt.
        name="${name:-$VM_NAME}"
        os_variant="archlinux"
    else
        # No universal checksum source for arbitrary distros (every project
        # publishes its own hash file/format) — print the hash so you can
        # compare it by hand against whatever the ISO's project publishes,
        # rather than silently booting something unverified.
        echo "SHA256: $(sha256sum "$iso" | awk '{print $1}')"
        echo "Compare this against the checksum published on the ISO's download page."
        echo
        if [[ -z "$name" ]]; then
            name="$(basename "$iso")"
            name="${name%.*}"
            name="${name//[^a-zA-Z0-9_-]/-}"
        fi
    fi

    echo "Creating UEFI VM '$name' (${ram}MB RAM, $cpus vCPUs, ${disk}G disk) from $(basename "$iso")..."
    virt-install \
        --connect qemu:///system \
        --name "$name" \
        --memory "$ram" \
        --vcpus "$cpus" \
        --cpu host-passthrough \
        --boot uefi \
        --tpm default \
        --disk "size=$disk,format=qcow2,discard=unmap" \
        --cdrom "$iso" \
        --os-variant "$os_variant" \
        --graphics spice \
        --video virtio \
        --network network=default \
        --autoconsole graphical

    echo
    echo "VM '$name' created. Manage it later from virt-manager, or:"
    echo "  virsh --connect qemu:///system start $name && virt-viewer --connect qemu:///system $name"
}

destroy() {
    local name="" force="" arg reply

    # Name and flag in either order, matching `create` above, which already takes
    # its spec flags on either side of the ISO/name arguments.
    for arg in "$@"; do
        case "$arg" in
            --yes|-y) force=1 ;;
            "")       ;;
            *)        name="$arg" ;;
        esac
    done
    name="${name:-$VM_NAME}"

    if ! virsh --connect qemu:///system dominfo "$name" &>/dev/null; then
        echo "No VM named '$name' is defined — nothing to remove."
        return 0
    fi

    # Same typed-"yes" guard as win11.sh:99-114. The default archtest VM genuinely is
    # throwaway, so a prompt looks like pure friction here — but this takes a NAME, so
    # `destroy <name>` reaches any domain on the host, and --remove-all-storage is
    # unrecoverable. The keystroke that earns its place is the one that stops a
    # mistyped name from eating a real VM. Pass --yes in installer-test loops.
    if [[ -z "$force" ]]; then
        echo "About to PERMANENTLY delete VM '$name' and all of its storage:"
        echo
        virsh --connect qemu:///system domblklist "$name" 2>/dev/null | sed '1,2d' | while read -r target source; do
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

    virsh --connect qemu:///system destroy "$name" >/dev/null 2>&1 || true
    virsh --connect qemu:///system undefine "$name" --nvram --remove-all-storage
    echo "VM '$name' and its disk removed."
}

case "${1:-setup}" in
    setup)   setup ;;
    iso)     iso ;;
    create)  shift; create "$@" ;;
    destroy) shift; destroy "$@" ;;
    # Header comment block as usage, matched on "is it a comment?" rather than a
    # hardcoded line range — the range truncates as soon as a usage line is added.
    *) awk 'NR>2 { if (/^#/) print; else exit }' "$0"; exit 1 ;;
esac
