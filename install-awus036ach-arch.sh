#!/usr/bin/env bash
# install-awus036ach-arch.sh
# SoCal IT - ALFA AWUS036ACH (RTL8812AU) installer for Arch-based distros (rolling-safe)
#
# Targets:
#   - Arch Linux
#   - CachyOS
#   - Arch Black
#
# Usage:
#   chmod +x install-awus036ach-arch.sh
#   ./install-awus036ach-arch.sh
#
# Author: SoCal IT - https://github.com/socalit

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
require_cmd grep
require_cmd awk
require_cmd sed

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

log "Updating system and installing dependencies..."
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm \
  "${HEADERS_PKG}" \
  base-devel \
  dkms \
  git \
  bc \
  linux-firmware \
  wireless_tools \
  iw \
  usbutils

# Verify headers exist for running kernel
if [[ ! -e "/usr/lib/modules/${KREL}/build" ]]; then
  die "Kernel headers not available for ${KREL}. Ensure ${HEADERS_PKG} is installed and matches your running kernel."
fi
ok "Kernel headers found for ${KREL}"

log "Unloading any currently-loaded 88xxau/8812au modules (best effort)..."
sudo modprobe -r 88XXau 2>/dev/null || true
sudo modprobe -r 8812au 2>/dev/null || true

log "Removing any existing/broken RTL8812AU DKMS packages (best effort)..."
# Remove AUR variants if present (ignore failures)
sudo dkms remove -m rtl8812au -v all --all 2>/dev/null || true
sudo dkms remove -m 8812au -v all --all 2>/dev/null || true

# If user previously installed these, clean them up to prevent conflicts.
# (pacman will just skip if not installed)
sudo pacman -Rns --noconfirm \
  rtl8812au-dkms-git \
  rtl8812au-aircrack-ng-dkms-git \
  rtl88xxau-aircrack-dkms-git \
  rtl88xxau-dkms-git \
  8812au-dkms-git \
  8812au-dkms \
  88xxau-dkms-git \
  88xxau-dkms \
  2>/dev/null || true

log "Cleaning old DKMS source dirs (best effort)..."
sudo rm -rf /usr/src/rtl8812au-* /usr/src/8812au-* 2>/dev/null || true

ok "Pre-clean completed."

# Use a maintained source tree (morrownr-style). The AUR rtl8812au-dkms-git notes it moved to a morrownr 8812au-20210820 tree. (Reference only)
REPO_URL="https://github.com/morrownr/8812au-20210820.git"
WORKDIR="${HOME}/.cache/awus036ach-driver"
SRCDIR="${WORKDIR}/8812au-20210820"

log "Cloning driver source..."
mkdir -p "${WORKDIR}"
if [[ -d "${SRCDIR}/.git" ]]; then
  log "Repo already exists - updating..."
  git -C "${SRCDIR}" fetch --all --prune
  git -C "${SRCDIR}" reset --hard origin/HEAD
else
  rm -rf "${SRCDIR}"
  git clone "${REPO_URL}" "${SRCDIR}"
fi

# Sanity check: ensure the internal headers exist in-tree
if [[ ! -f "${SRCDIR}/include/drv_types.h" ]]; then
  warn "Expected header not found: ${SRCDIR}/include/drv_types.h"
  warn "This indicates the repo layout is not what the build expects."
  die "Driver source tree is missing required headers."
fi
if [[ ! -f "${SRCDIR}/hal/hal_data.h" && ! -f "${SRCDIR}/include/hal_data.h" ]]; then
  warn "Could not find hal_data.h in common locations."
  warn "Continuing anyway - some trees place it differently."
fi

ok "Driver source tree looks sane."

log "Installing driver via upstream install script (DKMS)..."
# Many Realtek trees provide install-driver.sh; use it for correct DKMS wiring.
if [[ ! -x "${SRCDIR}/install-driver.sh" ]]; then
  die "install-driver.sh not found or not executable in ${SRCDIR}"
fi

# Force GCC toolchain for the module build (avoids LLVM=1 clang paths on some rolling kernels)
export CC=gcc
export CXX=g++
export LLVM=0

# Install script typically supports unattended install with sudo inside; we run it with sudo.
# If it prompts about Secure Boot / MOK, follow its instructions.
sudo bash "${SRCDIR}/install-driver.sh"

log "Attempting to load module..."
sudo modprobe 8812au 2>/dev/null || sudo modprobe 88XXau 2>/dev/null || {
  warn "Module load failed. Diagnostics:"
  echo
  echo "== dkms status =="
  dkms status || true
  echo
  echo "== lsusb (look for Realtek 0bda:*) =="
  lsusb || true
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
echo "Next steps (monitor mode):"
echo "  1) Identify the ALFA interface (commonly wlan1):"
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
echo "  - Logs: dmesg | tail -n 160"
echo "  - After kernel updates: reboot (DKMS will rebuild)"
