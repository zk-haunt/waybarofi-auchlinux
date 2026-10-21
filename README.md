# Arch Install Scripts

Minimal **automated Arch Linux installation scripts** using `curl | bash`.

> [!WARNING]
> These scripts will **erase your selected disk** and configure partitions, **LUKS**, and **systemd-boot**.
> Use only if you understand what the script does. **Test in a VM first.**

---

## ✅ What this installs

- Base system (**Zen kernel only**, or **Linux + Zen**)
- Basic **LUKS encryption**
- **systemd + systemd-boot** essential setup
- Networking + user creation + sudo setup

---

## 📦 Available installer

### 1) Run installer directly (Zen/Stable/Both selection is interactive)
```bash
curl -fsSL "https://raw.githubusercontent.com/zk-haunt/auchlinux/main/install.sh?$(date +%s)" | bash
```

### Or edit and run locally

```bash
curl -fsSL "https://raw.githubusercontent.com/zk-haunt/auchlinux/main/install.sh" -o install.sh
chmod +x install.sh
./install.sh
```

---

## 🚀 After install.sh — the desktop

`install.sh` gives you a bootable base system and nothing else: no Hyprland, no
bar, no login screen. These steps build the actual desktop. Run them in order.

### 2) Reboot and clone the repo

```bash
git clone https://github.com/zk-haunt/auchlinux.git ~/auchlinux
```

### 3) Dev toolchains — run this *before* install-packages

```bash
cd ~/auchlinux && ./scripts/dev-utils.sh
./scripts/dev-utils.sh --status       # show what's present, change nothing
```

