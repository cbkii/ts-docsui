# TS18 Full File Picker

This Magisk module repairs the Android 10 system file picker on TS18-class head units.

## What it provides

- Android 10 DocumentsUI for `GET_CONTENT`, `OPEN_DOCUMENT`, `CREATE_DOCUMENT`, and `OPEN_DOCUMENT_TREE`.
- The stock Android `primary:` root for all of `/storage/emulated/0`, shown by default.
- Action-scoped `includeDeviceRoot-1` through `includeDeviceRoot-8` preferences required by the bundled Android 10 picker.
- A separate **Internal storage (full)** source that lists shared storage without invoking root during picker startup.
- A **Root file system** source for `/`, including app-private and system paths ordinary storage permissions cannot read.
- Optional TS18 USB roots at `/storage/usbdisk0` and `/storage/usbdisk1`.
- Create, read, write, rename, move, copy, and delete operations where the mounted filesystem permits them.
- Manual diagnostics exported to `/storage/emulated/0/Download/TS18-SAF-Diagnostics`.

## Important behaviour

The normal Android ExternalStorageProvider remains the preferred provider for `/storage/emulated/0`. Exact TS18 diagnostics proved that it publishes `primary:` and enumerates the internal-storage top level.

Picker discovery never invokes `su`. The bundled root provider registers its roots and returns local metadata first; bounded Magisk helper calls begin only after root-only content is opened. A missing root policy therefore cannot freeze the normal picker or stock internal-storage source.

During upgrade the module repairs DocumentsUI private-data ownership, disables the obsolete `com.ts18.safprovider` experiment and App Manager picker interception, enables the complete DocumentsUI entrypoint set, clears stale preferred-activity state, and records resolver health under `/data/adb/ts18-documentsui-saf/`.

Pre-schema-2 runtime configuration is backed up and migrated once to keep exact-device-proven `primary:` visible. Later user choices are preserved.

Root cannot make read-only device-mapper mounts writable. `/system`, `/vendor`, and similar partitions remain read-only; the provider can still browse and read them.

Seekable root-file editing uses `/storage/emulated/0/.TS18-Root-Provider`. Closed staging files are removed and stale files are cleaned during boot. The module does not use `/tmp`, `/cache`, or `/data/local/tmp` for runtime staging.

## Configuration

Edit `/data/adb/ts18-documentsui-saf.conf`, then reboot. Every setting is documented in the file.

## Manual picker test

```sh
su -c '/data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-launch.sh internal'
```

Resolver and launch output is written to `/storage/emulated/0/Download/TS18-SAF-launch.log`.

## Diagnostics

Press **Action** in Magisk, or run:

```sh
su -c '/data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-deepdiag.sh full'
```

The verified archive is written under `/storage/emulated/0/Download/TS18-SAF-Diagnostics/`.

## Rollback

Disable or remove the module in Magisk and reboot. No boot, MCU, CAN, LCD, logo, or firmware partition is modified.
