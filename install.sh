#!/usr/bin/env bash
set -euo pipefail

# ✅ Better readability (only works on real TTY, not terminal emulators)
if [[ -c /dev/tty ]]; then
  setfont -d </dev/tty >/dev/tty 2>/dev/null || true
fi

# ============================
# LOG EVERYTHING (scroll later)
# ============================
exec > >(tee -i /tmp/arch-install.log) 2>&1

# ============================
# DEFAULTS (YOU CAN CHANGE)
# ============================
DEFAULT_HOSTNAME="arch"
DEFAULT_USERNAME="user"
DEFAULT_TIMEZONE="Asia/Kolkata"
DEFAULT_LOCALE="en_US.UTF-8"
DEFAULT_KEYMAP="us"

# ✅ DEFAULT PASSWORDS (ENTER = these)
DEFAULT_ROOT_PASSWORD="rooting"
DEFAULT_USER_PASSWORD="usering"
DEFAULT_LUKS_PASSPHRASE="passphrasing"

ESP_SIZE="512MiB"

# Detect CPU Microcode
CPU_VENDOR=$(grep -m1 'vendor_id' /proc/cpuinfo 2>/dev/null | awk '{print $3}' || echo "")
UCODE="amd-ucode" # Default fallback
if [[ "$CPU_VENDOR" == "GenuineIntel" ]]; then
  UCODE="intel-ucode"
fi

# ✅ Core packages (Kernel packages will be appended based on user selection)
PKGS=(
  base base-devel linux-firmware
  sudo git nvim nano
  networkmanager bash-completion
  efibootmgr dosfstools cryptsetup
  "$UCODE"
)

# ============================
# HELPERS
# ============================
info() { echo -e "\n[+] $*\n"; }
warn() { echo -e "\n[!] $*\n"; }
die()  { echo -e "\n[✗] ERROR: $*\n" >&2; exit 1; }

# Make prompts work even in: curl ... | bash
TTY="/dev/tty"

read_tty() {
  local prompt="$1"
  local var
  echo -ne "$prompt" > "$TTY"
  IFS= read -r var < "$TTY"
  echo "$var"
}

read_secret_tty() {
  local prompt="$1"
  local var
  echo -ne "$prompt" > "$TTY"
  stty -echo < "$TTY"
  IFS= read -r var < "$TTY"
  stty echo < "$TTY"
  echo > "$TTY"
  echo "$var"
}

require() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

# ============================
# PRE-FLIGHT CHECKS
# ============================
[[ $EUID -eq 0 ]] || die "Run as root"
[[ -d /sys/firmware/efi ]] || die "Not booted in UEFI mode!"
[[ -c "$TTY" ]] || die "No TTY found. Run from a real terminal."

require lsblk
require parted
require cryptsetup
require pacstrap
require genfstab
require arch-chroot
require sgdisk
require wipefs
require mkfs.fat
require mkfs.ext4
require blkid
require pacman
require pacman-key

# ============================
# TIME SYNC
# ============================
info "Enabling time sync..."
timedatectl set-ntp true || true

# ============================
# PACMAN KEYRING FIX (PGP ERRORS)
# ============================
info "Fixing pacman keyring (prevents PGP signature errors)..."
timedatectl set-ntp true || true

# make pacman faster
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf || true

