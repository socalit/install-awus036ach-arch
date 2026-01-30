#!/usr/bin/env bash
# install-awus036ach-arch.sh
# ALFA AWUS036ACH (RTL8812AU) driver installer for Arch-based Linux
# Uses DKMS via AUR to survive rolling kernel updates
#
# Compatible with:
#   - Arch Linux
#   - CachyOS
#   - Arch Black
#
# Installs:
#   - Matching kernel headers
#   - base-devel, dkms, git
#   - RTL8812AU DKMS driver from AUR (prefers aircrack-ng variant)
#
# Usage:
#   chmod +x install-awus036ach-arch.sh
#   ./install-awus036ach-arch.sh
#
# Notes:
# - Requires an AUR helper (yay). Script will install yay if missing.
# - Safe to re-run (idempotent).
#
# Author: SoCal IT – https://github.com/socalit

set -euo pipefail

log() { echo "[*] $*"; }
ok()  { echo "[OK] $*"; }
warn(){ echo "[!] $*"; }
die() { echo "[X] $*" >&2; exit 1; }

if [[ "${EUID}" -eq 0 ]]; then
  die "Do not run as root. Run as your normal user (script will use sudo)."
fi

if ! command -v sudo >/dev/null 2>&1; then
  die "sudo not found. Install sudo first."
fi

if ! command -v pacman >/dev/null 2>&1; then
  die "pacman not found. This script is for Arch-based distributions only."
fi

log "ALFA AWUS036ACH (RTL8812AU) installer for Arch-based Linux"
KREL="$(uname -r)"
log "Kernel: ${KREL}"

# Detect kernel flavor and choose headers package
HEADERS_PKG="linux-headers"
if echo "$KREL" | grep -qi "cachyos"; then
  HEADERS_PKG="linux-cachyos-headers"
elif echo "$KREL" | grep -qi "zen"; then
  HEADERS_PKG="linux-zen-headers"
elif echo "$KREL" | grep -qi "lts"; then
  HEADERS_PKG="linux-lts-headers"
fi

log "Using headers package: ${HEADERS_PKG}"

log "Updating system and installing dependencies..."
sudo pacman -Syu --noconfirm
sudo pacman -S --needed --noconfirm "${HEADERS_PKG}" base-devel dkms git

# Verify headers match running kernel
if [[ ! -e "/usr/lib/modules/${KREL}/build" ]]; then
  warn "Kernel headers do not appear to match the running kernel: ${KREL}"
  warn "Reboot after kernel updates, then re-run this installer."
fi

# Ensure yay exists (AUR helper)
ensure_yay() {
  if command -v yay >/dev/null 2>&1; then
    ok "yay is installed."
    return 0
  fi

  warn "yay not found. Installing yay (AUR helper)..."
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  cd "$tmpdir"
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si --noconfirm
  ok "yay installed."
}

ensure_yay

log "Removing any conflicting RTL88xxAU modules (if present)..."
lsmod | grep -q "^88XXau" && sudo modprobe -r 88XXau || true
lsmod | grep -q "^8812au" && sudo modprobe -r 8812au || true

log "Selecting RTL8812AU DKMS driver package from AUR..."

# Prefer the aircrack-ng DKMS driver (monitor mode + injection)
CANDIDATES=(
  "rtl8812au-aircrack-ng-dkms-git"
  "rtl8812au-dkms-git"
  "rtl8812au-openhd-dkms-git"
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

log "Found AUR package: ${PKG_FOUND}"
log "Installing ${PKG_FOUND}..."
yay -S --needed --noconfirm "${PKG_FOUND}"

# Ensure DKMS built something for the current kernel (best effort)
if command -v dkms >/dev/null 2>&1; then
  log "DKMS status:"
  dkms status || true
fi

log "Loading driver module..."
sudo modprobe 8812au 2>/dev/null || sudo modprobe 88XXau 2>/dev/null || \
  die "Failed to load module (tried 8812au and 88XXau). Check: dkms status && dmesg | tail -n 120"

ok "Driver loaded successfully."

log "Replug your AWUS036ACH if it is not detected."
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
echo "  - Reboot after kernel updates"
echo "  - Verify DKMS: dkms status"
echo "  - Check logs: dmesg | tail -n 120"
