#!/usr/bin/env bash
# =============================================================================
# Arch Linux "Niri Edition" Installer
# Target: Fresh Arch ISO live environment (UEFI)
# Layout: EFI + root (ext4), no separate /home, zram swap 50%
#
# Repository layout expected:
#   install.sh             ← this script
#   chroot-setup.sh        ← executed inside arch-chroot
#   config/
#     niri/config.kdl
#     sway/config
#     waybar/config.jsonc
#     waybar/style.css
#     foot/foot.ini
#     mako/config
#     swaylock/config
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
LOCALE="en_US.UTF-8"
TIMEZONE="Asia/Tokyo"
KEYMAP="jp106"
PARALLEL_DL=5

# Fonts / IME
FONTS="otf-ipaexfont adobe-source-han-sans-jp-fonts adobe-source-han-serif-jp-fonts ttf-jetbrains-mono-nerd"
IME_PKGS="fcitx5 fcitx5-mozc fcitx5-gtk fcitx5-qt fcitx5-configtool"

# Desktop stack
NIRI_PKGS="niri xdg-desktop-portal-gnome xwayland-satellite"
SWAY_PKGS="sway swaybg swayidle xdg-desktop-portal-wlr autotiling"
GRIMSHOT_PKGS="grim slurp"
WAYLAND_PKGS="wayland wayland-protocols"
BAR_PKGS="waybar"
LAUNCHER_PKGS="fuzzel"
TERM_PKGS="foot"
NOTIFY_PKGS="mako"
LOCK_PKGS="swaylock"
FM_PKGS="thunar thunar-archive-plugin file-roller gvfs"
GREETER_PKGS="greetd greetd-tuigreet"
GPU_PKGS=""

# Audio / Network / Misc
AUDIO_PKGS="pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber"
NET_PKGS="networkmanager network-manager-applet"
EXTRA_PKGS="vim neovim htop btop fastfetch git xdg-user-dirs-gtk firefox reflector zram-generator"

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="${SCRIPT_DIR}/config"
CHROOT_SCRIPT="${SCRIPT_DIR}/chroot-setup.sh"

info()    { echo -e "\033[1;34m[INFO]\033[0m  $*"; }
success() { echo -e "\033[1;32m[OK]\033[0m    $*"; }
warn()    { echo -e "\033[1;33m[WARN]\033[0m  $*"; }
die()     { echo -e "\033[1;31m[ERROR]\033[0m $*" >&2; exit 1; }

confirm() {
  local msg="$1"
  read -rp "${msg} [y/N]: " ans
  [[ "${ans,,}" == "y" ]]
}

