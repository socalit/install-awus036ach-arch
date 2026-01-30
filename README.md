# AWUS036ACH (RTL8812AU) DKMS Installer

This repository provides a **DKMS-based installer** for the **ALFA AWUS036ACH** USB Wi-Fi adapter using the **Realtek RTL8812AU** chipset on **Arch-based Linux distributions**.

The script is designed for **rolling-release environments** and ensures the driver remains functional across kernel updates while enabling **monitor mode** and **packet injection** for authorized wireless security testing and lab use.

---

## Supported Distributions

This installer uses DKMS, which automatically rebuilds the driver when the kernel updates. This installer is intended for **Arch-based systems**, including:

- CachyOS
- Arch Linux
- Arch Black
- Other Arch derivatives using `pacman` and AUR

> This script is **not** intended for Debian/Ubuntu/Kali systems.

---

## Features

- Installs **rtl8812au-dkms** from the Arch User Repository (AUR
- Automatically rebuilds the driver on kernel updates via **DKMS**
- Enables:
  - Monitor mode
  - Packet injection
- Detects and installs the correct kernel headers
- Safe to re-run (idempotent)
- Designed for rolling-release stability

---

## Hardware Supported

- **ALFA AWUS036ACH**
- Chipset: **Realtek RTL8812AU**

---

## Requirements

- Arch-based Linux system
- `sudo` privileges
- Internet access
- USB ALFA AWUS036ACH adapter
- Kernel headers matching the running kernel

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/socalit/awus036ach-cachyos-installer.git
cd awus036ach-cachyos-installer
```
2. Make the script executable
```bash
chmod +x install-awus036ach-cachyos.sh
```
3. Run the installer
```bash
./install-awus036ach-cachyos.sh
```

---


Verifying Installation

After installation, plug in (or replug) the ALFA adapter and run:

```bash
iw dev
```

