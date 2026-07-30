# 📂 File Picker for TS18

[English](README.md) | [简体中文](README.zh-CN.md) | [Русский](README.ru.md)

`ts-docsui` is a Magisk module for supported Topway TS18 Android 10 head units. It restores the Android system file picker, exposes normal internal storage and adds a separate Magisk-backed root file source.

## What it provides

- Normal internal storage under `/storage/emulated/0` through Android's stock ExternalStorageProvider.
- An **Internal storage (full)** source.
- A **Root file system** source for root-only paths.
- TS18 USB storage when a compatible USB volume is mounted.
- File and folder selection for apps that use Android SAF.

> [!TIP]
> A TS18 directory can initially appear empty even when it is not. Refresh the current folder before treating that result as a provider failure.

## Requirements

- Topway TS18 / UIS8581A / SP9863A hardware matching the supported Android 10 platform.
- Android 10 / API 29.
- Magisk 28 or later already working.

Do not assume TS10, TS10S or visually similar units are interchangeable. This module does not install Magisk or root the head unit.

## Release variants

Every release contains two installable ZIPs with the same runtime implementation:

- `ts-docsui-v<versionCode>.zip` — the lean final module. It contains essential runtime components only.
- `ts-docsui-debug-v<versionCode>.zip` — the debug module. It additionally contains the bounded diagnostics collector and a Magisk **Action** entry point.

Use the final module for normal operation. Install the debug module only while collecting evidence or diagnosing a problem. Do not install both at once; both use the module ID `ts-docsui`.

## Installation

1. Download one ZIP from the [latest release](https://github.com/cbkii/ts-docsui/releases/latest).
2. In Magisk, open **Modules** and choose **Install from storage**.
3. Select the ZIP.
4. Reboot the head unit.

After reboot, open a file picker from an app. Normal internal storage should remain the stock Android source. The separate full/root entries are supplied by the root provider. USB entries appear only while USB storage is mounted.

## Diagnostics

Diagnostics are included only in the debug variant. Press **Action** in Magisk, or run:

```sh
su -c '/data/adb/modules/ts-docsui/tools/ts18-saf-deepdiag.sh full'
```

All diagnostic work, logs and verified archives stay under:

```text
/storage/emulated/0/Download/ts-docsui/diagnostics/
```

Normal service and installer logs are kept under:

```text
/storage/emulated/0/Download/ts-docsui/logs/
```

`/data/adb/ts-docsui` is reserved for the small helper, generated preferences and reconciliation markers required at runtime.

## Safety

The module is systemless. It does not flash boot, MCU, CAN, LCD, logo or firmware partitions.

The root source has real root access, but root does not make read-only device-mapper mounts writable. Do not modify protected system, vendor, metadata, Magisk or Android state paths.

The rooted firmware used by this project came from the [Topway TS10 and TS18 community topic on 4PDA](https://4pda.to/forum/index.php?showtopic=1015856). That firmware is external to this repository and is not proof that another unit is compatible.

## Technical information

Developers and advanced users should read the [technical guide](docs/DEVELOPMENT.md) and [physical TS18 acceptance procedure](docs/DEVICE_ACCEPTANCE.md).
