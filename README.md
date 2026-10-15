# Jio Fiber JCOW414 — Hardware & OpenWrt Research

Personal research project on an owned Sercomm Jio Fiber JCOW414 router (EcoNet EN7528HU platform).  
Goals: Root access, flash decapsulation, hardware documentation, and porting OpenWrt / Entware.

> **Status: Root Achieved & Partitions Dumped** — Permanent root shell access unlocked, all 8 MTD partitions dumped, kernel decapsulated. OpenWrt research in progress.

---

## Current Status

| Area | Status | Notes |
|---|---|---|
| Hardware identification | ✅ Complete | All ICs, SoC, RAM, radios, and flash chips documented |
| Root shell access | ✅ Complete | Unlocked via R2.15 Downgrade + Lua Config Injection |
| Firmware dump | ✅ Complete | All MTD partitions (`mtd0`-`mtd11`) extracted & backed up |
| Kernel decapsulation | ✅ Complete | EcoNet `HDR2` container unpacked; LZMA MIPS kernel extracted |
| Bootloader access | ✅ Bypassed | Interactive prompt bypassed via root shell; full `mtd0` binary dumped |
| OpenWrt research | 🔄 In Progress | Device tree authored; target mapped to `target/linux/econet/en7528` |

---

## Root Access & Setup Guide

Follow this step-by-step guide to unlock permanent root shell access, disable remote ISP auto-updates, and back up all flash partitions.