# clear cache to avoid corrupted packages
rm -rf /var/cache/pacman/pkg/* || true

pacman-key --init
pacman-key --populate archlinux
pacman -Sy --noconfirm archlinux-keyring
pacman-key --populate archlinux

# ============================
# ASK USER CONFIG
# ============================
info "Setup configuration (press ENTER for defaults)"

HOSTNAME="$(read_tty "Hostname [$DEFAULT_HOSTNAME]: ")"
HOSTNAME="${HOSTNAME:-$DEFAULT_HOSTNAME}"

USERNAME="$(read_tty "Username [$DEFAULT_USERNAME]: ")"
USERNAME="${USERNAME:-$DEFAULT_USERNAME}"

TIMEZONE="$(read_tty "Timezone [$DEFAULT_TIMEZONE]: ")"
TIMEZONE="${TIMEZONE:-$DEFAULT_TIMEZONE}"

LOCALE="$(read_tty "Locale [$DEFAULT_LOCALE]: ")"
LOCALE="${LOCALE:-$DEFAULT_LOCALE}"

KEYMAP="$(read_tty "Keymap [$DEFAULT_KEYMAP]: ")"
KEYMAP="${KEYMAP:-$DEFAULT_KEYMAP}"

echo
echo "Choose kernel(s) to install:"
echo "  [1] Zen kernel only (Default)"
echo "  [2] Stable kernel only"
echo "  [3] Both kernels (Zen and Stable)"
KERNEL_CHOICE="$(read_tty "Choice [1/2/3]: ")"
KERNEL_CHOICE="${KERNEL_CHOICE:-1}"

if [[ "$KERNEL_CHOICE" == "2" ]]; then
  PKGS+=(linux)
elif [[ "$KERNEL_CHOICE" == "3" ]]; then
  PKGS+=(linux linux-zen)
else
  PKGS+=(linux-zen)
fi

echo
info "Passwords: press ENTER to use defaults"
echo "  root default = $DEFAULT_ROOT_PASSWORD"
echo "  user default = $DEFAULT_USER_PASSWORD"
echo

# ✅ User password (ENTER => default)
USER_PASSWORD="$(read_secret_tty "User password [default: $DEFAULT_USER_PASSWORD]: ")"
USER_PASSWORD="${USER_PASSWORD:-$DEFAULT_USER_PASSWORD}"

USER_PASSWORD2="$(read_secret_tty "Confirm user password [default: $DEFAULT_USER_PASSWORD]: ")"
USER_PASSWORD2="${USER_PASSWORD2:-$DEFAULT_USER_PASSWORD}"

[[ "$USER_PASSWORD" == "$USER_PASSWORD2" ]] || die "User passwords do not match!"

# ✅ Root password (ALWAYS ASK SEPARATELY)
echo
ROOT_PASSWORD="$(read_secret_tty "Root password [default: $DEFAULT_ROOT_PASSWORD]: ")"
ROOT_PASSWORD="${ROOT_PASSWORD:-$DEFAULT_ROOT_PASSWORD}"

ROOT_PASSWORD2="$(read_secret_tty "Confirm root password [default: $DEFAULT_ROOT_PASSWORD]: ")"
ROOT_PASSWORD2="${ROOT_PASSWORD2:-$DEFAULT_ROOT_PASSWORD}"

[[ "$ROOT_PASSWORD" == "$ROOT_PASSWORD2" ]] || die "Root passwords do not match!"

# ============================
# DISK MENU
# ============================
info "Available disks:"
mapfile -t DISKS < <(lsblk -dpno NAME,SIZE,MODEL | grep -E "/dev/(sd|nvme|vd|mmcblk)" || true)
((${#DISKS[@]})) || die "No disks detected."

for i in "${!DISKS[@]}"; do
  echo "  [$((i+1))] ${DISKS[$i]}"
done

echo
CHOICE="$(read_tty "Choose a disk number to install to: ")"
[[ "$CHOICE" =~ ^[0-9]+$ ]] || die "Invalid choice."
IDX=$((CHOICE-1))
(( IDX >= 0 && IDX < ${#DISKS[@]} )) || die "Choice out of range."

DISK="$(echo "${DISKS[$IDX]}" | awk '{print $1}')"
[[ -b "$DISK" ]] || die "Disk not found: $DISK"

warn "YOU ARE ABOUT TO ERASE EVERYTHING ON: $DISK"
CONFIRM="$(read_tty "Type YES to continue: ")"
[[ "$CONFIRM" == "YES" ]] || die "Aborted."

# rerun safe
umount -R /mnt 2>/dev/null || true
cryptsetup close cryptroot 2>/dev/null || true

# partition naming style
if [[ "$DISK" == *"nvme"* || "$DISK" == *"mmcblk"* ]]; then
  ESP="${DISK}p1"
  ROOT="${DISK}p2"
else
  ESP="${DISK}1"
  ROOT="${DISK}2"
fi

# ============================
# WIPE + PARTITION
# ============================
info "Wiping disk: $DISK"
wipefs -af "$DISK"
sgdisk --zap-all "$DISK"

info "Creating GPT partitions (512MiB EFI + rest root)..."
parted -s "$DISK" mklabel gpt
parted -s "$DISK" mkpart ESP fat32 1MiB "$ESP_SIZE"
parted -s "$DISK" set 1 esp on
parted -s "$DISK" mkpart LUKS_ROOT ext4 "$ESP_SIZE" 100%

info "Disk layout:"
lsblk "$DISK"

# ============================
# FORMAT EFI
# ============================
info "Formatting EFI partition (FAT32)..."
mkfs.fat -F32 "$ESP"

# ============================
# LUKS + ROOT FS (ENTER => DEFAULT PASSPHRASE)
# ============================
info "Setting up LUKS2..."
wipefs -af "$ROOT"

echo
LUKS_PASSPHRASE="$(read_secret_tty "LUKS passphrase [default: $DEFAULT_LUKS_PASSPHRASE]: ")"
LUKS_PASSPHRASE="${LUKS_PASSPHRASE:-$DEFAULT_LUKS_PASSPHRASE}"

LUKS_PASSPHRASE2="$(read_secret_tty "Confirm LUKS passphrase [default: $DEFAULT_LUKS_PASSPHRASE]: ")"
LUKS_PASSPHRASE2="${LUKS_PASSPHRASE2:-$DEFAULT_LUKS_PASSPHRASE}"

[[ "$LUKS_PASSPHRASE" == "$LUKS_PASSPHRASE2" ]] || die "LUKS passphrases do not match!"

# luksFormat + open using stdin
printf "%s" "$LUKS_PASSPHRASE" | cryptsetup luksFormat --type luks2 "$ROOT" -
printf "%s" "$LUKS_PASSPHRASE" | cryptsetup open "$ROOT" cryptroot -
unset LUKS_PASSPHRASE LUKS_PASSPHRASE2

[[ -e /dev/mapper/cryptroot ]] || die "cryptroot mapping not created — encryption step failed!"

info "Formatting root as ext4..."
mkfs.ext4 -F -L ROOT /dev/mapper/cryptroot

# ============================
# MOUNT
# ============================
info "Mounting..."
mount /dev/mapper/cryptroot /mnt
mkdir -p /mnt/boot
# Root-only ESP. Without options, vfat mounts world-readable (fmask/dmask 0022)
# and genfstab below copies whatever is mounted into fstab — which left every
# user able to read systemd-boot's random seed, a hole bootctl itself warns
# about. Mounting 0077 here means fstab is right from the first boot;
# scripts/harden-system.sh only fixed it after the fact (and needed a reboot).
mount -o fmask=0077,dmask=0077 "$ESP" /mnt/boot

# ============================
# INSTALL SYSTEM
# ============================
info "Installing base system..."
pacstrap -K /mnt "${PKGS[@]}"

info "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

# ============================
# CHROOT CONFIG
# ============================
info "Configuring system..."
arch-chroot /mnt /bin/bash -euo pipefail <<EOF
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc

sed -i 's/^#\\($LOCALE\\)/\\1/' /etc/locale.gen
locale-gen
echo "LANG=$LOCALE" > /etc/locale.conf

echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

echo "$HOSTNAME" > /etc/hostname
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
::1         localhost
127.0.1.1   $HOSTNAME.localdomain $HOSTNAME
HOSTS

# ✅ FIXED password setting (safe for ALL characters)
printf '%s:%s\n' root "$ROOT_PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$USERNAME"
printf '%s:%s\n' "$USERNAME" "$USER_PASSWORD" | chpasswd

sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
systemctl enable NetworkManager
EOF

# ============================
# SYSTEMD INITRAMFS + SD-ENCRYPT
# ============================
info "Configuring systemd initramfs (sd-encrypt)..."
arch-chroot /mnt /bin/bash -euo pipefail <<'EOF'
sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect modconf block sd-encrypt filesystems fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P
EOF

# ============================
# SYSTEMD-BOOT
# ============================
info "Installing systemd-boot..."
arch-chroot /mnt bootctl install

LUKS_UUID="$(blkid -s UUID -o value "$ROOT")"
ROOT_UUID="$(blkid -s UUID -o value /dev/mapper/cryptroot)"

info "Writing systemd-boot config..."
DEFAULT_ENTRY="arch-zen.conf"
if [[ "$KERNEL_CHOICE" == "2" ]]; then
  DEFAULT_ENTRY="arch.conf"
fi

cat > /mnt/boot/loader/loader.conf <<EOF
default $DEFAULT_ENTRY
timeout 5
console-mode max
editor no
EOF

# ✅ Entry 1: Zen
if [[ "$KERNEL_CHOICE" == "1" || "$KERNEL_CHOICE" == "3" ]]; then
  cat > /mnt/boot/loader/entries/arch-zen.conf <<EOF
title   Arch Linux (Zen)
linux   /vmlinuz-linux-zen
initrd  /$UCODE.img
initrd  /initramfs-linux-zen.img
options rd.luks.name=$LUKS_UUID=cryptroot root=UUID=$ROOT_UUID rw
EOF
fi

# ✅ Entry 2: Stable
if [[ "$KERNEL_CHOICE" == "2" || "$KERNEL_CHOICE" == "3" ]]; then
  cat > /mnt/boot/loader/entries/arch.conf <<EOF
title   Arch Linux (Stable)
linux   /vmlinuz-linux
initrd  /$UCODE.img
initrd  /initramfs-linux.img
options rd.luks.name=$LUKS_UUID=cryptroot root=UUID=$ROOT_UUID rw
EOF
fi

# ucode fallback
if [[ ! -f "/mnt/boot/$UCODE.img" ]]; then
  warn "$UCODE.img not found → removing it from entries"
  [[ -f /mnt/boot/loader/entries/arch-zen.conf ]] && sed -i "/$UCODE.img/d" /mnt/boot/loader/entries/arch-zen.conf
  [[ -f /mnt/boot/loader/entries/arch.conf ]] && sed -i "/$UCODE.img/d" /mnt/boot/loader/entries/arch.conf
fi

# ============================
# CLEANUP
# ============================
info "Install complete!"
info "Unmounting..."
umount -R /mnt
cryptsetup close cryptroot

info "✅ Done. Reboot now with: reboot"
info "Log saved to: /tmp/arch-install.log"