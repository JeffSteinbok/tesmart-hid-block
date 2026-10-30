# Diagnostic findings: October 29-30, 2026

All times below are local PDT. Logs were inspected read-only on the affected Mac.
This is a record of observations, not a claim that TESmart firmware alone is the
root cause. Host USB driver/resume interaction has not been ruled out.

## Setup

- M4 MacBook Air.
- Dell SD25TB4 Thunderbolt dock and TESmart DKS202-M24 KVM.
- Microsoft 2.4GHz Transceiver v9.0 (`045e:07a5`) and Nano Transceiver v2.0
  (`045e:0800`) appeared at different times, sometimes via KVM presentation.
- Other USB devices included a Logitech BRIO and USB audio.

## Repeated sequence

1. Mac enters sleep.
2. Wi-Fi reports an incoming packet wake (`E_RX_IP_PACKET`), waking the system in
   the background.
3. A USB HID driver calls `requestUserActive` with
   `kIOHIDSystemActivityTickle NX_HARDWARE_TICKLE`.
4. macOS turns the display on.

Example on October 30:

```text
00:00:24.522 Wi-Fi incoming-packet wake
00:00:24.969 AppleUserUSBHostHIDDevice (0x100139893) requests user activity
00:00:25     Display is turned on
```

That registry ID mapped to the DKS202-M24 keyboard HID interface. A later event
at 23:51:53 on October 29 also named only the KVM interface while no Microsoft
receiver HID interfaces were present. Physical keyboard/receiver removal did
not eliminate all wakes. Disconnecting the KVM USB uplink reportedly stopped
the behavior in a manual test.

## Capture trials

- A temporary root helper captured the composite controller `1a86:e010`.
- TESmart's keyboard and vendor HID interfaces disappeared from `hidutil list`.
- Receiver interfaces and BRIO remained present in the first capture snapshot.
- At 22:20:05, while capture was active, both Microsoft receiver-named HID
  devices requested user activity during a Wi-Fi wake; the display still woke.
  Therefore, blocking the built-in controller does not stop all possible HID
  display activity in this setup.
- Changing the KVM keyboard mode changed the receiver interfaces' reported
  vendor IDs between `1a86` and `045e`. This suggests proxy/emulation behavior,
  but identity strings do not establish whether a physical receiver is attached
  to this host or whether actual user input occurred.
- A second capture began around 00:32:43, expired after five minutes, and was
  followed by a ten-minute trial beginning around 00:43:42. The user reported
  a quiet interval. This is encouraging, not conclusive.
- There was also an independent notification-triggered full wake at 23:57:19;
  this tool cannot prevent notification/network/system wakes generally.
- Disabling network wake was reported not to solve the problem. The setting
  was subsequently re-enabled, so snapshots of its enabled state did not prove
  what it was during the intervening test.

The installed service should be evaluated across sleep/wake, physical dock
reconnect, and reboot. It targets only the built-in KVM controller; no claim is
made that it blocks other receivers or all sources of screen wake.

## Support email draft

Subject: DKS202-M24 wakes Mac displays with keyboard and receivers unplugged

Hi TESmart Support,

My DKS202-M24 presents a keyboard HID interface that requests screen activity
during background wakes on an M4 MacBook Air connected through a Dell SD25TB4
Thunderbolt dock. This has occurred with my physical keyboard and wireless
receivers unplugged.

Kernel logs identify the DKS202-M24 keyboard interface (USB VID/PID
`1a86:e010`) calling `requestUserActive` with
`kIOHIDSystemActivityTickle NX_HARDWARE_TICKLE`, immediately before the displays
turn on. Disconnecting the KVM USB uplink stopped the behavior in a manual test.

Temporarily capturing the KVM controller through Apple's IOUSBHost API removes
that HID interface. Other receiver-named interfaces have also requested screen
activity in some configurations, so the interaction may involve keyboard mode
or USB resume handling rather than only the built-in keyboard interface.

Is this a known issue? Is firmware available that addresses macOS resume/wake
compatibility, or a way to disable the built-in keyboard interface while
retaining ordinary USB peripheral switching? Please let me know how to retrieve
the hardware revision and firmware version you need.

Thanks,
Jeff