### 1. Web UI Firmware Downgrade
Downgrade to R2.15 to unlock configuration decryption:
* **Firmware Image:** [`SRCMTF1_JCOW414_R2.15.img`](https://raw.githubusercontent.com/gpsarathy/JioFiber-Home-Gateway/master/Firmwares/JCOW414/2.15/SRCMTF1_JCOW414_R2.15.img) (or via [Jio OTA URL](http://fota.slv.fxd.jiophone.net/ONT/Sercomm/JCOW414/SRCMTF1_JCOW414_R2.15.img))
* **Signature File:** [`SRCMTF1_JCOW414_R2.15.sig`](https://raw.githubusercontent.com/gpsarathy/JioFiber-Home-Gateway/master/Firmwares/JCOW414/2.15/SRCMTF1_JCOW414_R2.15.sig) (or via [Jio OTA URL](http://fota.slv.fxd.jiophone.net/ONT/Sercomm/JCOW414/SRCMTF1_JCOW414_R2.15.sig))

1. Open the router web panel at `http://192.168.29.1` (or your router IP) and log in.
2. Go to: **Administrator** &rarr; **Maintenance** &rarr; **Firmware Upgrade**.
3. Upload both `.img` and `.sig` files and click **Proceed**.
4. The router flashes the image to the alternate bank (`tclinux_slave` / `mtd7`) and boots into R2.15.

### 2. Config Backup Decryption & Lua Command Injection
1. Go to: **Administrator** &rarr; **Maintenance** &rarr; **Backup** and download your configuration file (`RSVXXXXXXXXXXX_JCOW414.enc`).
2. Decrypt the backup with OpenSSL using [`keys/JCOW414.key`](keys/JCOW414.key) (AES-128-CBC with SHA256 KDF):
   ```bash
   openssl aes-128-cbc -d -pass pass:$(cat keys/JCOW414.key) -in backup.enc -out backup.txt
   ```
3. Open `backup.txt` in a text editor. Replace line 1 (`config.userdb = {}`) with:
   ```lua
   config.userdb = {} os.execute("/usr/sbin/telnetd"); os.execute("/pfrm2.0/bin/iptables -I fwInBypass -p tcp --dport 23 -m ifgroup --ifgroup-in 0x1/0x1 -j ACCEPT"); os.execute("echo -e \"password\npassword\" | passwd root");
   ```
   *(Ensure the whole payload stays on line 1 with no line breaks).*
4. Re-encrypt with the same key:
   ```bash
   openssl aes-128-cbc -pass pass:$(cat keys/JCOW414.key) -in backup.txt -out backup_modified.enc
   ```
5. In the web panel, go to **Maintenance** &rarr; **Restore** and upload `backup_modified.enc`.
6. The web UI will show *"Failed to update configuration (checksum error)"* — this is expected. Line 1 has executed in memory as root.
7. Connect via Telnet to port 23:
   ```bash
   telnet 192.168.29.1 23
   ```
   * **Username:** `root`
   * **Password:** `password`

### 3. Persistence & Preventing Re-Locking
Inside the Telnet root shell, run:
```sh
# 1. Prevent background watchdog from killing Telnet
rm -f /flash/telnetDisable
touch /tmp/DEBUG_IMAGE

# 2. Make custom root password & telnetd survive reboots
mkdir -p /flash2/pfrm2.0/etc
cat << 'EOF' > /flash2/pfrm2.0/etc/voipInit
#!/bin/sh
echo -e "password\npassword" | passwd root
/usr/sbin/telnetd
. /pfrm2.0/etc/voipInit &
EOF
chmod +x /flash2/pfrm2.0/etc/voipInit

# 3. Disable TR-069 daemon to block silent OTA updates from Jio
killall -9 smartcableONTApp 2>/dev/null
chmod 000 /usr/sbin/smartcableONTApp 2>/dev/null
```

### 4. Partition Dump Extraction
Start Busybox `httpd` to download backups over your browser:
```sh
/pfrm2.0/bin/iptables -I fwInBypass -p tcp --dport 8080 -m ifgroup --ifgroup-in 0x1/0x1 -j ACCEPT
mkdir -p /tmp/mtd_backup
cat /dev/mtd0 > /tmp/mtd_backup/mtd0_bootloader.bin
cat /dev/mtd1 > /tmp/mtd_backup/mtd1_romfile.bin
cat /dev/mtd2 > /tmp/mtd_backup/mtd2_kernel.bin
cat /dev/mtd3 > /tmp/mtd_backup/mtd3_rootfs.bin
cat /dev/mtd4 > /tmp/mtd_backup/mtd4_tclinux.bin
cat /dev/mtd8 > /tmp/mtd_backup/mtd8_opt0.bin
cat /dev/mtd9 > /tmp/mtd_backup/mtd9_opt1.bin
cat /dev/mtd11 > /tmp/mtd_backup/mtd11_config.bin
httpd -p 8080 -h /tmp/mtd_backup
```
Navigate to `http://<router-ip>:8080/` in your browser to download all binary partition dumps.

---

## Hardware Specifications

| Component | Specification | Details |
|---|---|---|
| **Model** | Sercomm JCOW414 | Manufactured for Reliance Jio Fiber |
| **Main SoC** | EcoNet EN7528HU | MIPS 1004Kc @ 900MHz, 4 cores (TC3162 / EN751221) |
| **RAM** | 512MB DDR3 | SK Hynix H5TQ4G63EFR (432MB usable System RAM) |
| **SPI NOR Flash** | 1MB (8Mbit) | Puya P25Q80L (U19, SOP-8, Stage 1 Bootloader) |
| **SPI NAND Flash**| 256MB (2Gbit) | Micron MT29F2G01 (Kernel, Rootfs, Config data) |
| **Wi-Fi 2.4GHz** | MediaTek MT7603E | 802.11b/g/n (PCIe Bus 1, `14c3:7603`) |
| **Wi-Fi 5GHz** | MediaTek MT7613E | 802.11a/n/ac (PCIe Bus 2, `14c3:7663`) |
| **Ethernet** | 4x Gigabit LAN | Integrated switch (`eth0.1` - `eth0.4`) |
| **USB** | USB 3.0 Host | xHCI controller (`u3h` / `ippc`) |
| **Fiber (PON)** | GPON (SC/APC) | Integrated optical transceiver |

### GPIO & Peripheral Map

Extracted from `/userfs/led.conf`, `ledctl1`, and kernel `/proc/tc3162/`:

| Function | Pin / Resource | Active State / Note |
|---|---|---|
| **Status LED — Red** | GPIO 27 | Active High |
| **Status LED — Green** | GPIO 25 | Active High |
| **Status LED — Blue** | GPIO 23 | Active High |
| **Reset Button** | GPIO 0 | Active Low (Input) |
| **WPS Button** | GPIO 4 | Active Low (Input) |
| **USB 1 Power (VBUS)** | GPIO 9 | Active High |
| **USB 2 Power (VBUS)** | GPIO 11 | Active High |
| **LAN Port 1 (LAN1)** | Switch Port 1 | Gigabit (`eth0.1`) |
| **LAN Port 2 (LAN2)** | Switch Port 2 | Gigabit (`eth0.2`) |
| **LAN Port 3 (LAN3)** | Switch Port 3 | Gigabit (`eth0.3`) |
| **LAN Port 4 (LAN4)** | Switch Port 4 | Gigabit (`eth0.4`) |

---

## Flash Partition Layout (MTD)

From `/proc/mtd`:

| Partition | Offset | Size | Contents |
|---|---|---|---|
| `mtd0` | `0x00000000` | 256 KB | `bootloader` (TcBoot stage 1) |
| `mtd1` | `0x00040000` | 256 KB | `romfile` (Factory calibration, MAC, serial) |
| `mtd2` | `0x00080000` | ~4 MB | `kernel` (Active Linux kernel) |
| `mtd3` | `0x0047379c` | ~36 MB | `rootfs` (SquashFS read-only root) |
| `mtd4` | `0x00080000` | 40 MB | `tclinux` (Bank 1 primary firmware) |
| `mtd5` | — | ~4 MB | `kernel_slave` (Backup bank kernel) |
| `mtd6` | — | ~34 MB | `rootfs_slave` (Backup bank rootfs) |
| `mtd7` | `0x02880000` | 40 MB | `tclinux_slave` (Bank 2 backup firmware) |
| `mtd8` | `0x05080000` | 8 MB | `opt0` |
| `mtd9` | `0x05880000` | 8 MB | `opt1` |
| `mtd10`| `0x06080000` | 26 MB | `ubifs` (`/flash` persistent config data) |
| `mtd11`| `0x07a80000` | 2 MB | `config` |
| `mtd12`| `0x07c80000` | 90 MB | `ubifs2` (`/flash2` persistent app data) |
| `mtd13`| `0x0ddc0000` | ~2 MB | `reservearea` |

> **Fail-Safe Architecture:** The router utilizes dual firmware banks (`tclinux` and `tclinux_slave`). Flashing custom builds to one bank preserves the alternate bank as a recovery failsafe.

---

## Firmware Decapsulation & Structure

* **Container Header:** The stock kernel and `tclinux` images use the EcoNet **`HDR2`** container format:
  * Magic: `48 44 52 32` (`HDR2`)
  * Kernel Load Address: `0x80002000`
  * Kernel Entry Point: `0x80079010`
* **Compression:** Raw LZMA stream begins at offset `0x100` (256 bytes) directly after the header.
* **Kernel:** Decompresses to an 11.4MB MIPS 32-bit Linux 3.18.21 kernel binary (`vmlinux`).
* **Root Filesystem:** Standard SquashFS 4.0 containing proprietary kernel modules:
  * `mt7603eap.ko` — MediaTek Wi-Fi AP driver
  * `xpon.ko`, `gpon_flow.ko` — GPON optical uplink driver
  * `eth.ko`, `eth_ephy.ko` — Ethernet switch driver
  * `hw_nat.ko`, `swnat.ko` — Hardware NAT acceleration

---

## UART Serial Header — J4

Populated 4-pin header located between the large 2200µF capacitor and the metal RF shield:

```
J4 Header (left to right)
┌─────┬─────┬─────┬─────┐
│  1  │  2  │  3  │  4  │
│ GND │ TX  │ RX  │ VCC │ (3.3V — DO NOT CONNECT)
└─────┴─────┴─────┴─────┘
```

* **Connection Settings:** `115200` baud, `8` data bits, `no` parity, `1` stop bit, `no` flow control.
* **Logic Level:** 3.3V (CP2102 or CH340 USB-TTL adapter).

---

## OpenWrt Development Notes

* **Architecture:** MIPS 1004Kc (little-endian, 32-bit).
* **Device Tree Source:** See [`openwrt/en7528-sercomm-jcow414.dts`](openwrt/en7528-sercomm-jcow414.dts) for complete pinout and peripheral bindings.
* **Upstream Target:** OpenWrt supports the EcoNet EN7528 platform under `target/linux/econet/en7528` (and PR #20104 `target/linux/airoha`).
* **Kernel Image Packaging:** Custom kernels must be wrapped with the EcoNet `HDR2` header with load address `0x80002000` and LZMA-compressed.
* **Failsafe Testing:** Custom firmware can be written to Bank 1 (`mtd4` / `tclinux`) while leaving Bank 2 (`mtd7` / `tclinux_slave`) untouched as a rollback guarantee.
* **Alternative (Entware):** Users who wish to keep original GPON/Wi-Fi vendor performance while running custom packages (AdGuard Home, WireGuard, Cloudflare tunnels, transmission) can install Entware using `jf_entware_mips.sh` directly into `/flash2` on rooted stock firmware.

---

## Community Resources & Credits

- [gpsarathy/JioFiber-Home-Gateway](https://github.com/gpsarathy/JioFiber-Home-Gateway) — firmware OTA archive, static decryption keys
- [JFC Group — JioFiber Customisation](https://github.com/JFC-Group/JF-Customisation) — root access research, Entware scripts
- [NaniBot — JIO Notes](https://nanibot.net/posts/jio-notes/) — persistent root method documentation
- [fawazahmed0/Jio-fiber-Modem](https://github.com/fawazahmed0/Jio-fiber-Modem) — related Jio router research

---

## Disclaimer

This research is conducted on personally owned hardware, disconnected from any live network, for educational and hardware preservation purposes. No ISP infrastructure was accessed or targeted.
