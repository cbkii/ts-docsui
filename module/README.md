# TS18 Full File Picker

This Magisk module repairs the Android 10 system file picker on TS18-class head units.

## What it provides

- Android 10 DocumentsUI for `OPEN_DOCUMENT`, `CREATE_DOCUMENT`, and `OPEN_DOCUMENT_TREE`.
- The normal Android `primary:` root for all of `/storage/emulated/0` when its live root and child queries pass.
- A separate **Internal storage (full)** root backed by Magisk root.
- A **Root file system** root for `/`, including app-private and system paths that ordinary storage permissions cannot read.
- Optional TS18 USB roots at `/storage/usbdisk0` and `/storage/usbdisk1`.
- Create, read, write, rename, move, copy, and delete operations through the root provider where the mounted filesystem permits them.
- Manual diagnostics from the Magisk Action button, exported to `/storage/emulated/0/Download/TS18-SAF-Diagnostics`.

## Important behaviour

The normal Android ExternalStorageProvider remains the preferred provider for `/storage/emulated/0` because it offers native seekable file descriptors and Android-compatible URI behaviour. The bundled root provider is an additional provider for root-only paths and a fallback internal-storage root.

The root provider uses Magisk `su`. The module normally creates an allow policy for its package automatically. When automatic policy creation is unavailable, Magisk may show one root request.

Root access cannot make read-only device-mapper mounts writable. `/system`, `/vendor`, and similar partitions remain read-only unless the firmware mounted them writable. The root provider can still browse and read them.

## Configuration

Edit `/data/adb/ts18-documentsui-saf.conf`, then reboot. Every setting has a plain-English comment in the file.

## Diagnostics

Press **Action** in Magisk, or run:

```sh
su -c '/data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-deepdiag.sh full'
```

The final archive is written under:

```text
/storage/emulated/0/Download/TS18-SAF-Diagnostics/
```

Temporary diagnostic work is also kept under that Download folder and removed after the archive is verified. The collector does not use `/tmp`, `/cache`, or `/data/local/tmp`.
