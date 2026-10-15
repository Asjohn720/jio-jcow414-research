# Research Log

## Session 1 — Hardware Identification

- Opened router, photographed PCB front and back
- Identified all major ICs by visual inspection of markings
- Located J4 UART header (4-pin, populated, near large capacitor)
- Confirmed SPI NOR flash at U19 (Puya P25Q80L)
- Identified SK Hynix H5TQ4G63EFR RAM (512MB DDR3)
- EcoNet EN7528HU SoC confirmed (MIPS-based, GPON integrated)
- Two MediaTek Wi-Fi chips: MT7592N and MT7613BEN

## Session 2 — Web UI and Network Recon

- Full admin access at 192.168.29.1
- nmap full TCP scan — only ports 80, 443, 53 open
- No telnet, SSH, FTP, TFTP, SNMP on LAN
- Hidden endpoints: /info.html and /status.html return 403
- Downloaded config backup from Maintenance → Backup/Restore
- Firmware upgrade page requires both .img and .sig files

## Session 3 — Config Backup Analysis

- Identified as OpenSSL AES-256-CBC encrypted
- Attempted decryption with all label values and common passwords
- Tried keyguesser.py from JFC Group — fails on R2.52.1
- Inner layer entropy 7.999/8.0 — double encrypted
- Concluded: not decryptable without firmware downgrade

## Session 4 — UART Access

- Purchased CP2102 USB-TTL adapter and multimeter
- Identified J4 pins using continuity and voltage measurement
- Connected CP2102 at 115200 8N1, opened minicom
- Successfully captured full boot log on first attempt
- Discovered two separate locked prompts during boot
- Linux shell confirmed at end of boot: reliance.reliance login:
- Username root confirmed valid, password unknown
- Discovered console noise issue — daemons share TTY with login

## Key Discoveries

- Router manufactured by Sercomm, customized by RIL (Reliance)
- Internal EcoNet codename: TC3162 / EN751221
- Build hostname: root@tn795
- Firmware R2.52.1 has read-only filesystem (blocks standard JFC exploit)
- Two separate boot prompt windows, both locked
- Console TTY shared with system daemons — unique to newer firmware
- "Thirdparty configuration exists" logged at boot — unknown significance
- TR-069 client (smartcableONTApp) contacts Jio backend on startup
- Dual firmware design: tclinux (primary) + tclinux_slave (backup)

## Session 5 — Firmware Downgrade, Root Exploitation, & MTD Dump

- Acquired official `SRCMTF1_JCOW414_R2.15.img` and `SRCMTF1_JCOW414_R2.15.sig`
- Uploaded and flashed via Web UI Firmware Upgrade page
- Successfully booted into R2.15 on alternate partition bank (`tclinux_slave` / `mtd7`)
- Generated fresh config backup (`.enc`) on R2.15
- Successfully decrypted backup with static `JCOW414.key` (AES-128-CBC with SHA256 KDF)
- Injected Lua payload into line 1 (`os.execute("/usr/sbin/telnetd")...`)
- Re-encrypted and uploaded via Maintenance → Restore
- Achieved root Telnet shell on port 23 (`root` / `password`)
- Created persistence script at `/flash2/pfrm2.0/etc/voipInit` to persist root password across reboots
- Removed `/flash/telnetDisable` and killed `smartcableONTApp` (TR-069)
- Started Busybox `httpd` on port 8080 and dumped all 8 active MTD partitions (`mtd0` to `mtd11`)
- Decapsulated `mtd2_kernel.bin`: EcoNet `HDR2` container with load address `0x80002000`, unpacked 11.4MB MIPS Linux 3.18.21 kernel via LZMA offset `0x100`
- Extracted `mtd3_rootfs.bin` SquashFS filesystem, preserving all kernel modules (`xpon.ko`, `mt7603eap.ko`, `eth.ko`)

## Key Discoveries

- Router manufactured by Sercomm, customized by RIL (Reliance)
- Internal EcoNet codename: TC3162 / EN751221
- Build hostname: root@tn795
- Firmware R2.52.1 has read-only filesystem and randomized root password
- R2.15 downgrade successfully bypasses all authentication locks
- Firmware uses dual-bank partition layout (`tclinux` on `mtd4` and `tclinux_slave` on `mtd7`)
- Stock kernel packaged in EcoNet `HDR2` container with entry point `0x80002000`
- TR-069 client (smartcableONTApp) can be disabled permanently to avoid forced OTA upgrades

