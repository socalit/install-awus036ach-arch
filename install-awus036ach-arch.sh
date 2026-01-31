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
sudo pacman -S --needed --noconfirm "${HEADERS_PKG}" base-devel dkms git gcc make

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

# Make yay non-interactive (no clean/diff prompts)
YAY_FLAGS=(--noconfirm --needed --answerclean None --answerdiff None --removemake)

log "Unloading any currently-loaded 88xxau/8812au modules (best effort)..."
sudo modprobe -r 88XXau 2>/dev/null || true
sudo modprobe -r 8812au 2>/dev/null || true

log "Selecting and installing an RTL8812AU DKMS driver from AUR (rolling-safe + fallback)..."

# Try newer tree first on rolling kernels
CANDIDATES=(
  "rtl8812au-dkms-git"
  "rtl8812au-aircrack-ng-dkms-git"
)

dkms_find_rtl8812au_version() {
  # Prefer /usr/src naming if present; otherwise dkms status parsing
  dkms status 2>/dev/null | awk -F'[/, ]' '/^rtl8812au\//{print $2}' | head -n 1
}

find_dkms_conf_paths() {
  local ver="$1"
  # Common places:
  #  - /usr/src/rtl8812au-<ver>/dkms.conf
  #  - /var/lib/dkms/rtl8812au/<ver>/source/dkms.conf
  local paths=()
  if [[ -n "$ver" ]]; then
    [[ -f "/usr/src/rtl8812au-${ver}/dkms.conf" ]] && paths+=("/usr/src/rtl8812au-${ver}/dkms.conf")
    [[ -f "/var/lib/dkms/rtl8812au/${ver}/source/dkms.conf" ]] && paths+=("/var/lib/dkms/rtl8812au/${ver}/source/dkms.conf")
  fi
  # Also scan if version path differs (git pkgver quirks)
  while IFS= read -r p; do paths+=("$p"); done < <(ls -1 /usr/src/rtl8812au-*/dkms.conf 2>/dev/null || true)
  while IFS= read -r p; do paths+=("$p"); done < <(ls -1 /var/lib/dkms/rtl8812au/*/source/dkms.conf 2>/dev/null || true)

  # De-dupe
  printf "%s\n" "${paths[@]}" | awk '!seen[$0]++'
}

tail_make_logs() {
  local ver="$1"
  local logpath=""
  if [[ -n "$ver" && -f "/var/lib/dkms/rtl8812au/${ver}/build/make.log" ]]; then
    logpath="/var/lib/dkms/rtl8812au/${ver}/build/make.log"
  else
    # Best-effort: newest rtl8812au make.log
    logpath="$(ls -1t /var/lib/dkms/rtl8812au/*/build/make.log 2>/dev/null | head -n 1 || true)"
  fi

  if [[ -n "$logpath" && -f "$logpath" ]]; then
    echo
    echo "== DKMS make.log (tail 80) =="
    echo "Path: ${logpath}"
    sudo tail -n 80 "$logpath" || true
    echo
  else
    echo
    echo "== DKMS make.log =="
    echo "No make.log found under /var/lib/dkms/rtl8812au/*/build/"
    echo
  fi
}

patch_dkms_conf_force_gcc() {
  local ver="$1"
  local patched="0"

  while IFS= read -r conf; do
    [[ -f "$conf" ]] || continue
    # Patch rules:
    # - If LLVM=1 appears in MAKE[...] lines, flip to LLVM=0
    # - If LLVM= is absent, append LLVM=0 to MAKE[0] line (best effort)
    log "Patching DKMS config to force GCC (LLVM=0): $conf"
    sudo sed -i \
      -e 's/\bLLVM=1\b/LLVM=0/g' \
      -e 's/\bLLVM= 1\b/LLVM=0/g' \
      "$conf" || true

    # If there are MAKE[...] lines and none contain LLVM=, append LLVM=0
    if sudo grep -qE '^[[:space:]]*MAKE\[[0-9]+\]=' "$conf"; then
      if ! sudo grep -qE '^[[:space:]]*MAKE\[[0-9]+\]=.*\bLLVM=' "$conf"; then
        sudo sed -i -E 's/^(MAKE\[[0-9]+\]=.*)"/\1 LLVM=0"/' "$conf" || true
      fi
    fi

    patched="1"
  done < <(find_dkms_conf_paths "$ver")

  [[ "$patched" == "1" ]]
}

dkms_rebuild_install_force() {
  local ver="$1"
  local krel="$2"

  # Clean any partial state for this kernel (best effort)
  sudo dkms remove "rtl8812au/${ver}" -k "${krel}" --force 2>/dev/null || true

  # Force install (some DKMS installs collide)
  sudo dkms install "rtl8812au/${ver}" -k "${krel}" --force
}

install_and_build_for_kernel() {
  local pkg="$1"
  local krel="$2"

  log "Trying AUR package: ${pkg}"

  if ! yay -Si "${pkg}" >/dev/null 2>&1; then
    warn "Package not found in AUR: ${pkg}"
    return 1
  fi

  # Install candidate (non-interactive)
  yay -S "${YAY_FLAGS[@]}" "${pkg}" || return 1

  # Determine DKMS module version
  local dk_ver=""
  dk_ver="$(dkms_find_rtl8812au_version || true)"
  if [[ -z "$dk_ver" ]]; then
    warn "Could not detect rtl8812au DKMS version. Will still attempt build."
  else
    log "Detected DKMS module: rtl8812au, version: ${dk_ver}"
  fi

  # Attempt 1: DKMS autoinstall for the running kernel
  log "Forcing DKMS build for running kernel: ${krel} (default)"
  if sudo dkms autoinstall -k "${krel}"; then
    ok "DKMS build succeeded for ${pkg} on kernel ${krel}"
    return 0
  fi

  warn "DKMS default build failed for ${pkg} on kernel ${krel}"
  tail_make_logs "${dk_ver}"

  # Attempt 2: Patch dkms.conf to stop forcing LLVM=1, then rebuild with --force
  if [[ -n "$dk_ver" ]]; then
    warn "Applying rolling-safe patch: force GCC by patching dkms.conf (LLVM=0) and rebuilding..."
    patch_dkms_conf_force_gcc "${dk_ver}" || warn "dkms.conf patch may not have applied (continuing anyway)."

    if dkms_rebuild_install_force "${dk_ver}" "${krel}"; then
      ok "DKMS build succeeded after GCC/LLVM patch for ${pkg} on kernel ${krel}"
      return 0
    fi

    warn "Patched rebuild still failed for ${pkg} on kernel ${krel}"
    tail_make_logs "${dk_ver}"
  else
    warn "No DKMS version detected, cannot patch dkms.conf reliably."
  fi

  warn "Removing ${pkg} and trying next candidate..."
  yay -Rns --noconfirm "${pkg}" || true
  return 1
}

PKG_OK=""
for pkg in "${CANDIDATES[@]}"; do
  if install_and_build_for_kernel "${pkg}" "${KREL}"; then
    PKG_OK="${pkg}"
    break
  fi
done

if [[ -z "${PKG_OK}" ]]; then
  die "All candidate RTL8812AU DKMS drivers failed to build for kernel ${KREL}. See make.log output above."
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