# ─────────────────────────────────────────────────────────────────────────────
# 0. PREFLIGHT CHECKS
# ─────────────────────────────────────────────────────────────────────────────
preflight() {
  info "Running preflight checks..."

  [[ -d /sys/firmware/efi/efivars ]]       || die "Not booted in UEFI mode."
  ping -c1 -W3 archlinux.org &>/dev/null   || die "No internet connection. Connect via iwctl first."
  [[ $EUID -eq 0 ]]                         || die "Must run as root."
  [[ -f "${CHROOT_SCRIPT}" ]]               || die "Missing chroot-setup.sh (expected at ${CHROOT_SCRIPT})"

  local required=(
    "niri/config.kdl"
    "sway/config"
    "waybar/config.jsonc"
    "waybar/style.css"
    "foot/foot.ini"
    "mako/config"
    "swaylock/config"
  )
  for f in "${required[@]}"; do
    [[ -f "${CONFIG_SRC}/${f}" ]] || die "Missing config file: config/${f}"
  done

  success "Preflight checks passed."
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. INTERACTIVE CONFIGURATION
# ─────────────────────────────────────────────────────────────────────────────
gather_config() {
  info "Gathering configuration..."

  while true; do
    read -rp "Enter username: " USERNAME
    [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && break
    warn "Invalid username. Use lowercase letters, digits, _ or - (start with letter or _)."
  done

  while true; do
    read -rp "Enter hostname: " HOSTNAME
    [[ "$HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9\-]{0,62}$ ]] && break
    warn "Invalid hostname."
  done

  while true; do
    read -rsp "Enter password for ${USERNAME}: " USER_PASS; echo
    read -rsp "Confirm password: "               USER_PASS2; echo
    [[ "$USER_PASS" == "$USER_PASS2" ]] && break
    warn "Passwords do not match. Try again."
  done

  info "Available disks:"
  lsblk -d -o NAME,SIZE,TYPE | grep disk
  while true; do
    read -rp "Enter target disk (e.g. /dev/sda or /dev/nvme0n1): " DISK
    [[ -b "$DISK" ]] && break
    warn "Device not found: ${DISK}"
  done

  echo
  warn "=== CONFIGURATION SUMMARY ==="
  echo "  Username : ${USERNAME}"
  echo "  Hostname : ${HOSTNAME}"
  echo "  Disk     : ${DISK}  (will be WIPED)"
  echo
  confirm "Proceed? This will DESTROY all data on ${DISK}." || die "Aborted by user."
}

# ─────────────────────────────────────────────────────────────────────────────
# 1b. GPU DETECTION & DRIVER SELECTION
# ─────────────────────────────────────────────────────────────────────────────
detect_gpu() {
  info "Detecting GPU and selecting video drivers..."

  GPU_PKGS=""
  local gpu_vendors=()

  # Detect GPUs via lspci
  if lspci | grep -iE 'vga|3d|display' | grep -iq 'intel'; then
    info "  Detected Intel GPU"
    gpu_vendors+=("intel")
    GPU_PKGS+=" mesa vulkan-intel intel-media-driver libva-intel-driver"
  fi

  if lspci | grep -iE 'vga|3d|display' | grep -iq 'amd'; then
    info "  Detected AMD GPU"
    gpu_vendors+=("amd")
    GPU_PKGS+=" mesa vulkan-radeon libva-mesa-driver mesa-vdpau xf86-video-amdgpu"
  fi

  if lspci | grep -iE 'vga|3d|display' | grep -iq 'nvidia'; then
    info "  Detected NVIDIA GPU"
    gpu_vendors+=("nvidia")
    # Use open kernel modules (nvidia-open) for modern GPUs
    # For older GPUs, user can manually switch to nvidia-dkms after install
    GPU_PKGS+=" nvidia-open nvidia-utils libva-nvidia-driver"
  fi

  # Fallback: if no GPU detected, install generic Mesa
  if [[ -z "${GPU_PKGS}" ]]; then
    warn "  No specific GPU detected. Installing generic Mesa drivers."
    GPU_PKGS=" mesa"
  fi

  success "GPU detection complete. Drivers selected:${GPU_PKGS}"
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. REFLECTOR – OPTIMIZE MIRRORS
# ─────────────────────────────────────────────────────────────────────────────
setup_mirrors() {
  info "Installing reflector and selecting fastest mirrors (JP → Asia → worldwide)..."
  pacman -Sy --noconfirm reflector
  reflector \
    --country Japan \
    --age 12 \
    --protocol https \
    --sort rate \
    --save /etc/pacman.d/mirrorlist
  success "Mirror list updated."
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. PARTITION & FORMAT
# ─────────────────────────────────────────────────────────────────────────────
part() {
  # Resolve partition name: nvme/mmcblk → p suffix, others → no suffix
  local disk="$1" num="$2"
  if [[ "$disk" == *"nvme"* || "$disk" == *"mmcblk"* ]]; then
    echo "${disk}p${num}"
  else
    echo "${disk}${num}"
  fi
}

partition_disk() {
  info "Partitioning ${DISK}..."
  wipefs -af "$DISK"

  parted -s "$DISK" \
    mklabel gpt \
    mkpart EFI  fat32  1MiB   513MiB \
    set 1 esp on \
    mkpart ROOT ext4   513MiB 100%

  EFI_PART=$(part "$DISK" 1)
  ROOT_PART=$(part "$DISK" 2)

  info "Formatting partitions..."
  mkfs.fat -F32 -n EFI  "$EFI_PART"
  mkfs.ext4 -L ROOT      "$ROOT_PART"

  info "Mounting partitions..."
  mount "$ROOT_PART" /mnt
  mkdir -p /mnt/boot/efi
  mount "$EFI_PART"  /mnt/boot/efi

  success "Partitioning complete. EFI=${EFI_PART}, ROOT=${ROOT_PART}"
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. PACSTRAP
# ─────────────────────────────────────────────────────────────────────────────
install_base() {
  info "Building package list for installation..."

  # All packages for pacstrap (GPU_PKGS is set by detect_gpu)
  ALL_PKGS="base base-devel linux linux-firmware grub efibootmgr \
    ${FONTS} ${IME_PKGS} \
    ${NIRI_PKGS} ${SWAY_PKGS} ${GRIMSHOT_PKGS} ${WAYLAND_PKGS} \
    ${BAR_PKGS} ${LAUNCHER_PKGS} \
    ${TERM_PKGS} ${NOTIFY_PKGS} ${LOCK_PKGS} ${FM_PKGS} ${GREETER_PKGS} \
    ${AUDIO_PKGS} ${NET_PKGS} ${EXTRA_PKGS} ${GPU_PKGS}"

  info "Enabling parallel downloads (${PARALLEL_DL}) in live environment..."
  sed -i "s/^#ParallelDownloads.*/ParallelDownloads = ${PARALLEL_DL}/" /etc/pacman.conf

  info "Running pacstrap (this will take a while)..."
  # shellcheck disable=SC2086
  pacstrap /mnt $ALL_PKGS

  info "Generating fstab..."
  genfstab -U /mnt >> /mnt/etc/fstab

  success "Base system installed."
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. STAGE FILES INTO CHROOT
# ─────────────────────────────────────────────────────────────────────────────
stage_files() {
  info "Staging chroot script and config files..."

  # Copy chroot script
  cp "${CHROOT_SCRIPT}" /mnt/root/chroot-setup.sh
  chmod +x /mnt/root/chroot-setup.sh

  # Copy dotfiles
  mkdir -p /mnt/root/dotfiles
  cp -r "${CONFIG_SRC}/." /mnt/root/dotfiles/

  # Write vars.env — sourced by chroot-setup.sh
  cat > /mnt/root/vars.env <<EOF
USERNAME="${USERNAME}"
HOSTNAME="${HOSTNAME}"
USER_PASS="${USER_PASS}"
LOCALE="${LOCALE}"
TIMEZONE="${TIMEZONE}"
KEYMAP="${KEYMAP}"
PARALLEL_DL="${PARALLEL_DL}"
EOF
  chmod 600 /mnt/root/vars.env

  success "Files staged under /mnt/root/."
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. RUN CHROOT
# ─────────────────────────────────────────────────────────────────────────────
run_chroot() {
  info "Entering chroot and running setup..."
  arch-chroot /mnt /root/chroot-setup.sh

  info "Cleaning up staged files..."
  rm -f  /mnt/root/chroot-setup.sh /mnt/root/vars.env
  rm -rf /mnt/root/dotfiles

  success "Chroot configuration done."
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. FINISH
# ─────────────────────────────────────────────────────────────────────────────
finish() {
  info "Unmounting filesystems..."
  umount -R /mnt

  echo
  success "================================================================"
  success " Installation complete!"
  success " Remove the installation media and reboot."
  success "================================================================"
  echo
  info "First boot checklist:"
  echo "  1. Log in as '${USERNAME}' via tuigreet"
  echo "  2. Run 'fcitx5-configtool' to add Mozc input method"
  echo "  3. Run 'nmtui' or use nm-applet to connect to Wi-Fi"
  echo "  4. Run 'xdg-user-dirs-update' if not done automatically"
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────
main() {
  echo "============================================================"
  echo "  Arch Linux Niri Edition Installer"
  echo "============================================================"
  echo

  preflight
  gather_config
  detect_gpu
  setup_mirrors
  partition_disk
  install_base
  stage_files
  run_chroot
  finish
}

main "$@"
