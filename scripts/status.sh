#!/bin/bash
set -euo pipefail
/bin/launchctl print system/net.steinbok.tesmart-hid-block
echo '--- TESmart HID interfaces (none expected while capture is held) ---'
/usr/bin/hidutil list | /usr/bin/awk '/DKS202-M24/ {print; found=1} END {if (!found) print "No TESmart HID interfaces visible"}'
