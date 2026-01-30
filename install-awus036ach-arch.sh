#!/usr/bin/env bash
# install-awus036ach-arch.sh
# SoCal IT – ALFA AWUS036ACH (RTL8812AU) driver installer for Arch-based Linux (rolling-safe)
#
# Compatible:
#   - Arch Linux
#   - CachyOS
#   - Arch Black
#
# Usage:
#   chmod +x install-awus036ach-arch.sh
#   ./install-awus036ach-arch.sh
#
# Author: SoCal IT – https://github.com/socalit

set -euo pipefail

log() { echo "[*] $*"; }
ok()  { echo "[OK] $*"; }
warn(){ echo "[!] $*"; }
die() { echo "[X] $*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"; }

if [[ "${EUID}" -eq 0 ]]; then
  die "Do not run as root. Run as your normal user (script will use sudo)."
fi

require_cmd sudo
require_cmd pacman
require_cmd uname

KREL="$(uname -r)"
log "SoCal IT – AWUS036ACH (RTL8812AU) installer"
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

log "Updating system and installing dependencies..."
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm "${HEADERS_PKG}" base-devel dkms git

# Verify headers exist for running kernel
if [[ ! -e "/usr/lib/modules/${KREL}/build" ]]; then
  die "Kernel headers not available for ${KREL}. Ensure ${HEADERS_PKG} is installed and matches your running kernel."
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

log "Unloading any currently-loaded 88xxau/8812au modules (best effort)..."
sudo modprobe -r 88XXau 2>/dev/null || true
sudo modprobe -r 8812au 2>/dev/null || true

log "Selecting and installing an RTL8812AU DKMS driver from AUR (rolling-safe + fallback)..."

# On very new kernels, rtl8812au-dkms-git often builds more reliably.
CANDIDATES=(
  "rtl8812au-dkms-git"
  "rtl8812au-aircrack-ng-dkms-git"
)

install_and_build_for_kernel() {
  local pkg="$1"
  local krel="$2"

  log "Trying AUR package: ${pkg}"

  if ! yay -Si "${pkg}" >/dev/null 2>&1; then
    warn "Package not found in AUR: ${pkg}"
    return 1
  fi

  # Install candidate
  yay -S --needed --noconfirm "${pkg}" || return 1

  # Force DKMS build for the running kernel
  log "Forcing DKMS build for running kernel: ${krel}"
  if ! sudo dkms autoinstall -k "${krel}"; then
    warn "DKMS build failed for ${pkg} on kernel ${krel}"
    warn "Removing ${pkg} and trying next candidate..."
    yay -Rns --noconfirm "${pkg}" || true
    return 1
  fi

  ok "DKMS build succeeded for ${pkg} on kernel ${krel}"
  return 0
}

PKG_OK=""
for pkg in "${CANDIDATES[@]}"; do
  if install_and_build_for_kernel "${pkg}" "${KREL}"; then
    PKG_OK="${pkg}"
    break
  fi
done

if [[ -z "${PKG_OK}" ]]; then
  die "All candidate RTL8812AU DKMS drivers failed to build for kernel ${KREL}. Check: /var/lib/dkms/*/*/build/make.log"
fi

log "Using working package: ${PKG_OK}"

log "DKMS status:"
dkms status || true

log "Loading driver module..."
sudo modprobe 8812au 2>/dev/null || sudo modprobe 88XXau 2>/dev/null || {
  warn "Module load failed. Diagnostics:"
  echo
  echo "== dkms status =="
  dkms status || true
  echo
  echo "== recent dmesg (last 160 lines) =="
  dmesg | tail -n 160 || true
  die "Failed to load module (tried 8812au and 88XXau)."
}

ok "Driver module loaded."

log "Detected wireless interfaces:"
iw dev || true

echo
ok "Installation complete."
echo
echo "Next steps (enable monitor mode):"
echo "  1) Identify the ALFA interface (commonly wlan1):"
echo "     iw dev"
echo "  2) Enable monitor mode (replace wlan1 if needed):"
echo "     sudo ip link set wlan1 down"
echo "     sudo iw dev wlan1 set type monitor"
echo "     sudo ip link set wlan1 up"
echo "     iw dev"
echo
echo "Troubleshooting:"
echo "  - After kernel updates: sudo pacman -Syu && reboot"
echo "  - Verify DKMS: dkms status"
echo "  - Check logs: dmesg | tail -n 160"