Installs, in this order: **Rust** (`rustup` from pacman, then
`rustup default stable`), **Go** (pacman), then **Node LTS + npm** via
[nvm](https://github.com/nvm-sh/nvm).

> [!IMPORTANT]
> **Order matters — do this before `install-packages.sh`.** That script builds
> `paru` from source, and paru's PKGBUILD declares `makedepends=('cargo')`. With
> no Rust present, `makepkg` resolves `cargo` by installing the **`rust`**
> package — which then conflicts with `rustup` when you install it later, since
> both provide `rustc`/`cargo`. Installing `rustup` first satisfies `cargo` up
> front and the conflict never arises.

Arch ships **one** package, `rustup`, providing `rustc`/`cargo`/`rustup` — there
is no separate `rust` package to add. It also ships with *no* toolchain
selected, so `cargo` exists but errors until `rustup default stable` runs; this
script does that for you.

Shell wiring lives in `config/zsh/conf.d/50-dev.zsh`, repo-tracked and deployed
by `apply-config.sh`. nvm is **lazy-loaded** there: `.zshenv` sources every
`conf.d/*.zsh` on *every* zsh invocation, and sourcing `nvm.sh` eagerly costs
~200 ms per shell. The first `node`/`npm` call in a shell pays that instead.

Skip this step entirely if you don't write code on the machine — but then let
`makepkg` pull whatever it wants for the paru build.

### 4) Packages + configs

```bash
cd ~/auchlinux && ./install-packages.sh
```

> [!IMPORTANT]
> **`cd` into the repo first.** This script calls `./scripts/apply-config.sh`
> and reads `./scripts/assets/` through **relative** paths. Run it as
> `~/auchlinux/install-packages.sh` from somewhere else and those steps are
> skipped **silently** — you get packages but no configs, and Hyprland comes up
> broken with no hint why.

This installs every package and then runs `apply-config.sh` for you, which
deploys `config/` into `~/.config/`. You do **not** need to run apply-config
separately.

### 5) Shell, fonts, prompt

```bash
./scripts/term-n-font.sh
```

zsh + `ZDOTDIR` + oh-my-zsh + starship + Nerd Fonts. It runs `apply-config.sh`
again internally for `zsh`, `starship`, and `kitty`.

### 6) Login manager

```bash
./scripts/manage-sddm.sh
```

SDDM is **not** handled by `install-packages.sh`. Without this there's no
graphical login — you'd start Hyprland by hand from a TTY.

### 7) Reboot into Hyprland

### 8) First-run theming — required, nothing does it for you

The theme files in `~/.config/` are **symlinks that don't exist until you pick a
theme once**. `apply-config.sh` deliberately skips them (they're state, not
content), so on a fresh install the bar is simply missing. Press these:

| Keybind | Picks |
|---|---|
| `Super + Shift + B` | **Waybar theme** — without this there is no bar at all |
| `Super + Shift + W` | Wallpaper — **put images here first**, see below |
| `Super + Shift + R` (or `Super + Shift + D`) | Rofi theme |
| `Super + Shift + T` | GTK theme |

**Wallpapers are not shipped with this repo.** The picker reads from:

```
~/Pictures/wallpapers/
```

Create it and drop images in before pressing `Super + Shift + W`, or the menu
comes up empty:

```bash
mkdir -p ~/Pictures/wallpapers
```

- Formats: `.jpg` `.jpeg` `.png` `.webp` `.bmp` `.gif`
- Subfolders work — it scans two levels deep (`wallpapers/anime/foo.png` is fine)
- Picking one runs **matugen**, which regenerates the accent colours for waybar,
  rofi, GTK, and kitty from that image. So the wallpaper drives the whole
  palette — it isn't only a background.

Re-running `apply-config.sh` by hand is only needed after you edit something in
`config/`:

```bash
./scripts/apply-config.sh              # everything
./scripts/apply-config.sh hypr waybar  # just these
```

---

## 🛠 Manual upkeep

Three jobs stay manual on purpose — firmware updates, reading Arch news when an
upgrade stops, and the occasional security audit. Steps for each are in
[`manual.md`](manual.md).

---

## 🧩 Optional setups

Independent of each other, run whenever — after the steps above.

| Script | What it sets up |
|---|---|
| [`scripts/harden-dns.sh`](scripts/harden-dns.sh) | Encrypted DNS (DoT + DNSSEC), LLMNR off. Firewall is ufw now, set up by `harden-system.sh` (next row). |
| [`scripts/harden-system.sh`](scripts/harden-system.sh) | System hardening, run by `install-packages.sh` step 9: ufw (default-deny + LocalSend ports), sysctl, coredumps off, removable-media options, unused kernel modules blocked, auditd with a small ruleset, time sync, `/boot` root-only, fwupd metadata refresh, informant news gate. Configs live in [`config/etc/`](config/etc/). Re-run it after editing anything there. |
| [`scripts/zram.sh`](scripts/zram.sh) | Compressed swap in RAM (zram), zswap off. Run by `install-packages.sh` step 11; `--status` / `--revert` to inspect or undo. |
| [`malware-scan.timer`](config/systemd/user/malware-scan.timer) | Weekly CVE + AUR-integrity scan (`scripts/malware-scanner.sh --quiet`); a notification only when something needs attention. Enabled by `apply-config.sh`. |
| [`scripts/virt/virt-manager.sh`](scripts/virt/virt-manager.sh) | QEMU/KVM + virt-manager. `virt/kvm.sh` then builds throwaway VMs. |
| [`scripts/steam/steam.sh`](scripts/steam/steam.sh) | Steam + Vulkan GPU drivers. |
| [`scripts/ollama.sh`](scripts/ollama.sh) | Local LLMs (CPU-only): ollama, off at boot, memory-capped so a long session can't freeze the desktop. Which model to use: [`llm-findings.md`](llm-findings.md). |
| [`scripts/easyeffects/easyeffects.sh`](scripts/easyeffects/easyeffects.sh) | EasyEffects audio EQ + presets. |
| [`scripts/vpn/vpn.sh`](scripts/vpn/README.md) | WireGuard VPN + waybar indicator. |
| [`scripts/vtube/vtube.sh`](scripts/vtube/README.md) | VTube face-tracking pipeline. |

> [!NOTE]
> **Firewall + VMs + LocalSend.** The firewall is **ufw** as of 2026-10-02; the
> two `config/etc/nftables*.conf` rulesets were deleted (they live on in git
> history if ever needed). ufw defaults to deny-inbound, which means
> LocalSend gets no transfers and libvirt guests get no DHCP lease until you
> open them explicitly:
>
> ```
> sudo ufw allow 53317/tcp && sudo ufw allow 53317/udp   # LocalSend
> ```
>
> libvirt guests additionally need `DEFAULT_FORWARD_POLICY="ACCEPT"` in
> `/etc/default/ufw`, since ufw drops FORWARD.
> The same caveat as before carries over: reloading the firewall rebuilds the
> netfilter tables and drops libvirt's own chains, so after `sudo ufw reload`
> (or `disable`/`enable`) run
> `sudo virsh net-destroy default && sudo virsh net-start default` to put them
> back.