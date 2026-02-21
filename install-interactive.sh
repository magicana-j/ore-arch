#!/usr/bin/env bash
# =============================================================================
# Arch Linux "Niri + Sway Edition" Installer (Interactive)
# Target: Fresh Arch ISO live environment (UEFI)
# Layout: EFI + root (ext4), no separate /home, zram swap 50%
#
# This version uses interactive menus for keyboard, timezone, and mirror selection.
# =============================================================================

set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
LOCALE="en_US.UTF-8"
PARALLEL_DL=5

# User-selected configuration (set by gather_config)
KEYMAP=""
TIMEZONE=""
MIRROR_COUNTRY=""

# Fonts / IME
FONTS="terminus otf-ipafont adobe-source-han-sans-jp-fonts adobe-source-han-serif-jp-fonts ttf-jetbrains-mono-nerd"
IME_PKGS="fcitx5 fcitx5-mozc fcitx5-gtk fcitx5-qt fcitx5-configtool"

# Desktop stack
NIRI_PKGS="niri xdg-desktop-portal-gnome xwayland-satellite"
SWAY_PKGS="sway swaybg swayidle xdg-desktop-portal-wlr"
SCREENSHOT_PKGS="grim slurp"
WAYLAND_PKGS="wayland wayland-protocols"
BAR_PKGS="waybar"
LAUNCHER_PKGS="fuzzel"
TERM_PKGS="foot"
NOTIFY_PKGS="mako"
LOCK_PKGS="swaylock"
FM_PKGS="thunar thunar-archive-plugin file-roller gvfs"
GREETER_PKGS="greetd greetd-tuigreet"

# Audio / Network / Misc
AUDIO_PKGS="pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber"
NET_PKGS="networkmanager network-manager-applet"
EXTRA_PKGS="vim neovim htop btop fastfetch git xdg-user-dirs-gtk firefox reflector zram-generator"

# Hardware-specific packages (set by detect_hardware function)
GPU_PKGS=""
FIRMWARE_PKGS=""

# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_SRC="${SCRIPT_DIR}/config"
CHROOT_SCRIPT="${SCRIPT_DIR}/chroot-setup-interactive.sh"

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
# 1. INTERACTIVE CONFIGURATION (NEW ORDER)
# ─────────────────────────────────────────────────────────────────────────────
gather_config() {
  info "=== Interactive Configuration ==="
  echo

  # ── 1. Keyboard Layout ─────────────────────────────────────────────────────
  info "Step 1/5: Select keyboard layout"
  local keymaps=(
    "us:US English"
    "uk:UK English"
    "de:German"
    "fr:French"
    "es:Spanish"
    "it:Italian"
    "jp:Japanese"
    "kr:Korean"
    "ru:Russian"
    "cn:Chinese"
  )

  local i=1
  for entry in "${keymaps[@]}"; do
    IFS=':' read -r code desc <<< "$entry"
    printf "  %2d) %-6s  %s\n" "$i" "$code" "$desc"
    ((i++))
  done

  while true; do
    read -rp "Select keyboard layout [1-${#keymaps[@]}]: " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#keymaps[@]} )); then
      IFS=':' read -r KEYMAP _ <<< "${keymaps[$((selection-1))]}"
      break
    fi
    warn "Invalid selection."
  done
  success "Keyboard layout: ${KEYMAP}"
  echo

  # ── 2. Disk Selection ──────────────────────────────────────────────────────
  info "Step 2/5: Select installation disk"
  mapfile -t DISKS < <(lsblk -d -n -o NAME,SIZE,TYPE | awk '$3=="disk" {print "/dev/"$1}')
  
  if [[ ${#DISKS[@]} -eq 0 ]]; then
    die "No disks found."
  fi

  local i=1
  for disk in "${DISKS[@]}"; do
    local size=$(lsblk -d -n -o SIZE "$disk")
    local model=$(lsblk -d -n -o MODEL "$disk" 2>/dev/null || echo "")
    printf "  %d) %-20s %10s  %s\n" "$i" "$disk" "$size" "$model"
    ((i++))
  done

  while true; do
    read -rp "Select disk number [1-${#DISKS[@]}]: " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#DISKS[@]} )); then
      DISK="${DISKS[$((selection-1))]}"
      break
    fi
    warn "Invalid selection."
  done
  success "Installation disk: ${DISK}"
  echo

  # ── 3. Username & Password ─────────────────────────────────────────────────
  info "Step 3/5: Create user account"
  while true; do
    read -rp "Enter username: " USERNAME
    [[ "$USERNAME" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] && break
    warn "Invalid username. Use lowercase letters, digits, _ or - (start with letter or _)."
  done

  while true; do
    read -rsp "Enter password for ${USERNAME}: " USER_PASS; echo
    read -rsp "Confirm password: "               USER_PASS2; echo
    [[ "$USER_PASS" == "$USER_PASS2" ]] && break
    warn "Passwords do not match. Try again."
  done
  success "User account: ${USERNAME}"
  echo

  # ── 4. Timezone Selection ──────────────────────────────────────────────────
  info "Step 4/5: Select timezone"
  
  # List continents/regions
  local regions=(
    "Africa"
    "America"
    "Antarctica"
    "Arctic"
    "Asia"
    "Atlantic"
    "Australia"
    "Europe"
    "Indian"
    "Pacific"
  )

  echo "Select continent/region:"
  local i=1
  for region in "${regions[@]}"; do
    printf "  %2d) %s\n" "$i" "$region"
    ((i++))
  done

  local selected_region
  while true; do
    read -rp "Select region [1-${#regions[@]}]: " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#regions[@]} )); then
      selected_region="${regions[$((selection-1))]}"
      break
    fi
    warn "Invalid selection."
  done

  # List cities in selected region
  mapfile -t cities < <(find /usr/share/zoneinfo/"${selected_region}" -type f -printf "%f\n" 2>/dev/null | sort)
  
  if [[ ${#cities[@]} -eq 0 ]]; then
    die "No cities found in ${selected_region}."
  fi

  echo
  echo "Select city in ${selected_region}:"
  local i=1
  for city in "${cities[@]}"; do
    printf "  %2d) %s\n" "$i" "$city"
    ((i++))
    # Limit display to first 30 cities for readability
    if (( i > 30 )); then
      echo "  ... (${#cities[@]} total cities, showing first 30)"
      break
    fi
  done

  local selected_city
  while true; do
    read -rp "Select city [1-${#cities[@]}]: " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#cities[@]} )); then
      selected_city="${cities[$((selection-1))]}"
      TIMEZONE="${selected_region}/${selected_city}"
      break
    fi
    warn "Invalid selection."
  done
  success "Timezone: ${TIMEZONE}"
  echo

  # ── 5. Hostname ────────────────────────────────────────────────────────────
  info "Step 5/5: Set hostname"
  while true; do
    read -rp "Enter hostname: " HOSTNAME
    [[ "$HOSTNAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9\-]{0,62}$ ]] && break
    warn "Invalid hostname."
  done
  success "Hostname: ${HOSTNAME}"
  echo

  # ── 6. Mirror Country Selection ───────────────────────────────────────────
  info "Bonus: Select mirror country for package downloads"
  local countries=(
    "Japan"
    "United States"
    "Germany"
    "France"
    "United Kingdom"
    "Australia"
    "South Korea"
    "China"
    "Canada"
    "Worldwide"
  )

  local i=1
  for country in "${countries[@]}"; do
    printf "  %2d) %s\n" "$i" "$country"
    ((i++))
  done

  while true; do
    read -rp "Select mirror country [1-${#countries[@]}]: " selection
    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#countries[@]} )); then
      MIRROR_COUNTRY="${countries[$((selection-1))]}"
      break
    fi
    warn "Invalid selection."
  done
  success "Mirror country: ${MIRROR_COUNTRY}"
  echo

  # ── Final Confirmation ─────────────────────────────────────────────────────
  warn "=== CONFIGURATION SUMMARY ==="
  echo "  Keyboard : ${KEYMAP}"
  echo "  Disk     : ${DISK}  (will be WIPED)"
  echo "  Username : ${USERNAME}"
  echo "  Timezone : ${TIMEZONE}"
  echo "  Hostname : ${HOSTNAME}"
  echo "  Mirrors  : ${MIRROR_COUNTRY}"
  echo
  confirm "Proceed? This will DESTROY all data on ${DISK}." || die "Aborted by user."
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. HARDWARE DETECTION (GPU + Firmware)
# ─────────────────────────────────────────────────────────────────────────────
detect_hardware() {
  info "Detecting hardware and selecting drivers..."

  GPU_PKGS=""
  FIRMWARE_PKGS=""
  local gpu_vendors=()
  local needs_firmware=false

  # ── GPU Detection ──────────────────────────────────────────────────────────
  if lspci | grep -iE 'vga|3d|display' | grep -iq 'intel'; then
    info "  Detected Intel GPU"
    gpu_vendors+=("intel")
    GPU_PKGS+=" mesa vulkan-intel intel-media-driver libva-intel-driver"
  fi

  if lspci | grep -iE 'vga|3d|display' | grep -iq 'amd'; then
    info "  Detected AMD GPU"
    gpu_vendors+=("amd")
    GPU_PKGS+=" mesa vulkan-radeon libva-mesa-driver mesa-vdpau xf86-video-amdgpu"
    needs_firmware=true
    info "    → linux-firmware needed (amdgpu)"
  fi

  if lspci | grep -iE 'vga|3d|display' | grep -iq 'nvidia'; then
    info "  Detected NVIDIA GPU"
    gpu_vendors+=("nvidia")
    GPU_PKGS+=" nvidia-open nvidia-utils libva-nvidia-driver"
  fi

  if [[ -z "${GPU_PKGS}" ]]; then
    warn "  No specific GPU detected. Installing generic Mesa drivers."
    GPU_PKGS=" mesa"
  fi

  success "GPU detection complete. Drivers selected:${GPU_PKGS}"

  # ── Network/Wireless Detection ─────────────────────────────────────────────
  info "Detecting network hardware..."
  
  if lspci | grep -iE 'network|wireless|wi-fi|ethernet' | grep -iq 'intel'; then
    info "  Detected Intel network controller"
    needs_firmware=true
    info "    → linux-firmware needed (iwlwifi)"
  fi

  if lspci | grep -iE 'network|wireless|wi-fi' | grep -iq 'realtek'; then
    info "  Detected Realtek wireless controller"
    needs_firmware=true
    info "    → linux-firmware needed (rtw88/rtw89)"
  fi

  if lspci | grep -iE 'network|wireless|wi-fi' | grep -iq 'broadcom'; then
    info "  Detected Broadcom wireless controller"
    needs_firmware=true
    info "    → linux-firmware needed (brcm)"
  fi

  if lspci | grep -iE 'network|wireless|wi-fi' | grep -iq 'qualcomm\|atheros'; then
    info "  Detected Qualcomm/Atheros wireless controller"
    needs_firmware=true
    info "    → linux-firmware needed (ath)"
  fi

  if lspci | grep -iq 'bluetooth' || lsusb 2>/dev/null | grep -iq 'bluetooth'; then
    info "  Detected Bluetooth controller"
    needs_firmware=true
    info "    → linux-firmware needed (bluetooth)"
  fi

  # ── Firmware Decision ──────────────────────────────────────────────────────
  if [[ "$needs_firmware" == true ]]; then
    FIRMWARE_PKGS=" linux-firmware"
    success "Firmware package selected: linux-firmware"
  else
    info "No firmware required for detected hardware (wired-only setup)."
    FIRMWARE_PKGS=""
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. REFLECTOR – OPTIMIZE MIRRORS
# ─────────────────────────────────────────────────────────────────────────────
setup_mirrors() {
  info "Installing reflector and selecting fastest mirrors..."
  pacman -Sy --noconfirm reflector

  local reflector_args=(
    --age 12
    --protocol https
    --sort rate
    --save /etc/pacman.d/mirrorlist
  )

  # Add country filter if not "Worldwide"
  if [[ "${MIRROR_COUNTRY}" != "Worldwide" ]]; then
    reflector_args+=(--country "${MIRROR_COUNTRY}")
  fi

  reflector "${reflector_args[@]}"
  success "Mirror list updated (${MIRROR_COUNTRY})."
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. PARTITION & FORMAT
# ─────────────────────────────────────────────────────────────────────────────
part() {
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
# 5. PACSTRAP
# ─────────────────────────────────────────────────────────────────────────────
install_base() {
  info "Building package list for installation..."
  
  ALL_PKGS="base base-devel linux grub efibootmgr \
    ${FONTS} ${IME_PKGS} \
    ${NIRI_PKGS} ${SWAY_PKGS} ${SCREENSHOT_PKGS} ${WAYLAND_PKGS} \
    ${BAR_PKGS} ${LAUNCHER_PKGS} \
    ${TERM_PKGS} ${NOTIFY_PKGS} ${LOCK_PKGS} ${FM_PKGS} ${GREETER_PKGS} \
    ${AUDIO_PKGS} ${NET_PKGS} ${EXTRA_PKGS} ${GPU_PKGS} ${FIRMWARE_PKGS}"

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
# 6. STAGE FILES INTO CHROOT
# ─────────────────────────────────────────────────────────────────────────────
stage_files() {
  info "Staging chroot script and config files..."

  cp "${CHROOT_SCRIPT}" /mnt/root/chroot-setup.sh
  chmod +x /mnt/root/chroot-setup.sh

  mkdir -p /mnt/root/dotfiles
  cp -r "${CONFIG_SRC}/." /mnt/root/dotfiles/

  cat > /mnt/root/vars.env <<EOF
USERNAME="${USERNAME}"
HOSTNAME="${HOSTNAME}"
USER_PASS="${USER_PASS}"
LOCALE="${LOCALE}"
TIMEZONE="${TIMEZONE}"
KEYMAP="${KEYMAP}"
PARALLEL_DL="${PARALLEL_DL}"
MIRROR_COUNTRY="${MIRROR_COUNTRY}"
EOF
  chmod 600 /mnt/root/vars.env

  success "Files staged under /mnt/root/."
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. RUN CHROOT
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
# 8. FINISH
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
  echo "  Arch Linux Niri + Sway Edition Installer (Interactive)"
  echo "============================================================"
  echo

  preflight
  gather_config      # NEW: Reordered interactive prompts
  detect_hardware
  setup_mirrors      # Uses MIRROR_COUNTRY from gather_config
  partition_disk
  install_base
  stage_files
  run_chroot
  finish
}

main "$@"
