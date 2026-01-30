#!/usr/bin/env bash
# install-awus036ach-arch.sh
# ALFA AWUS036ACH (RTL8812AU) driver installer for Arch-based Linux (rolling-safe)
#
# Compatible with:
#   - Arch Linux
#   - CachyOS
#   - Arch Black
#
# What it does:
#   - Detects running kernel (uname -r)
#   - Installs matching kernel headers for the running kernel flavor
#   - Installs build deps (base-devel, dkms, git)
#   - Installs RTL8812AU DKMS driver from AUR (prefers aircrack-ng DKMS)
#   - Forces DKMS build for the *running* kernel if missing
#   - Loads driver module (tries 8812au and 88XXau)
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

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

if [[ "${EUID}" -eq 0 ]]; then
  die "Do not run as root. Run as your normal user (script will use sudo)."
fi

require_cmd sudo
require_cmd pacman
require_cmd uname

KREL="$(uname -r)"
log "SoCal IT – AWUS036ACH (RTL8812AU) installer"
log "Running kernel: ${KREL}"

# Detect kernel flavor -> choose headers package dynamically (no hardcoding kernel versions)
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

# Verify headers are present for the running kernel
if [[ ! -e "/usr/lib/modules/${KREL}/build" ]]; then
  die "Kernel headers not available for ${KREL}. Ensure ${HEADERS_PKG} is installed and matches your running kernel."
fi
ok "Kernel headers found for ${KREL}"

# Ensure yay exists (AUR helper)
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

log "Selecting RTL8812AU DKMS driver package from AUR..."
# Prefer aircrack-ng DKMS (monitor mode + injection).
CANDIDATES=(
  "rtl8812au-aircrack-ng-dkms-git"
  "rtl8812au-dkms-git"
)

PKG_FOUND=""
for pkg in "${CANDIDATES[@]}"; do
  if yay -Si "$pkg" >/dev/null 2>&1; then
    PKG_FOUND="$pkg"
    break
  fi
done

if [[ -z "$PKG_FOUND" ]]; then
  die "No supported RTL8812AU DKMS package found in AUR. Try: yay -Ss rtl8812au"
fi

log "Installing AUR package: ${PKG_FOUND}"
yay -S --needed --noconfirm "${PKG_FOUND}"

# Identify DKMS module name + version from dkms status
log "DKMS status:"
DKMS_STATUS="$(dkms status || true)"
echo "${DKMS_STATUS}"

DKMS_MOD="$(echo "${DKMS_STATUS}" | awk -F'/' 'NR==1{print $1}' | tr -d ' ')"
DKMS_VER="$(echo "${DKMS_STATUS}" | awk -F'[,/ ]' 'NR==1{print $2}')"

if [[ -z "${DKMS_MOD}" || -z "${DKMS_VER}" ]]; then
  warn "Could not parse DKMS module name/version. Will still attempt build/load."
else
  log "Detected DKMS module: ${DKMS_MOD}, version: ${DKMS_VER}"
fi

# Force DKMS to build for the *running* kernel if not already present
if ! echo "${DKMS_STATUS}" | grep -q "${KREL}"; then
  warn "DKMS module not built for running kernel ${KREL}. Forcing DKMS build..."
  sudo dkms autoinstall -k "${KREL}" || die "DKMS build failed for ${KREL}. Check: dmesg | tail -n 160"
  ok "DKMS build completed for ${KREL}"
else
  ok "DKMS already shows an install for ${KREL}"
fi

# Confirm a module was installed into the running kernel's module tree
# Common locations for DKMS outputs:
#   /lib/modules/<krel>/updates/dkms/
#   /lib/modules/<krel>/extra/
# We only need to know "something got installed", then modprobe should work.
if [[ ! -d "/lib/modules/${KREL}" ]]; then
  die "Kernel module directory not found for ${KREL} under /lib/modules."
fi

if [[ ! -d "/lib/modules/${KREL}/updates" && ! -d "/lib/modules/${KREL}/extra" ]]; then
  warn "No /updates or /extra directory found under /lib/modules/${KREL}. Continuing anyway."
fi

log "Loading driver module (tries both module names)..."
sudo modprobe 8812au 2>/dev/null || sudo modprobe 88XXau 2>/dev/null || {
  warn "Module load failed. Showing helpful diagnostics:"
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
echo "  - After kernel updates: sudo pacman -Syu && reboot"
echo "  - Verify DKMS: dkms status"
echo "  - Check logs: dmesg | tail -n 160"
