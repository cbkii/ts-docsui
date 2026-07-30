# Physical TS18 acceptance procedure

This procedure validates the real TS18 DocumentsUI, stock ExternalStorageProvider and optional root provider. CI cannot prove these behaviours.

Target baseline:

- TS18 `s9863a1h10_Natv` / UIS8581A / SP9863A;
- Android 10 / API 29;
- Magisk 28 or later;
- module ID `ts-docsui`.

Do not change firmware, MCU, CAN, LCD, boot, logo or read-only partitions during this procedure.

## Use the debug variant

Install the exact CI or release asset named:

```text
ts-docsui-debug-v<versionCode>.zip
```

The lean final ZIP does not contain diagnostic scripts. Both variants use the same module ID, so installing the debug ZIP replaces the final ZIP rather than creating a second module.

Run diagnostics from a root Termux shell or Magisk Action:

```sh
su -c 'TS_DOCSUI_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts-docsui/tools/ts18-saf-deepdiag.sh MODE'
```

Replace `MODE` with the stage name below. Replace `com.tw.media` with the exact client package being tested.

All diagnostic work and verified archives are written under:

```text
/storage/emulated/0/Download/ts-docsui/diagnostics/
```

No diagnostic staging is permitted under `/data/adb`.

## Stage 0 — preserve the current baseline

Before installing or updating:

```sh
su -c '/data/adb/modules/ts-docsui/tools/ts18-saf-deepdiag.sh baseline'
```

When no debug module is installed, preserve equivalent package, provider, AppOps, logcat and mount evidence using the current diagnostic module before replacing it.

## Stage 1 — migration boot

1. Install the exact debug ZIP.
2. Reboot once.
3. Wait two minutes after the launcher becomes usable.
4. Run:

```sh
su -c 'TS_DOCSUI_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts-docsui/tools/ts18-saf-deepdiag.sh boot1'
```

Expected:

- package, component, permission, AppOps, preference or ownership mutations are finite and explained;
- no `component-override` sysconfig warning is produced by this module;
- stock `primary:` remains visible;
- root-provider failure does not disable or refresh stock ExternalStorageProvider;
- no continuing alternating external-storage remount burst remains after boot settles.

## Stage 2 — settled second boot

1. Reboot without changing configuration.
2. Wait two minutes after the launcher becomes usable.
3. Run:

```sh
su -c 'TS_DOCSUI_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts-docsui/tools/ts18-saf-deepdiag.sh boot2'
```

Expected:

- latest reconciliation mutations: `0`, unless a specific external state changed;
- no repeated permission or AppOps write;
- no preference/helper replacement;
- no DocumentsUI ownership repair;
- no cache clear or provider force-stop;
- no alternating remount storm.

Any non-zero mutation must be explained before release promotion.

## Stage 3 — picker and ordinary storage

Use the real client app and test separately:

1. `OPEN_DOCUMENT` from `Music`, `Documents`, `Pictures`, `DCIM` and `Download`.
2. `CREATE_DOCUMENT` in a non-Download folder.
3. `OPEN_DOCUMENT_TREE` for `/storage/emulated/0` and a nested folder.
4. USB selection under `/storage/usbdisk0` while a known-good volume is mounted.

Capture immediately before and after each picker action:

```sh
su -c 'TS_DOCSUI_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts-docsui/tools/ts18-saf-deepdiag.sh before-picker'
# perform one picker action
su -c 'TS_DOCSUI_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts-docsui/tools/ts18-saf-deepdiag.sh after-picker'
```

Record the exact action, selected URI and whether the client could read or write through it.

## Stage 4 — persisted URI grant

The client must call `takePersistableUriPermission`; picker display alone is insufficient.

1. Select the Music tree with `OPEN_DOCUMENT_TREE`.
2. Confirm the client reports the selected URI.
3. Capture `after-grant`.
4. Force-stop and reopen the client; read through the same URI.
5. Capture `after-client-restart`.
6. Reboot; read through the same URI again.
7. Capture `after-grant-reboot`.
8. Perform an ACC sleep/wake cycle; read again.
9. Capture `after-grant-acc`.

```sh
su -c 'TS_DOCSUI_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts-docsui/tools/ts18-saf-deepdiag.sh after-grant'
su -c 'TS_DOCSUI_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts-docsui/tools/ts18-saf-deepdiag.sh after-client-restart'
su -c 'TS_DOCSUI_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts-docsui/tools/ts18-saf-deepdiag.sh after-grant-reboot'
su -c 'TS_DOCSUI_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts-docsui/tools/ts18-saf-deepdiag.sh after-grant-acc'
```

The diagnostic bundle records system URI-grant state, but the client must prove real access.

## Stage 5 — root-provider isolation

Test three states independently.

### Root provider disabled

Set `FIX_ENABLE_ROOT_FILE_PROVIDER=0` in:

```text
/data/adb/ts-docsui.conf
```

Reboot and capture `root-disabled`.

Expected: DocumentsUI and stock `primary:` continue to work.

### Root provider enabled, root denied

Enable the provider, deny its Magisk permission and capture:

```sh
su -c 'TS_DOCSUI_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts-docsui/tools/ts18-saf-deepdiag.sh root-denied'
```

Expected:

- picker launch remains responsive;
- ordinary internal storage remains usable;
- root-only content fails clearly;
- no repeated root prompt, AppOps write or remount loop occurs.

### Root provider enabled, root granted

Grant root and capture `root-granted` after browsing a harmless root-only file.

Expected: bounded root-only reads work without affecting stock storage.

Do not test writes under protected system, vendor, metadata, Magisk or Android state paths.

## Stage 6 — USB lifecycle

1. Capture with no USB mounted.
2. Insert one known-good FAT USB volume.
3. Confirm `/storage/usbdisk0` and its picker root appear.
4. Select and read one harmless file.
5. Remove the volume normally.
6. Confirm the picker updates without a remount storm.
7. Capture `usb-inserted` and `usb-removed`.

## Stage 7 — final-variant replacement

After diagnostics are complete:

1. preserve the diagnostic archives and SHA-256 files;
2. install `ts-docsui-v<versionCode>.zip` from the same build or release;
3. reboot;
4. confirm ordinary picker and root-provider behaviour is unchanged;
5. confirm Magisk no longer shows an Action button for this module;
6. confirm `action.sh` and `tools/ts18-saf-deepdiag.sh` are absent from `/data/adb/modules/ts-docsui`.

## Stage 8 — rollback

1. Disable or remove the Magisk module.
2. Reboot.
3. Confirm stock package and provider authorities return to the expected baseline.
4. Confirm no module sysconfig overlay remains.
5. Preserve a final rollback diagnostic archive before replacing or deleting evidence.

Download logs and diagnostic archives are intentionally not removed by module uninstall.

## Release gate

Do not promote the module as physically validated until:

- picker actions work from real clients outside Downloads;
- the second settled boot has no unexplained mutation;
- persisted grants survive client restart, reboot and ACC sleep/wake;
- root denial cannot break stock storage;
- USB lifecycle works;
- no unsupported sysconfig warning or sustained remount storm remains;
- the final variant behaves like the debug variant without diagnostic payload;
- disable/remove plus reboot restores the prior package/provider state.
