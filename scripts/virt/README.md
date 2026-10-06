# VM Setup Guide — virt-manager / kvm / win11

Running virtual machines on this system: one-time platform setup, then
creating VMs from any ISO.

## Quick start

```bash
./scripts/virt/virt-manager.sh          # 1. one-time platform setup, then re-login
./scripts/virt/kvm.sh iso               # 2. fetch + verify the Arch ISO
./scripts/virt/kvm.sh create            # 3. boot it
```

---

## Step 1 — Platform setup (once)

Installs QEMU/libvirt/virt-manager, adds you to the `libvirt`/`kvm` groups,
starts the default NAT network, and grants libvirt access to ISOs in `$HOME`.
Nothing else in this guide works until this is done.

```bash
./scripts/virt/virt-manager.sh
```

Needs sudo, so run it directly in your terminal where it can prompt you for a
password. When it finishes, **log out and back in** (or `newgrp libvirt`) so
the new group memberships take effect.

Confirm it worked:

```bash
systemctl is-active libvirtd                  # "active"
groups                                        # includes kvm and libvirt
virsh --connect qemu:///system net-list       # "default" network, active
```

## Step 2 — Create a VM

### From the Arch ISO (default) — verification is automatic

```bash
./scripts/virt/kvm.sh iso        # ~1.5GB download to ~/Downloads
```

**Nothing to verify by hand here.** `kvm.sh iso` fetches Arch's official
`b2sums.txt` and checks the ISO against it, refusing to continue if the hash
doesn't match. It's safe to re-run: an existing file that still matches the
current release is reused instead of re-downloaded.

That proves the file isn't corrupt or truncated (*integrity*). If you also
want to prove it genuinely came from Arch and not a hijacked mirror
(*authenticity*), check the detached signature — `pacman-key` validates it
against the Arch developer keys already in your keyring:

```bash
cd ~/Downloads
curl -LO https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso.sig
pacman-key -v archlinux-x86_64.iso.sig      # want: "Good signature from ..."
```

Then boot it:

```bash
./scripts/virt/kvm.sh create     # boots VM "archtest", opens virt-viewer
```

Defaults: 4G RAM, 4 vCPUs, 40G disk, UEFI + TPM, NAT networking. Override any
of them with `--ram` / `--cpus` / `--disk` (see below).

Unlike `iso`, `create` is not safe to re-run — it fails if a VM with that name
already exists, so `destroy` it first (see step 3) to rebuild from scratch.

### Choosing specs

Every `create` accepts optional spec flags. Leave one out and it keeps its
default. They work with or without an ISO path, in any order:

```bash
./scripts/virt/kvm.sh create --ram 8G --cpus 6 --disk 80
./scripts/virt/kvm.sh create ~/Downloads/other.iso myvm --ram 2G
```

| Flag | Meaning | Default |
|---|---|---|
| `--ram <MB\|nG>` | Memory — `8192` or `8G` both work | `4096` (4G) |
| `--cpus <n>` | vCPU count | `4` |
| `--disk <GB>` | Disk size | `40` |

The disk is qcow2, so `--disk 80` reserves nothing up front — it grows as the
guest actually writes. RAM and vCPUs are the ones to be careful with, since
the VM competes with your desktop for both; check what you have spare with
`nproc` and `free -h` before going much above the defaults.

### From any other ISO — verify it yourself first

There's no cross-distro equivalent of Arch's `b2sums.txt`, so `create` can
only print the ISO's SHA-256; it has no trusted source to check it against and
will boot the image either way. Do the comparison **before** you create the VM:

**1. Get the official hash.** Find the SHA-256 for that exact filename on the
distro's download page, release notes, or a `.sha256`/`CHECKSUM` file next to
the download.

**2. Hash your copy.**

```bash
sha256sum ~/Downloads/bazzite-stable-live-amd64.iso
```

**3. Compare the two strings.** They must match exactly. If they don't,
re-download — a mismatch means a corrupt or tampered file, and neither is
worth installing from.

**4. Optional — check authenticity too.** If the distro publishes a GPG
signature (often `.sig` or `.asc`) plus a signing key, that additionally
proves *who* built the image, not just that it's undamaged:

```bash
gpg --verify bazzite-stable-live-amd64.iso.sig bazzite-stable-live-amd64.iso
```

Once it checks out, create the VM. An optional second argument names it;
without one the name comes from the ISO filename
(`bazzite-stable-live-amd64.iso` → VM `bazzite-stable-live-amd64`):

```bash
./scripts/virt/kvm.sh create ~/Downloads/bazzite-stable-live-amd64.iso
./scripts/virt/kvm.sh create ~/Downloads/bazzite-stable-live-amd64.iso my-bazzite
```

The SHA-256 it prints on the way up is the same value as step 2 — a last
chance to catch a mismatch before the guest boots.

## Step 3 — Manage and delete VMs

List everything you've created, running or stopped:

```bash
virsh --connect qemu:///system list --all
```

Reconnect to a VM's console after closing the viewer window (closing it
leaves the VM running):

```bash
virt-viewer --connect qemu:///system <name>
```

Start a stopped VM, then delete one permanently:

```bash
virsh --connect qemu:///system start <name>
./scripts/virt/kvm.sh destroy                  # deletes "archtest"
./scripts/virt/kvm.sh destroy <name>           # deletes a named VM
```

> **`destroy` does not ask for confirmation** and removes the disk image with
> the VM. Check the name against `virsh list --all` first.

`virt-manager` gives you the same operations in a GUI, and lists every VM in
its sidebar.

---

## Windows 11 guest, untested

