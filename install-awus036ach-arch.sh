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
# Notes:
# - Adapter does NOT need to be plugged in to compile/install the driver.
# - Adapter DOES need to be plugged in to verify lsusb / iw dev shows the new interface.
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
require_cmd awk
require_cmd sed

KREL="$(uname -r)"
KBUILD="/usr/lib/modules/${KREL}/build"

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

HEADERS_PKG="$(detect_headers_pkg "$KREL")"
log "Computed headers package: ${HEADERS_PKG}"

PACMAN_PKGS=(
  "${HEADERS_PKG}"
  base-devel
  dkms
  git
  linux-firmware
  iw
  usbutils
)

log "Installing required pacman packages (if missing)..."
sudo pacman -S --needed --noconfirm "${PACMAN_PKGS[@]}"
ok "pacman dependencies installed (or already present)"

log "Verifying pacman package names..."
for p in "${PACMAN_PKGS[@]}"; do
  pacman -Qi "$p" >/dev/null 2>&1 || die "Required pacman package not installed (name mismatch or install failed): $p"
  ok "Verified installed pacman package: $p"
done

if [[ ! -e "$KBUILD" ]]; then
  die "Kernel headers path not found: ${KBUILD}. Reboot into the kernel that matches your installed headers, then rerun."
fi
ok "Kernel headers found for: ${KREL}"

ensure_yay() {
  if command -v yay >/dev/null 2>&1; then
    ok "yay is installed"
    return 0
  fi

  warn "yay not found - installing yay from AUR..."
  require_cmd git
  require_cmd makepkg

  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT

  cd "$tmpdir"
  git clone https://aur.archlinux.org/yay.git
  cd yay
  makepkg -si --noconfirm

  command -v yay >/dev/null 2>&1 || die "yay install failed"
  ok "yay installed"
}

ensure_yay

# Prefer newer trees first for newer kernels like 6.18.x
AUR_CANDIDATES=(
  rtl8812au-dkms-git
  rtl8812au-aircrack-ng-dkms-git
  rtl8812au-openhd-dkms-git
)

log "Validating AUR package names (no guessing)..."
VALID_AUR=()
for pkg in "${AUR_CANDIDATES[@]}"; do
  if yay -Si "$pkg" >/dev/null 2>&1; then
    ok "AUR package exists: $pkg"
    VALID_AUR+=("$pkg")
  else
    warn "AUR package missing: $pkg"
  fi
done

if [[ ${#VALID_AUR[@]} -eq 0 ]]; then
  die "No valid rtl8812au DKMS packages found in AUR. Try: yay -Ss 8812au"
fi

log "Preferred AUR candidate: ${VALID_AUR[0]}"

log "USB check (non-fatal). Adapter may be unplugged."
if command -v lsusb >/dev/null 2>&1; then
  if lsusb | grep -qi '0bda:'; then
    ok "Realtek USB device detected"
  else
    warn "No Realtek USB device detected (adapter may be unplugged)"
  fi
else
  warn "lsusb not available (usbutils missing?)"
fi

log "Unloading any currently-loaded RTL88xxAU/RTL8812AU modules (best effort)..."
sudo modprobe -r 88XXau 2>/dev/null || true
sudo modprobe -r 8812au 2>/dev/null || true

log "Removing conflicting driver packages (best effort)..."
# Remove common conflicting packages if they exist (ignore failures)
sudo pacman -Rns --noconfirm \
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

log "Removing old DKMS entries and source directories (best effort)..."
sudo rm -rf /var/lib/dkms/rtl8812au 2>/dev/null || true
sudo rm -rf /usr/src/rtl8812au-* /usr/src/8812au-* 2>/dev/null || true

ok "Pre-clean completed"

log "Installing RTL8812AU DKMS driver from AUR: ${VALID_AUR[0]}"
# Non-interactive yay build/install
yay -S --needed --noconfirm --answerclean All --answerdiff None "${VALID_AUR[0]}"

ok "AUR driver package installed: ${VALID_AUR[0]}"

log "DKMS status (after install):"
dkms status || true

# Force GCC module build for running kernel (avoid LLVM=1 / clang on rolling kernels)
log "Forcing DKMS build for running kernel using GCC (disables LLVM/clang)..."
DRV_VER="$(dkms status | awk -F'[,/ ]+' '/rtl8812au/{print $3; exit}')"
if [[ -z "${DRV_VER}" ]]; then
  warn "Could not detect rtl8812au DKMS version from dkms status"
else
  sudo env LLVM=0 CC=gcc CXX=g++ dkms install -m rtl8812au -v "${DRV_VER}" -k "${KREL}" --force || true
fi

log "DKMS status (after forced rebuild):"
dkms status || true

log "Attempting to load module (8812au then 88XXau)..."
if sudo modprobe 8812au 2>/dev/null; then
  ok "Loaded module: 8812au"
elif sudo modprobe 88XXau 2>/dev/null; then
  ok "Loaded module: 88XXau"
else
  warn "Module load failed. Diagnostics:"
  echo
  echo "== dkms status =="
  dkms status || true
  echo
  echo "== lsmod (filter) =="
  lsmod | grep -E '8812au|88XXau' || true
  echo
  echo "== lsusb (look for Realtek 0bda:8812 when adapter is plugged in) =="
  lsusb || true
  echo
  echo "== recent kernel log (last 200 lines) =="
  sudo dmesg | tail -n 200 || true
  die "Failed to load module (tried 8812au and 88XXau)"
fi

log "Detected wireless interfaces (adapter must be plugged in to show a new wlanX):"
iw dev || true

echo
ok "Installation complete"
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
echo "  - Logs: sudo dmesg | tail -n 200"
echo "  - After kernel updates: reboot (DKMS will rebuild)"
