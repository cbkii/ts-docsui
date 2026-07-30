# Technical and developer guide

User guides:

- [English](../README.md)
- [简体中文](../README.zh-CN.md)
- [Русский](../README.ru.md)

## Scope

This project targets Topway TS18 Android 10/API 29 head units on UIS8581A / SP9863A hardware with Magisk 28 or later.

Do not assume TS18, TS10, TS10S or other UIS8581A units are interchangeable. Firmware, board, panel, boot, LCD, MCU, CAN and populated hardware must match before any device-level change.

The module ID is:

```text
ts-docsui
```

The project intentionally serves the current implementation only. It does not retain alternate module IDs, legacy diagnostic wrappers or old split evidence collectors.

## Architecture

```text
Client app
  -> Android DocumentsUI picker
     -> stock com.android.externalstorage.documents
        -> /storage/emulated/0 and mounted TS18 USB volumes
     -> com.cbkii.tsdocsui.root.documents
        -> local discovery and shared-storage listing
        -> bounded Magisk helper for root-only paths
```

The stock Android ExternalStorageProvider remains authoritative for ordinary shared storage. It returns Android-compatible document URIs and native seekable file descriptors.

The bundled root provider is separate. It supplies:

- `Internal storage (full)` for `/storage/emulated/0`;
- `Root file system` for `/`;
- available `/storage/usbdisk0` and `/storage/usbdisk1` roots.

Root access does not make read-only device-mapper mounts writable. `/system`, `/vendor` and similar mounts remain read-only unless the firmware itself mounted them writable.

## Runtime authority and state

PackageManager runtime reconciliation is authoritative for package and component enablement. The module does not ship the exact-device-unsupported `component-override` sysconfig payload.

Small required state is stored at:

```text
/data/adb/ts-docsui/
/data/adb/ts-docsui.conf
```

That state is limited to the root helper, generated preference files while they are being applied, the applied picker-state marker and the one-time preferred-activity marker.

Potentially large output is kept out of `/data/adb`:

```text
/storage/emulated/0/Download/ts-docsui/logs/
/storage/emulated/0/Download/ts-docsui/diagnostics/
```

The service uses `/dev/null` rather than falling back to `/data/adb` when shared-storage logging is unavailable.

## Internal storage visibility

Exact-device diagnostics showed that the stock provider publishes the `primary:` root and can list `/storage/emulated/0`. The remaining visibility failure was in DocumentsUI preferences.

The module writes `includeDeviceRoot-1` through `includeDeviceRoot-8` together with the older compatibility keys used by this Android 10 picker. The default `EXTERNAL_ROOT_MODE=show` keeps the proven `primary:` root visible. Optional `auto` mode hides it only after a bounded provider query definitively reports that the root is unavailable; an inconclusive timeout keeps it visible.

## Root-provider operation

Provider identity:

```text
package:   com.cbkii.tsdocsui.rootprovider
authority: com.cbkii.tsdocsui.root.documents
```

The narrow Magisk helper is installed at:

```text
/data/adb/ts-docsui/rootfs-helper.sh
```

Seekable editing of root-only files uses:

```text
/storage/emulated/0/.ts-docsui-root-provider
```

Closed staging files are removed immediately by the provider. Stale stage files are removed during boot. The module does not use `/tmp`, `/cache` or `/data/local/tmp` for work.

Root-provider failure is isolated from stock storage. Failure to install the helper, denial of Magisk permission or failure to enable the custom provider must not disable, clear or rewrite `com.android.externalstorage`.

## Release variants

The source module contains runtime code plus the single current diagnostics collector. The ZIP builder produces two deterministic variants:

```text
ts-docsui-v<versionCode>.zip
ts-docsui-debug-v<versionCode>.zip
```

The final ZIP excludes:

```text
action.sh
tools/ts18-saf-deepdiag.sh
```

