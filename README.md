# BleKey Studio

BleKey Studio is a native macOS utility for configuring XKey-compatible
Bluetooth keypads. It uses AppKit, CoreBluetooth, and a small Swift package for
the feature implementation. The UI is written in AppKit, not SwiftUI or
storyboards. No third-party runtime dependencies are added.

## Compatibility

Compatibility is determined by the BLE service and packet protocol, not by a
product name alone.

| Status | Device or platform | Scope |
| --- | --- | --- |
| Verified | `3KEY_1` three-key BLE keypad | Device discovery, connection and key-mapping writes have been exercised on hardware. Sleep persistence still needs broader hardware verification. |
| Protocol candidate | 1–24 key XKey-compatible BLE keypads | The device must expose service `FFE6`, writable characteristic `FFE7`, and accept the four-byte mapping/sleep packets documented below. These devices are not automatically considered verified. |
| Unsupported | Generic BLE HID keyboards and macro pads | Standard HID support alone is insufficient; BleKey Studio requires the vendor configuration service and protocol. |
| Unsupported | USB-only or Bluetooth Classic devices | The current transport is CoreBluetooth Low Energy only. |

The leading number in a device name, such as `3KEY_1`, is used only as a key
count hint. The key count can be set manually from 1 to 24. A matching name does
not prove protocol compatibility.

### Host support

- macOS 13 or later.
- The packaged DMG is currently built and verified for Apple Silicon (`arm64`).
- Intel (`x86_64`) builds and other Apple platforms have not been verified.

### Supported configuration surface

- 1–24 physical keys and 10 layers.
- Standard keyboard actions, left/right modifiers, modifier-only mappings,
  pointer actions, media controls, and the system actions listed by the app.
- Sleep timeout writes using the known XKey timeout codes.
- Read-only inspection of GATT characteristics that explicitly advertise
  `Read`.

### Known protocol limits

- No key-mapping readback command has been verified.
- A successful GATT write confirms transport completion, not firmware
  persistence.
- Devices using the same UUIDs with different packet semantics require separate
  validation before they should be marked compatible.

## Features

- Discover and connect to paired XKey-compatible BLE devices.
- Configure 1 to 24 physical keys across 10 device layers.
- Edit mappings in one central list and editor, with an optional keyboard below.
- Graphite dark controls, tactile keycaps, and a red selection accent.
- Pick keys from an interactive MacBook Pro ANSI keyboard.
- Record shortcuts with live modifier feedback and a cancel control; Escape remains assignable.
- Start recording by clicking the field, double-clicking a mapping row or pressing Return in the table.
- Search actions by name or alias, with keyboard navigation and explicit selection.
- Assign a modifier by itself, or click the selected primary key again to remove only that key.
- Assign keyboard, media, pointer, and system actions.
- Configure sleep timeout from 1 minute to 4 hours, or disable sleep.
- Save, duplicate, rename, import, and export local profiles.
- Undo and redo mapping changes.
- Write only pending changes and retain failures for retry.
- Inspect the exact four-byte command before writing.
- Inspect readable configuration characteristics without sending query payloads.
- Validate imported profiles before changing the local library.
- Keep unreadable libraries protected, with retry and backup-based recovery.
- Show unsaved edits after disk errors, retry saving or export a complete rescue copy.
- Confirm quitting with unsaved edits and wait for active device operations.
- Distinguish local drafts, saved edits, pending device writes and unverified delivery.
- Keep local edit and Bluetooth transport activity in a persistent, revealable log file.

Sleep is left unchanged until explicitly selected. Real-device writes show the
pending overrides for confirmation. Demo mode is labeled and uses separate data.

The device protocol supports writing but no readback command has been verified.
The app therefore distinguishes local drafts from settings last sent by this
app. It never presents a local profile as data read from the device.

## Protocol

```text
Service: FFE6
Write characteristic: FFE7
Notify characteristic: 1002

Mapping: [layer][physical key][modifier or action family][HID/action code]
Sleep:   FF FF FF [timeout code]
```

Layer 10 is encoded as `0x10`. Keyboard modifiers use the standard USB HID
modifier bitmask. Pointer actions use `0xFE` in byte three; media and system
actions use `0xFD`.
Four hours uses the special timeout code `0xFF`; timeout codes are not uniformly
minute counts. A GATT write completion is not a configuration readback or proof
of firmware persistence.

## Development

Open `BleKeyStudio.xcworkspace` in Xcode 26 or build with XcodeBuildMCP:

```bash
xcodebuildmcp macos build \
  --workspace-path ./BleKeyStudio.xcworkspace \
  --scheme BleKeyStudio
```

Run protocol and persistence tests:

```bash
xcodebuildmcp swift-package test \
  --package-path ./BleKeyStudioPackage
```

Set `DEVELOPER_DIR` when Xcode is installed at a nonstandard path.

Launch with `--demo` to exercise the complete interface without writing to a
Bluetooth device.

Create the installable disk image:

```bash
./Scripts/package.sh
```

The Apple Silicon DMG is written to `dist/BleKey-Studio-0.3.4.dmg`.
It is ad-hoc signed for local testing, not Developer ID signed or notarized.
Hardware configuration readback has not been verified. The Windows vendor
client's read button reads the standard Device Name characteristic (1800/2A00),
not a key-mapping table.

## Local Data Recovery

Saving is automatic. A persistent error banner is shown when reading or saving
fails. Device writes are disabled until local storage recovers. Failed saves
retain in-memory edits and require confirmation before quitting.

The rescue-copy action exports the entire local library. Profile import accepts
either a single profile or a complete library and merges it without trusting
device bindings or old sent-state records. If the original library cannot be
read, recovery first copies it to a uniquely named `profiles-unreadable-*.json`
file alongside the library, then writes the validated replacement. If that
backup cannot be created, recovery stops without overwriting the original.

JSON documents use `documentVersion: 1`; earlier versionless files remain
supported. Unsupported versions, invalid addresses/actions, duplicate mappings
and malformed libraries are rejected before use.

## Structure

```text
BleKeyStudio/                         AppKit application entry and assets
BleKeyStudioPackage/Sources/
  BleKeyStudioFeature/
    Models.swift                      Profiles and mapping state
    ActionCatalog.swift               Keyboard/media/pointer/system actions
    XKeyProtocol.swift                Four-byte command encoder
    BluetoothController.swift         CoreBluetooth transport and write queue
    ActivityLogStore.swift            Persistent local edit and transport log
    AppCoordinator.swift              Window and application menu
    WorkspaceViewController.swift     Navigation and unified mapping editor
    KeyboardCanvasView.swift          Interactive MacBook keyboard
    Theme.swift                       Graphite palette and surface drawing
    StudioControls.swift              Native controls with custom appearance
    ShortcutRecorderView.swift        Physical shortcut capture
    ActionPickerViewController.swift  Searchable action picker
    PhysicalKeypadView.swift          Source keypad visualization
    ActionPaletteView.swift           Non-keyboard action browser
Scripts/                              Reproducible icon and packaging tools
```
