# TS18 Full File Picker

[English](README.md) | [简体中文](README.zh-CN.md) | [Русский](README.ru.md)

This Magisk module fixes the Android file picker on supported TS18 car head units.

## Why this module exists

On some TS18 units, the file picker shows only **Downloads** and USB storage. Apps cannot choose files or folders from the rest of the internal storage.

This module restores the normal Android 10 file picker and adds an extra root file source.

## What it provides

- Access to all normal internal storage under `/storage/emulated/0`.
- An extra **Internal storage (full)** entry.
- A **Root file system** entry for files that need Magisk root access.
- TS18 USB storage when a USB drive is connected.
- File and folder selection for apps that use the Android system picker.

## Requirements

- A Topway **TS18** unit with Android 10.
- UIS8581A / SP9863A TS18 hardware.
- Magisk 28 or later already working.

This module is not for TS10, TS10S, or unrelated units that only look similar.

## Source of the rooted firmware

The Magisk-rooted TS18 firmware used with this project is sourced from the [Topway TS10 and TS18 community topic on 4PDA](https://4pda.to/forum/index.php?showtopic=1015856).

4PDA is a third-party community. This project does not create, host, or verify the firmware found there.

Only use firmware that exactly matches your unit's system version, board, screen, panel, and boot configuration. The wrong firmware can stop the unit from starting. Make a full backup before changing firmware. Stop when the match is not certain.

You do not need to reinstall firmware when Magisk already works on your unit.

## Installation

1. Download the module ZIP from the [latest release](https://github.com/cbkii/ts-docsui/releases/latest).
2. Open **Magisk**.
3. Open **Modules** and choose **Install from storage**.
4. Select the downloaded ZIP.
5. Reboot the head unit.

After the reboot, open a file picker from an app. You should see normal internal storage, full internal storage, and the root file system. USB entries appear only when USB storage is connected.

## When it does not work

1. Confirm that the unit is TS18, Android 10, and already rooted with Magisk.
2. Reboot once after installing or updating the module.
3. In Magisk, open this module and press **Action**.
4. Find the diagnostic ZIP in:

```text
/storage/emulated/0/Download/TS18-SAF-Diagnostics/
```

Attach that ZIP to a new GitHub issue. Do not install different firmware only to test this module.

## Safety

The module is systemless. It does not flash boot, MCU, CAN, LCD, logo, or firmware partitions.

The **Root file system** entry has real root access. Do not change or delete files that you do not understand. Read-only system partitions remain read-only.

## Technical information

Developers and advanced users should read the [technical and developer guide](docs/DEVELOPMENT.md).
