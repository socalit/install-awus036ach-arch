#!/usr/bin/env bash
# install-awus036ach-arch.sh
# SoCal IT - ALFA AWUS036ACH (RTL8812AU) installer for Arch-based distros (rolling-safe)
#
# Targets:
#   - Arch Linux
#   - CachyOS
#   - Arch Black
#
# What it does:
#   - Installs matching kernel headers + deps
#   - Installs a DKMS RTL8812AU driver from AUR (prefers aircrack-ng)
#   - Loads the kernel module
#   - Prints basic diagnostics
#
# Usage:
#   chmod +x install-awus036ach-arch.sh
#   ./install-awus036ach-arch.sh
#
# Author: SoCal IT - https://github.com/socalit

set -euo pipefail

log()  { echo "[*] $*"; }
ok()   { echo "[OK] $*"; }
warn() { echo "[!] $*"; }
die()  { echo "[X] $*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

if [[ "${EUID}" -eq 0 ]]; then
  die "Do not run as root. Run as your normal user (script will use sudo)."
fi

require_cmd sudo
require_cmd pacman
require_cmd uname
require_cmd grep
require_cmd mktemp
require_cmd git

KREL="$(uname -r)"
log "SoCal IT - AWUS036ACH (RTL8812AU) installer"
log "Running kernel: ${KREL}"

detect_headers_pkg() {
  local krel="$1"
  if echo "$krel" | grep -qi "cachyos-lts"; then
    echo "linux-cachyos-lts-headers"
  elif echo "$krel" | grep -qi "cachyos"; then
    echo "linux-cachyos-headers"
  elif echo "$krel" | grep -qi "zen"; then
    echo "linux-zen-headers"
  elif echo "$krel" | grep -qi "lts"; then
    echo "linux-lts-headers"
  else
    echo "linux-headers"
  fi
}

HEADERS_PKG="$(detect_headers_pkg "${KREL}")"
log "Kernel headers package: ${HEADERS_PKG}"

log "Installing dependencies..."
# Intentionally not doing pacman -Syu inside an installer.
sudo pacman -S --needed --noconfirm \
  "${HEADERS_PKG}" \
  base-devel \
  dkms \
  git \
  linux-firmware \
  iw \
  usbutils

# Verify headers exist for running kernel
if [[ ! -e "/usr/lib/modules/${KREL}/build" ]]; then
  die "Kernel headers mismatch for ${KREL}. Reboot after kernel updates, then rerun this script."
fi
ok "Kernel headers found for ${KREL}"

ensure_yay() {
  if command -v yay >/dev/null 2>&1; then
    ok "yay is installed."
    return 0
  fi

  warn "yay not found. Installing yay (AUR helper)..."
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  cd "$tmpdir"
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si --noconfirm
  ok "yay installed."
}

ensure_yay

log "Unloading any currently-loaded RTL8812AU modules (best effort)..."
sudo modprobe -r 88XXau 2>/dev/null || true
sudo modprobe -r 8812au 2>/dev/null || true

log "Removing conflicting driver packages (best effort)..."
# If user previously installed one of these, remove them to prevent conflicts.
sudo pacman -Rns --noconfirm \
  rtl8812au-dkms \
  rtl8812au-dkms-git \
  rtl8812au-aircrack-ng-dkms-git \
  rtl8812au-openhd-dkms-git \
  rtl88xxau-aircrack-dkms-git \
  rtl88xxau-dkms-git \
  8812au-dkms-git \
  8812au-dkms \
  88xxau-dkms-git \
  88xxau-dkms \
  2>/dev/null || true

ok "Pre-clean completed."

# Preferred AUR package order (based on what you actually have in yay -Ss output)
# 1) aircrack-ng DKMS (monitor + injection focus) - best default
# 2) generic rtl8812au DKMS
# 3) openhd DKMS (special patches) - last resort
AUR_CANDIDATES=(
  "rtl8812au-aircrack-ng-dkms-git"
  "rtl8812au-dkms-git"
  "rtl8812au-openhd-dkms-git"
)

choose_and_install_aur_pkg() {
  local p
  for p in "${AUR_CANDIDATES[@]}"; do
    if yay -Si "$p" >/dev/null 2>&1; then
      log "Installing AUR package: $p"
      yay -S --needed --noconfirm "$p"
      echo "$p"
      return 0
    fi
  done
  return 1
}

log "Installing RTL8812AU DKMS driver from AUR..."
INSTALLED_PKG="$(choose_and_install_aur_pkg)" || {
  die "No compatible RTL8812AU DKMS AUR package found. Run: yay -Ss 8812au"
}
ok "Installed driver package: ${INSTALLED_PKG}"

log "DKMS status:"
dkms status || true

log "Attempting to load module (8812au / 88XXau)..."
sudo modprobe 8812au 2>/dev/null || sudo modprobe 88XXau 2>/dev/null || {
  warn "Module load failed. Diagnostics:"
  echo
  echo "== dkms status =="
  dkms status || true
  echo
  echo "== lsusb (look for Realtek 0bda:8812 when adapter is plugged in) =="
  lsusb || true
  echo
  echo "== recent kernel log (last 160 lines) =="
  sudo dmesg | tail -n 160 || true
  die "Failed to load module (tried 8812au and 88XXau)."
}

ok "Driver module loaded."

log "Detected wireless interfaces (adapter must be plugged in to appear):"
iw dev || true

echo
ok "Installation complete."
echo
echo "Next steps (when adapter is plugged in):"
echo "  1) Identify the ALFA interface:"
echo "     iw dev"
echo "  2) Enable monitor mode (replace wlan1 if needed):"
echo "     sudo ip link set wlan1 down"
echo "     sudo iw dev wlan1 set type monitor"
echo "     sudo ip link set wlan1 up"
echo "     iw dev"
echo
echo "Troubleshooting:"
echo "  - Verify module: lsmod | grep -E '8812au|88XXau'"
echo "  - Verify DKMS: dkms status"
echo "  - Logs: sudo dmesg | tail -n 160"
echo "  - After kernel updates: reboot (DKMS will rebuild)"
