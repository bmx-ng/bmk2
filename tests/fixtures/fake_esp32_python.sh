#!/bin/sh
cat <<'EOF'
esptool v5.3.1
Serial port /dev/ttyACM0:
Chip type: ESP32-S3
Features: Wi-Fi, BLE
Crystal frequency: 40MHz
USB mode: USB-Serial/JTAG
MAC: 00:11:22:33:44:55
Manufacturer: 20
Device: 4017
Detected flash size: 8MB
Hard resetting via RTS pin...
EOF
