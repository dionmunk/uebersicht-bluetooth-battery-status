#!/bin/bash
# Bluetooth battery levels from two sources, separated by ---SEP---:
#   ioreg           - HID peripherals (Magic Mouse / Keyboard / Trackpad), one
#                     "+-o" node per device with its address and charge flags
#   system_profiler - JSON for everything else (e.g. AirPods), and the device
#                     names ioreg can leave blank
# On first run, also renders the SF Symbol bolt.fill to a PNG (the charging-bolt
# mask) with the Swift helper; the PNG is generated locally, not shipped.
# Requires Xcode Command Line Tools (`swift`).
DIR="$(cd "$(dirname "$0")" && pwd)"
if [ ! -f "$DIR/icons/bolt.fill.ink.png" ]; then
  mkdir -p "$DIR/icons"
  swift "$DIR/render-bolt.swift" "$DIR/icons" >/dev/null 2>&1
fi

ioreg -r -k BatteryPercent | grep -E '[+]-o|"(Product|BD_ADDR|DeviceAddress|BatteryPercent|BatteryStatusFlags)"'
echo '---SEP---'
system_profiler -json SPBluetoothDataType 2>/dev/null
