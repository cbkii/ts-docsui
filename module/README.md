# TS18 Full File Picker

This Magisk module repairs the Android 10 system file picker on TS18-class head units.

## What it provides

- Android 10 DocumentsUI for `GET_CONTENT`, `OPEN_DOCUMENT`, `CREATE_DOCUMENT`, and `OPEN_DOCUMENT_TREE`.
- The normal Android `primary:` root for all of `/storage/emulated/0`, shown by default.
- A separate **Internal storage (full)** root that lists shared storage directly before using root as a fallback.
- A **Root file system** root for `/`, including app-private and system paths ordinary storage permissions cannot read.
- Optional TS18 USB roots at `/storage/usbdisk0` and `/storage/usbdisk1`.
- Create, read, write, rename, move, copy, and delete operations through the root provider where the mounted filesystem permits them.
- Manual diagnostics from the Magisk Action button, exported to `/storage/emulated/0/Download/TS18-SAF-Diagnostics`.

## Important behaviour

The normal Android ExternalStorageProvider remains the preferred provider for `/storage/emulated/0` because it offers native seekable file descriptors and Android-compatible URI behaviour. Exact TS18 diagnostics proved its `primary:` root works, so the repaired configuration does not hide it after one transient boot-time query failure.

The bundled root provider is separate. Picker discovery, root registration, root metadata and shallow `/` listing do **not** invoke `su`; this prevents a missing Magisk policy or root prompt from freezing the entire picker. Bounded root helper calls begin only after root-only content is opened.

During upgrade the module repairs DocumentsUI private-data ownership, removes the obsolete `com.ts18.safprovider` experiment, disables App Manager's picker interceptor, enables the complete DocumentsUI component set, clears stale preferred-activity records and records resolver health under `/data/adb/ts18-documentsui-saf/`.

The root provider uses Magisk `su`. The module normally creates an allow policy for its package automatically. When automatic policy creation is unavailable, the normal picker and `primary:` storage remain usable; Magisk may request root only when a root-only source is opened.

Root access cannot make read-only device-mapper mounts writable. `/system`, `/vendor`, and similar partitions remain read-only unless the firmware mounted them writable. The root provider can still browse and read them.

Seekable root-file editing uses a short-lived hidden staging folder under `/storage/emulated/0/.TS18-Root-Provider`. A staged file is removed when the client closes it; stale files older than one hour are removed during boot. Root-provider staging never uses `/tmp`, `/cache`, `/data/local/tmp`, or a top-level scratch folder under `/data`.

## Configuration

Edit `/data/adb/ts18-documentsui-saf.conf`, then reboot. Every setting has a plain-English comment in the file. Upgrades from pre-schema-2 configurations are backed up and migrated once to the repaired picker defaults.

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

The final archive is written under:

```text
/storage/emulated/0/Download/TS18-SAF-Diagnostics/
```

Temporary diagnostic work is also kept under that Download folder and removed after the archive is verified. The collector does not use `/tmp`, `/cache`, or `/data/local/tmp`.
