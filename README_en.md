# Arch Linux "Niri Edition" Installer

An interactive, one-shot installation script for Arch Linux live environments.  
Automatically sets up a Wayland desktop centered around the **[Niri](https://github.com/YaLTeR/niri)** compositor.

---

## Stack

| Category | Software |
|---|---|
| Compositor | Niri |
| Status Bar | Waybar |
| Terminal | foot |
| Launcher | fuzzel |
| Notifications | mako |
| Screen Lock | swaylock |
| File Manager | Thunar (with archive plugin) |
| Login Manager | greetd + tuigreet |
| Browser | Firefox |
| Audio | PipeWire / WirePlumber |
| Network | NetworkManager + nm-applet |
| IME | fcitx5-mozc |
| Japanese Fonts | IPAex / Source Han Sans & Serif JP |
| Monospace Font | JetBrainsMono Nerd Font |
| Swap | zram (50% of RAM, zstd compression) |
| Bootloader | GRUB (UEFI) |
| Filesystem | ext4 |

---

## Prerequisites

- **Arch Linux installation media** (USB, etc.) booted in UEFI mode
- Internet connection (connect manually via `iwctl` before running the script)
- `git` (if not present in the live environment: `pacman -Sy git`)

---

## Usage

```bash
# 1. Connect to the internet via iwctl
# 2. Clone this repository
git clone https://github.com/magicana-j/ore-arch.git
cd ore-arch

# 3. Make executable and run
chmod +x install.sh
./install.sh
```

The script walks through the following steps:

1. **Preflight checks** — UEFI mode, internet connectivity, root privileges
2. **Interactive prompts** — username / hostname / password / target disk
3. **Mirror optimization** — selects the fastest Japanese mirrors via reflector
4. **Partitioning** — GPT with a 512 MB EFI partition and root on the remainder, formatted automatically
5. **pacstrap** — installs all packages with 5 parallel downloads
6. **chroot configuration** — timezone, locale, GRUB, user account, and all dotfiles generated automatically
7. **Unmount** — filesystems are cleanly unmounted on completion

Remove the installation media and reboot when prompted.

---

## Partition Layout

```
/dev/sdX
├── /dev/sdX1   EFI System   512 MB   FAT32
└── /dev/sdX2   root         Remaining  ext4
```

> NVMe and eMMC devices (`/dev/nvme0n1`, `/dev/mmcblk0`) are supported — partition names (`p1`, `p2`) are resolved automatically.

---

## First-Boot Checklist

- [ ] Log in through tuigreet
- [ ] Open `fcitx5-configtool` and add Mozc as an input method
- [ ] Connect to Wi-Fi via nm-applet or `nmtui` in a terminal
- [ ] Run `xdg-user-dirs-update` if needed

---

## Key Bindings (Niri defaults)

| Key | Action |
|---|---|
| `Mod + Return` | Open foot terminal |
| `Mod + D` | Open fuzzel launcher |
| `Mod + Q` | Close focused window |
| `Mod + H/J/K/L` | Move focus (vim-style) |
| `Mod + Shift + H/J/K/L` | Move window |
| `Mod + 1–5` | Switch workspace |
| `Mod + Shift + 1–5` | Move window to workspace |
| `Mod + F` | Maximize column |
| `Mod + Shift + F` | Fullscreen |
| `Mod + Alt + L` | Lock screen (swaylock) |
| `Mod + Shift + E` | Quit Niri |
| `Print` | Screenshot (region select) |

> `Mod` is the Super (Windows) key.

---

## Customization

Package groups are defined as constants at the top of the script and can be edited freely:

```bash
# Example: add extra packages
EXTRA_PKGS="vim neovim htop btop fastfetch git xdg-user-dirs-gtk firefox reflector zram-generator <extra>"
```

All dotfiles are generated via heredocs inside the chroot script:

| Config | Path |
|---|---|
| Niri | `~/.config/niri/config.kdl` |
| Waybar | `~/.config/waybar/config.jsonc` + `style.css` |
| foot | `~/.config/foot/foot.ini` |
| mako | `~/.config/mako/config` |
| swaylock | `~/.config/swaylock/config` |

---

## License

MIT
