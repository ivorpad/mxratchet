# mxratchet

Force Ratchet scroll mode on a Logitech MX Master 3 via HID++ 2.0, bypassing Logi Options+.

## Why

Logi Options+ has a persistent bug where it loses the Ratchet scroll wheel setting on the MX Master 3 — the wheel silently reverts to Free Spin, often after waking from sleep or reconnecting via Bluetooth. This has been reported by many users over several years with no fix.

The MX Master 3's scroll wheel mode is controlled by an electromagnet. Ratchet vs Free Spin is just a software command sent over Logitech's HID++ 2.0 protocol. We can send that command directly, without Logi Options+ at all.

## How it works

The tool communicates with the mouse over Bluetooth Low Energy using macOS IOKit HID:

1. **Find the device** — Enumerates HID devices by Logitech vendor ID (`0x046D`) and MX Master 3 product IDs
2. **Resolve the SmartShift feature** — Queries the HID++ 2.0 IRoot (feature index 0) to map feature ID `0x2110` to a device-local feature index
3. **Set ratchet mode** — Calls SmartShift `setRatchetControlMode` with `wheelMode=2` (Ratchet) and `autoDisengage=0xFF` (disable SmartShift entirely)

The `watch` command polls every 30 seconds and re-applies ratchet if the mode has changed, making it resilient against Logi Options+ overriding the setting.

A macOS LaunchDaemon runs `watch` as root at boot, so ratchet mode persists across reboots without any user interaction.

## Requirements

- macOS (tested on macOS 15 Sequoia)
- Swift compiler (`swiftc`, included with Xcode or Command Line Tools)
- MX Master 3 connected via Bluetooth, Bolt, or Unifying receiver
- `sudo` — BLE HID access requires root on macOS

## Install

```bash
git clone https://github.com/ivorpad/mxratchet.git
cd mxratchet
bash install.sh
```

The install script will:
1. Compile the Swift binary
2. Copy it to `/usr/local/bin/mxratchet`
3. Test device access
4. Install and start a LaunchDaemon that enforces ratchet mode every 30s

## Usage

```
sudo mxratchet status              # Show current wheel mode
sudo mxratchet ratchet             # Force ratchet mode (disable SmartShift)
sudo mxratchet freespin            # Force free spin mode
sudo mxratchet watch [--interval N] # Poll and re-apply ratchet (default: 30s)
```

Add `-v` for verbose output showing HID++ packets.

## Uninstall

```bash
sudo launchctl bootout system/com.ivor.mxratchet
sudo rm /Library/LaunchDaemons/com.ivor.mxratchet.plist /usr/local/bin/mxratchet
```

## Supported devices

| Device | PID | Connection |
|--------|-----|-----------|
| MX Master 3 | `0xB023` | Bluetooth |
| MX Master 3 | `0x4082` | Bolt |
| MX Master 3 | `0xC548` | Unifying |

## References

- [HID++ 2.0 SmartShift spec (x2110)](https://lekensteyn.nl/files/logitech/x2110_smartshift.html)
- [Solaar](https://github.com/pwr-Solaar/Solaar) — Linux HID++ implementation
- [niw/HIDPP](https://github.com/niw/HIDPP) — Swift macOS HID++ library

## License

MIT
