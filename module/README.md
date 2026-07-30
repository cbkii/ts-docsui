# ts-docsui

This Magisk module repairs the Android file picker on supported TS18 Android 10 head units. It keeps the stock Android provider for ordinary shared storage and adds a separate Magisk-backed provider for full/root paths.

## Requirements

- Topway TS18 / UIS8581A / SP9863A hardware;
- Android 10 / API 29;
- Magisk 28 or later already working.

Do not treat TS10, TS10S or unrelated UIS8581A units as interchangeable.

## Installation

Install one release ZIP from **Magisk > Modules > Install from storage**, then reboot.

- `ts-docsui-v<versionCode>.zip` is the lean final module.
- `ts-docsui-debug-v<versionCode>.zip` adds diagnostics and the Magisk **Action** entry.

Both variants use module ID `ts-docsui`; installing one replaces the other.

## Runtime files

Small required runtime state:

```text
/data/adb/ts-docsui/
/data/adb/ts-docsui.conf
```

Logs and diagnostic output:

```text
/storage/emulated/0/Download/ts-docsui/logs/
/storage/emulated/0/Download/ts-docsui/diagnostics/
```

The final variant does not contain diagnostic scripts. In the debug variant, press **Action** in Magisk to create a verified diagnostic archive.

## Safety

The module does not flash firmware, boot, MCU, CAN, LCD or logo partitions. The root source has real root access, but read-only device-mapper mounts remain read-only. Do not modify protected Android, vendor, metadata or Magisk state paths.
