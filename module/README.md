# TS18 Full File Picker

This Magisk module fixes the Android file picker on supported TS18 Android 10 car head units.

## What it fixes

Some TS18 units show only **Downloads** and USB storage in the file picker. This module makes the rest of the internal storage available and adds a separate root file source.

After reboot, the picker can show:

- normal internal storage;
- **Internal storage (full)**;
- **Root file system**;
- connected TS18 USB storage.

## Requirements

- Topway TS18 with Android 10;
- UIS8581A / SC9863A TS18 hardware;
- Magisk 28 or later already working.

Do not use this module on TS10, TS10S, or unrelated units.

## Installation

Install the ZIP from **Magisk > Modules > Install from storage**, then reboot.

If Magisk asks for root access for the file provider, allow it.

## Help and diagnostics

In Magisk, open this module and press **Action**. The diagnostic ZIP is saved under:

```text
/storage/emulated/0/Download/TS18-SAF-Diagnostics/
```

Project guides:

- English: https://github.com/cbkii/ts-docsui/blob/main/README.md
- 简体中文: https://github.com/cbkii/ts-docsui/blob/main/README.zh-CN.md
- Русский: https://github.com/cbkii/ts-docsui/blob/main/README.ru.md
- Technical guide: https://github.com/cbkii/ts-docsui/blob/main/docs/DEVELOPMENT.md

## Safety

The module does not flash firmware partitions. The **Root file system** entry has real root access, so do not change or delete files that you do not understand.
