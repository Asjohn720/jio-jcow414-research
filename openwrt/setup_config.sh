#!/bin/bash
set -e

cd /home/anand/openwrt-airoha

cat << 'EOF' > .config
CONFIG_TARGET_econet=y
CONFIG_TARGET_econet_en7528=y
CONFIG_TARGET_econet_en7528_DEVICE_jiofiber_jcow414=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
CONFIG_PACKAGE_luci-theme-bootstrap=y
CONFIG_IMAGEOPT=y
CONFIG_VERSIONOPT=y
CONFIG_VERSION_DIST="OpenWrt-Asjohn720"
CONFIG_VERSION_NUMBER="1.0"
CONFIG_VERSION_CODE="JCOW414"
EOF

make defconfig
echo "--- DEFCONFIG GENERATED SUCCESSFULLY ---"
grep "CONFIG_TARGET_econet_en7528_DEVICE_jiofiber_jcow414=y" .config
grep "CONFIG_VERSION_DIST" .config || true
