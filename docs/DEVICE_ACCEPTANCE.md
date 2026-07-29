# Physical TS18 acceptance procedure

This procedure validates the real TS18 DocumentsUI, stock ExternalStorageProvider and optional root provider. CI cannot prove these behaviours.

Target baseline:

- TS18 `s9863a1h10_Natv` / UIS8581A / SP9863A;
- Android 10 / API 29;
- Magisk 28 or later;
- module ID `ts18_documentsui_saf_full`.

Do not change firmware, MCU, CAN, LCD, boot, logo or read-only partitions during this procedure.

## Diagnostic command

Run from a root Termux shell or Magisk Action:

```sh
su -c 'TS18_SAF_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-evidence-v2.sh MODE'
```

Replace `MODE` with the stage name below. Replace `com.tw.media` with the exact client package being tested. The collector is package-version agnostic and records the live package identity.

Verified archives are written to:

```text
/storage/emulated/0/Download/TS18-SAF-Diagnostics/
```

## Stage 0 — preserve the current baseline

Before installing or updating the module:

```sh
su -c '/data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-evidence-v2.sh baseline'
```

When the module is not yet installed, preserve equivalent package, provider, AppOps, logcat and mount evidence using the prior installed module or a root diagnostic shell.

## Stage 1 — migration boot

1. Install the exact CI Magisk ZIP.
2. Reboot once.
3. Wait two minutes after the launcher becomes usable.
4. Do not repeatedly open the picker while boot reconciliation is still running.
5. Run:

```sh
su -c 'TS18_SAF_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-evidence-v2.sh boot1'
```

Expected:

- any package, component, permission, AppOps, preference or ownership mutation is finite and explained;
- no warning says `Tag component-override is unknown` for this module;
- stock `primary:` remains visible;
- root-provider failure does not disable or refresh stock ExternalStorageProvider;
- no continuing alternating external-storage remount burst remains after the boot settles.

## Stage 2 — settled second boot

1. Reboot without changing module configuration.
2. Wait two minutes after the launcher becomes usable.
3. Run:

```sh
su -c 'TS18_SAF_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-evidence-v2.sh boot2'
```

Expected:

- latest reconciliation mutations: `0`;
- package/component state: no change;
- permissions and AppOps: no write;
- preference/helper files: no replacement;
- DocumentsUI ownership: no recursive repair;
- no cache clear or provider force-stop;
- no alternating remount storm.

A non-zero mutation count is not automatically unsafe, but it must be explained before release promotion.

## Stage 3 — picker and ordinary storage

Use the real client app and test separately:

1. `OPEN_DOCUMENT` from `Music`, `Documents`, `Pictures`, `DCIM` and `Download`.
2. `CREATE_DOCUMENT` in a non-Download internal folder.
3. `OPEN_DOCUMENT_TREE` for `/storage/emulated/0` and a nested folder.
4. USB selection under `/storage/usbdisk0` when a USB volume is mounted.

Capture before opening the picker and immediately after the result returns:

```sh
su -c 'TS18_SAF_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-evidence-v2.sh before-picker'
# perform one picker action
su -c 'TS18_SAF_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-evidence-v2.sh after-picker'
```

Record the exact action, selected URI and whether the client could read or write through that URI.

## Stage 4 — persisted URI grant

The client must call `takePersistableUriPermission`; picker display alone is not enough.

1. Select the Music tree with `OPEN_DOCUMENT_TREE`.
2. Confirm the client reports the selected URI.
3. Capture `after-grant`.
4. Force-stop and reopen the client; read through the same URI.
5. Capture `after-client-restart`.
6. Reboot; read through the same URI again.
7. Capture `after-grant-reboot`.
8. Perform an ACC sleep/wake cycle; read again.
9. Capture `after-grant-acc`.

Commands:

```sh
su -c 'TS18_SAF_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-evidence-v2.sh after-grant'
su -c 'TS18_SAF_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-evidence-v2.sh after-client-restart'
su -c 'TS18_SAF_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-evidence-v2.sh after-grant-reboot'
su -c 'TS18_SAF_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-evidence-v2.sh after-grant-acc'
```

The diagnostic bundle records system URI-grant state, but the client must also prove real access.

## Stage 5 — root-provider isolation

Test three states independently:

### Root provider disabled

Set `FIX_ENABLE_ROOT_FILE_PROVIDER=0`, reboot and capture `root-disabled`.

Expected: DocumentsUI and stock `primary:` still work.

### Root provider enabled, Magisk root denied

Enable the provider, deny its Magisk request and capture:

```sh
su -c 'TS18_SAF_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-evidence-v2.sh root-denied'
```

Expected:

- picker launch remains responsive;
- ordinary internal storage remains usable;
- root-only content fails clearly;
- no repeated root prompt, AppOps write or remount loop occurs.

### Root provider enabled, Magisk root granted

Grant root and capture `root-granted` after browsing a regular root-only file.

Expected: bounded root-only operations work without affecting stock storage.

Do not test writes under protected system, vendor, metadata, Magisk or Android state paths.

## Stage 6 — USB lifecycle

1. Capture with no USB mounted.
2. Insert one known-good FAT USB volume.
3. Confirm `/storage/usbdisk0` and its picker root appear.
4. Select and read one harmless file.
5. Remove the volume normally.
6. Confirm the picker updates without a remount storm.
7. Capture `usb-inserted` and `usb-removed`.

## Stage 7 — rollback

1. Disable the Magisk module.
2. Reboot.
3. Confirm stock packages and provider authorities return to the expected baseline.
4. Confirm no module sysconfig overlay remains.
5. Preserve a final `rollback` diagnostic archive before deleting any state.

## Release gate

Do not promote the module as physically validated until:

- picker actions work from real clients;
- the second settled boot has no unexplained mutation;
- persisted grants survive client restart, reboot and ACC sleep/wake;
- root denial cannot break stock storage;
- USB lifecycle works;
- no unsupported sysconfig warning or remount storm remains;
- disable/remove plus reboot restores the prior package/provider state.