A separate track from the disposable VMs above — this one is meant to be kept.
Download the Win11 ISO yourself first ("Download Windows 11 Disk Image" from
https://www.microsoft.com/software-download/windows11), then:

```bash
./scripts/virt/win11.sh drivers                      # virtio-win ISO, ~700MB, cached
./scripts/virt/win11.sh create ~/Downloads/win11.iso
```

Specs: 8G RAM, 6 vCPUs, 64G virtio disk, UEFI + TPM 2.0 (both required by
Windows 11).

During Windows setup:

1. **No disk shown?** Load driver → Browse → virtio-win CD → `amd64\w11`
   (viostor). The virtio disk then appears.
2. **Network required at OOBE?** Load `NetKVM\w11\amd64` the same way, or
   press Shift+F10 and run `OOBE\BYPASSNRO` to skip.
3. **After first boot**, run `virtio-win-gt-x64.msi` from the virtio-win CD
   for the full driver set and guest agent — display resize, clipboard
   sharing, ballooning.
4. Run Windows Update once, then it's ready.

```bash
./scripts/virt/win11.sh destroy    # deletes the VM and its 64G disk (asks first)
./scripts/virt/win11.sh destroy --yes   # skip the confirmation
```

Same warning as above, and it matters more here: this disk isn't throwaway.

---

## Reference

### What each script does

| Script | Purpose |
|---|---|
| `scripts/virt/virt-manager.sh` | The platform — packages, groups, NAT network, ACLs. Run once. |
| `scripts/virt/kvm.sh` | Create/destroy VMs from any ISO. Defaults to a disposable Arch VM. |
| `scripts/virt/win11.sh` | A Windows 11 guest with virtio drivers and TPM. |

`kvm.sh setup` delegates to `virt-manager.sh` rather than duplicating it, so
there's one source of truth for the platform install.

### Testing this repo's installer

The `archtest` VM exists for exactly this — a clean Arch system to run
`install.sh` against without touching your real machine:

```bash
pacman -Sy git
git clone <your auchlinux remote>
cd auchlinux
./install.sh
```

### Bridged networking (optional, rarely needed)

**The default (NAT) — what you already have.** Your VM sits behind the host
the way your devices sit behind a home router. libvirt hands it a private
address on its own little network (`192.168.122.x`), and traffic to the
outside gets translated through the host's connection.

- The VM can reach the internet and your LAN fine.
- Nothing else on your network can reach *in* to the VM. To your router, the
  VM doesn't exist — only the host does.

**A bridge — the alternative.** The VM is attached directly to your physical
network instead, as if it were another machine plugged into your router. It
gets an address from your router in the same range as your laptop and phone
(`192.168.1.x`), and other devices can connect to it directly.

**Which do you want?** NAT, almost certainly. Browsing, updates, package
installs, and testing an installer all work fine behind it. You only need a
bridge when something *outside* the VM has to initiate a connection *to* it —
running a web or game server other machines connect to, sharing files over
SMB, or SSHing into the VM from a different computer.

```bash
./scripts/virt/virt-manager.sh --bridge <iface>    # e.g. enp3s0
```

`<iface>` is the network interface carrying your connection — find it with
`ip -br link show` (Ethernet names usually start with `en`, Wi-Fi with `wl`).

Two catches:

- **Wired only.** A Wi-Fi access point only forwards traffic for the single
  MAC address it authenticated when your machine joined. A bridged VM has its
  own MAC, so the AP silently drops its frames. This isn't a configuration
  problem — 802.11 just doesn't carry multiple MACs behind one station.
  *This machine currently has no Ethernet port in use (`wlo1` is Wi-Fi), so
  `--bridge` isn't usable here.*
- **Brief outage.** Your connection drops for a moment while the uplink is
  moved onto the bridge.

Running it defines a libvirt network called `host-bridge`. Existing VMs stay
on NAT — to move one over, open its hardware settings in `virt-manager` and
change the NIC source to the `host-bridge` network.

### Why ISOs in `$HOME` used to fail

`qemu:///system` runs guests as the unprivileged `libvirt-qemu` user. Home
directories are typically `700`/`750`/`770`, so that user can't traverse into
`$HOME` to reach an ISO in `~/Downloads` — libvirt chowns the file and still
fails with `Permission denied`.

Step 8 of `virt-manager.sh` fixes this automatically with an execute-only
(traverse, not read or list) ACL on `$HOME`. Nothing to do manually.



# Extra Details

## 🖥️ Virt-Manager / QEMU / KVM

One-shot setup script: [`scripts/virt/virt-manager.sh`](scripts/virt/virt-manager.sh). Standalone (like `steam.sh`), uses the repo's info/ok/warn helper style, `set -euo pipefail`, refuses to run as root, calls sudo itself.

**What it does (default run — safe NAT):**
1. **Pre-flight** — checks `/proc/cpuinfo` for `vmx`/`svm` (host confirmed **AMD-V / svm**, `/dev/kvm` live, kvm modules loaded); warns if BIOS virt is off but continues.
2. **Installs** — `qemu-full`, `libvirt`, `virt-manager`, `virt-viewer`, `edk2-ovmf` (UEFI), `swtpm` (TPM 2.0 for Win11), `dnsmasq`, `iptables-nft` (swaps legacy iptables), `dmidecode`, `bridge-utils`, `openbsd-netcat`.
3. **Groups** — `usermod -aG libvirt,kvm $USER` (effective after relogin).
4. **Socket perms** — sets `unix_sock_group="libvirt"` + `unix_sock_rw_perms="0770"` in `/etc/libvirt/libvirtd.conf` → passwordless for the libvirt group.
5. **Daemon** — `systemctl enable --now libvirtd.service` (+ `virtlogd.socket`).
6. **Default NAT network** — defines (if missing), autostarts, and starts `default` so VMs get internet out of the box.
7. **Default URI** — writes `uri_default = "qemu:///system"` to `~/.config/libvirt/libvirt.conf`.

**Optional `--bridge <iface>`** — builds a NetworkManager `br0` bridge enslaving the given wired interface and defines a libvirt network `host-bridge` (forward mode=bridge) for near-native LAN access. Heavily warned: **wired only** (no Wi-Fi), and briefly drops connectivity while the uplink moves onto the bridge. Skipped gracefully if nmcli/interface missing.

**Usage:** `./scripts/virt/virt-manager.sh` (then log out/in, launch `virt-manager`). For Win11 guests: pick OVMF UEFI firmware + add an emulated swtpm TPM 2.0 device.

**Not yet run end-to-end**: no sudo in this session, so the stack isn't installed here — script syntax (`bash -n`), `--help`, and arg-guards all verified; host is confirmed KVM-capable.