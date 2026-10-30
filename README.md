# TESmart HID Block

A small, reversible macOS workaround for unwanted display wakes associated with
the **TESmart DKS202-M24's built-in USB HID controller**.

It captures one exact USB device with Apple's `IOUSBHostDevice` device-capture
API, which detaches that device's normal drivers while the process holds it.
It does **not** filter keyboard input, disable SIP, unload Apple's shared HID
driver, or capture the entire USB hub.

## Status and limits

Experimental; tested locally on an M4 MacBook Air with a Dell SD25TB4 dock and
DKS202-M24. Short capture tests removed the TESmart HID interfaces successfully.
One later test had a quiet interval, but an earlier test still woke through
receiver-named interfaces. **This is not a proven fix for every wake.** See
[diagnostic findings](docs/findings.md).

The whole matching composite controller is captured, including its vendor HID
interface, not just the keyboard interface. KVM hotkeys/control features may stop
working. Separate USB receivers, the webcam, audio device, and hub are not capture
targets, but their functionality should be checked after installation.

## Exact target and safety

All conditions must hold:

| Property | Required value |
| --- | --- |
| USB vendor | `0x1a86` |
| USB product | `0xe010` |
| USB product name | `DKS202-M24` |
| USB device class | `0` (not a hub) |
| Number of VID/PID matches | Exactly one |

Multiple matching controllers or an unexpected model/class cause a refusal, not
arbitrary selection. Capture is privileged; dry run and self-tests are read-only.
No input reports, keystrokes, serial numbers, or network packet contents are read
or logged. Logs contain status, registry IDs, and API errors only.

## Build and temporary test

Requires macOS, Apple's compiler/SDK (Xcode or Command Line Tools), and an admin
account. No third-party dependencies.

```sh
make test
./build/tesmart-hid-block --dry-run
sudo ./build/tesmart-hid-block --capture --duration 600
```

The temporary test releases after ten minutes, or on Ctrl-C/SIGTERM. Do not run
two capture instances. Keep the Mac's built-in keyboard/trackpad available.
Verify the mouse/keyboard, let the screens sleep, and compare actual wake logs.

## Install at boot

```sh
bash scripts/install.sh
bash scripts/status.sh
```

The installer builds/tests as the normal user, then requests administrator access
to install two root-owned files:

- `/Library/PrivilegedHelperTools/net.steinbok.tesmart-hid-block`
- `/Library/LaunchDaemons/net.steinbok.tesmart-hid-block.plist`

The root LaunchDaemon starts before login and keeps running without a time limit.
`launchd` restarts it on exit. It checks device enumeration every two seconds,
waits if the dock is absent, and retries capture when the device is re-enumerated
after disconnect/reconnect or wake. It does not force sleep or prevent the Mac
from sleeping. Reconnect handling is polling-based, so there is a short window
before recapture. Reboot/dock/sleep behavior must be verified on the actual setup.

No files in the source checkout are used by the running service. Updating source
does not update the installed helper; rerun the installer after building changes.

## Stop, restart, or uninstall

Stop now (will start again at next boot):

```sh
sudo launchctl bootout system/net.steinbok.tesmart-hid-block
```

Start again after stopping:

```sh
sudo launchctl bootstrap system /Library/LaunchDaemons/net.steinbok.tesmart-hid-block.plist
```

Remove permanently and release the device:

```sh
bash scripts/uninstall.sh
```

Stopping normally calls `destroy()`, restoring normal driver matching. Removal
only deletes the installed helper and plist, not the repository. If peripherals
do not return after stopping, unplug/replug the KVM USB uplink. No security
settings need changing.

## Logs and wake diagnosis

```sh
log show --last 15m --style compact --predicate 'eventMessage BEGINSWITH "tesmart-hid-block:"'
pmset -g log | tail -150
hidutil list
```

For a precise USB activity request, use the kernel log and map its registry ID to
`hidutil list`. A device name alone cannot distinguish a physical receiver from
one emulated/presented by the KVM. Registry IDs change after re-enumeration.

```sh
/usr/bin/log show --last 5m --style compact --predicate 'process == "kernel" AND eventMessage CONTAINS "requestUserActive from"'
```

See Apple's [device-capture documentation](https://developer.apple.com/documentation/iousbhost/iousbhostobjectinitoptions/devicecapture)
for the privilege requirements and driver-detachment/release behavior.
