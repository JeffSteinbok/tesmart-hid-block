#!/bin/bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then exec sudo /bin/bash "$0"; fi
label=net.steinbok.tesmart-hid-block
if /bin/launchctl print "system/$label" >/dev/null 2>&1; then
    /bin/launchctl bootout "system/$label"
fi
/bin/rm -f /Library/LaunchDaemons/net.steinbok.tesmart-hid-block.plist
/bin/rm -f /Library/PrivilegedHelperTools/net.steinbok.tesmart-hid-block
echo 'Uninstalled service and helper. Device capture released; source repository retained.'
