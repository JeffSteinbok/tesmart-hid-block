#!/bin/bash
set -euo pipefail
repo_dir="$(cd "$(dirname "$0")/.." && pwd)"
label=net.steinbok.tesmart-hid-block
binary=/Library/PrivilegedHelperTools/net.steinbok.tesmart-hid-block
plist=/Library/LaunchDaemons/net.steinbok.tesmart-hid-block.plist
if [[ $EUID -ne 0 ]]; then
    make -C "$repo_dir" test
    exec sudo /bin/bash "$0"
fi
[[ -f "$repo_dir/build/tesmart-hid-block" ]] || { echo 'Run make test as your normal user first.' >&2; exit 1; }
"$repo_dir/build/tesmart-hid-block" --self-test
/usr/bin/codesign --verify "$repo_dir/build/tesmart-hid-block"
/usr/bin/plutil -lint "$repo_dir/launchd/$label.plist"
if /bin/launchctl print "system/$label" >/dev/null 2>&1; then
    /bin/launchctl bootout "system/$label"
fi
/usr/bin/install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
/usr/bin/install -o root -g wheel -m 755 "$repo_dir/build/tesmart-hid-block" "$binary"
/usr/bin/install -o root -g wheel -m 644 "$repo_dir/launchd/$label.plist" "$plist"
/bin/launchctl bootstrap system "$plist"
echo 'Installed. Starts at boot and retries reconnects. Check with scripts/status.sh.'
echo 'Stop: sudo launchctl bootout system/net.steinbok.tesmart-hid-block'