## Session 6 — Hardware Pinout & Peripheral Reverse Engineering

- Extracted live device-tree from running kernel via `/proc/device-tree` (`device-tree.tar.gz`)
- Compatible platform string verified: `econet,en751221` / `econet,en7528`
- Wi-Fi PCIe vendor and device IDs identified:
  - Bus 1: `14c3:7603` &rarr; MediaTek MT7603E (2.4GHz 802.11b/g/n)
  - Bus 2: `14c3:7663` &rarr; MediaTek MT7613E (5GHz 802.11a/n/ac)
- Decompiled `ledctl1` and parsed `/userfs/led.conf` to extract exact GPIO assignments:
  - **Tricolor Red LED:** GPIO 27
  - **Tricolor Green LED:** GPIO 25
  - **Tricolor Blue LED:** GPIO 23
  - **Reset Button:** GPIO 0 (Active Low, Mode 5 input)
  - **WPS Button:** GPIO 4 (Active Low, Mode 5 input)
  - **USB 1 VBUS Power:** GPIO 9
  - **USB 2 VBUS Power:** GPIO 11
  - **PHY TX Power Disable:** GPIO 16
- Queried `/proc/tc3162/eth_portmap` and `/proc/tc3162/eth_port_status`:
  - Internal Switch Port 1 &rarr; LAN1
  - Internal Switch Port 2 &rarr; LAN2
  - Internal Switch Port 3 &rarr; LAN3
  - Internal Switch Port 4 &rarr; LAN4
- Authored initial OpenWrt Device Tree Source: `openwrt/en7528-sercomm-jcow414.dts`

## Session 7 — OpenWrt Compilation, Dual-Bank Flashing, & Verified Boot

- Set up build environment in WSL2 Ubuntu with GCC 14, Musl, and OpenWrt Airoha/EcoNet staging branch
- Verified upstream device profile `Device/jiofiber_jcow414` in `target/linux/econet/image/en7528.mk`
- Configured custom distribution branding: `OpenWrt-Asjohn720` (v1.0-JCOW414)
- Fixed WSL PATH space delimiter issue and compiled factory image via `make -j16` (Linux kernel 6.18.55)
- Binaries generated:
  - `openwrt-asjohn720-1.0-jcow414-econet-en7528-jiofiber_jcow414-squashfs-tclinux.trx` (9.8 MB)
  - `openwrt-asjohn720-1.0-jcow414-econet-en7528-jiofiber_jcow414-squashfs-sysupgrade.bin` (8.7 MB)
- Discovered stock router `mtd` tool requirement: `-f` flag needed to bypass Broadcom `HDR0` check for EcoNet `HDR2` images (`mtd -f write /tmp/openwrt.trx tclinux`)
- Flashed custom firmware exclusively to Bank 1 (`tclinux` / `mtd4`), preserving stock R2.15 on Bank 2 (`tclinux_slave` / `mtd7`)
- Swapped active boot flag via stock utility `/usr/bin/sys bootflag swap` (`current boot_flag = 0`)
- Rebooted router into fully functional OpenWrt LuCI web interface (`http://192.168.1.1`):
  - Model: `JioFiber JCOW414`
  - Platform: `EcoNet-EN75xx` (`econet/en7528`)
  - Firmware Version: `OpenWrt by Asjohn720 1.0-JCOW414`
  - Kernel: `6.18.55`
  - RAM: `432.22 MiB` usable (76% free)
  - Switch: all 4 LAN ports operational with link status detection

## Project Milestones

- [x] Firmware downgrade to R2.15 via web UI
- [x] Telnet root access and persistence configuration
- [x] Full MTD partition dump (`mtd0` - `mtd11`)
- [x] Kernel extraction and rootfs decompilation
- [x] Live device-tree and hardware GPIO pinout extraction
- [x] OpenWrt Device Tree Source (`.dts`) authored
- [x] Compile functional OpenWrt image using `target/linux/econet/en7528`
- [x] Safe flash test OpenWrt image to Bank 1 (`mtd4`)
- [x] Successful boot into OpenWrt LuCI Web Dashboard
- [ ] CH341A SPI NOR flash read of U19 for bootloader patching