The debug ZIP includes both. All other runtime files are identical. Both variants use module ID `ts-docsui`, so installing either one replaces the other.

`update.json` always points to the final ZIP. GitHub releases include both ZIPs and both SHA-256 files.

## Repository layout

```text
rootprovider/                   Android DocumentsProvider source
module/                         Source Magisk payload
scripts/build-root-provider.py  Build and sign the provider APK
scripts/release_version.py      Resolve and apply release versions
scripts/build-magisk-zip.py     Build final or debug ZIP
scripts/release_assets.py       Validate the lean final release asset
scripts/validate-module.py      Validate source payload and safety boundaries
tests/                          Release, variant and runtime contract tests
.github/workflows/ci.yml        Build both variants on changes
.github/workflows/release-magisk-module.yml
```

`module/module.prop` is the sole persistent release version source. The Android provider build derives `versionName` and `versionCode` from it. Runtime scripts read the installed `module.prop`; there is no secondary version-synchronisation script.

## Local validation

Basic checks:

```bash
python3 -m compileall -q scripts tests
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 scripts/release_version.py --repo-root . --module-prop module/module.prop
find module -type f -name '*.sh' -print -exec sh -n {} ';'
sh -n module/META-INF/com/google/android/update-binary
```

A full provider and module build requires JDK 17, Android SDK 35 and Gradle 8.7 or later:

```bash
python3 scripts/build-root-provider.py --repo-root . --gradle gradle --timeout 900
python3 scripts/validate-module.py --module-dir module
python3 scripts/build-magisk-zip.py --module-dir module --out-dir dist --variant final
python3 scripts/build-magisk-zip.py --module-dir module --out-dir dist --variant debug
```

Validate that both archives are STORE-only and non-ZIP64. The final archive must not contain the debug-only files; the debug archive must contain both.

## Release process

The manual release workflow supports an explicit `version_tag`, or an automatic patch increment when blank; an explicit numeric `version_code`, or the current code plus one when blank; draft and prerelease states; and exact-tag asset replacement without moving a tag.

For a new release, the workflow:

1. confirms the default branch and remote head;
2. updates and commits only `module/module.prop`;
3. builds and validates the signed provider;
4. builds final and debug ZIPs from the same source commit;
5. validates both checksums and inventories;
6. generates `update.json` from the final ZIP;
7. creates an immutable annotated tag on the exact source commit;
8. publishes both ZIPs, both SHA-256 files and `update.json`.

## Diagnostics

Diagnostics are present only in the debug ZIP. Run the Magisk **Action** or:

```sh
su -c '/data/adb/modules/ts-docsui/tools/ts18-saf-deepdiag.sh full'
```

The collector is user-started, bounded and local-only. It records package/provider state, AppOps, URI grants, process mount namespaces, storage state, filtered logs, remount evidence and root-helper smoke results. It copies APK hashes rather than APK payloads. Work and the final verified archive stay under:

```text
/storage/emulated/0/Download/ts-docsui/diagnostics/
```

## Device acceptance

CI proves source, APK, script, metadata and ZIP structure. It cannot prove physical TS18 behaviour.

Before release promotion, validate:

- real `OPEN_DOCUMENT`, `CREATE_DOCUMENT` and `OPEN_DOCUMENT_TREE` flows;
- selection outside Downloads;
- persistable URI access after client restart, reboot and ACC sleep/wake;
- root provider disabled, root denied and root granted;
- USB insertion and removal;
- a settled second boot with no unexplained reconciliation mutations;
- no sustained external-storage remount storm;
- module disable/remove and reboot rollback.

Use [DEVICE_ACCEPTANCE.md](DEVICE_ACCEPTANCE.md) for the exact procedure.

## Safety

The module is systemless. It does not flash boot, MCU, CAN, LCD, logo or firmware partitions.

The root provider exposes sensitive files and can modify writable paths. Do not test writes under protected system, vendor, metadata, Magisk or Android state paths.
