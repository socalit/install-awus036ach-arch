![install-awus036ach](assets/banner.png)

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-%23FFDD00?logo=buymeacoffee&logoColor=black)](https://buymeacoffee.com/socal370xs)
[![Linux](https://img.shields.io/badge/Linux-Arch%20%7C%20CachyOS%20%7C%20Arch%20Black-blue?logo=linux)](https://archlinux.org/)
[![Adapter](https://img.shields.io/badge/Adapter-AWUS036ACH-red)](https://www.alfa.com.tw/)
[![Driver](https://img.shields.io/badge/Driver-RTL8812AU-blue)](#)
[![WiFi](https://img.shields.io/badge/WiFi-Monitor%20%7C%20Injection-success)](#)
[![License](https://img.shields.io/badge/license-MIT-purple)](/LICENSE)

# ALFA AWUS036ACH Driver Installer for Arch Linux (Rolling)

This script installs the correct **Realtek RTL8812AU** driver for the **ALFA AWUS036ACH** USB Wi-Fi adapter on **Arch-based Linux distributions** using **DKMS**.

It enables **monitor mode** and **packet injection**, and is designed to **survive rolling kernel updates** commonly found on Arch, CachyOS, and Arch Black.

> Developed and maintained by **SoCal IT** for wireless security testing and lab environments.

---

## Supported Distributions

- Arch Linux  
- CachyOS  
- Arch Black  
- Other Arch-based rolling distributions

> This script is **not intended for Kali, Debian, or Ubuntu** systems.

---

## Features

- Automatically detects the running kernel and installs matching headers  
- Installs required build tools and DKMS dependencies  
- Installs **rtl8812au-dkms** from the Arch User Repository (AUR)  
- Registers the driver with DKMS for automatic rebuilds on kernel updates  
- Loads the `88XXau` kernel module  
- Supports:
  - Monitor mode
  - Packet injection  
- Safe to re-run (idempotent)  
- Designed specifically for rolling-release stability  

---

## Requirements

- Arch-based Linux distribution  
- `sudo` privileges  
- Internet access  
- ALFA AWUS036ACH (Realtek RTL8812AU chipset)  
- Kernel headers matching the running kernel  

---

## Installation

```bash
git clone https://github.com/socalit/awus036ach-cachyos-installer.git
cd awus036ach-cachyos-installer
chmod +x install-awus036ach-cachyos.sh
./install-awus036ach-cachyos.sh
```
The installer will:

Install kernel headers if missing

Install build dependencies

Install rtl8812au-dkms via AUR

Build and load the driver module

---

Verifying Installation

After installation, plug in (or replug) the adapter and run:
```bash
iw dev
```
## Support 
### ⭐ **Star the GitHub repo** ### Share it with communities ### Open issues or request features If this project saved you time or solved a problem, consider supporting development: [![Buy Me a Coffee](https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20coffee&slug=socal370xs&button_colour=FFDD00&font_colour=000000&font_family=Arial&outline_colour=000000&coffee_colour=ffffff)](https://buymeacoffee.com/socal370xs)
