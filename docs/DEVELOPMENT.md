# Technical and developer guide

This document contains the advanced information moved out of the beginner README.

User guides:

- [English](../README.md)
- [简体中文](../README.zh-CN.md)
- [Русский](../README.ru.md)

## Scope

This project targets Topway TS18 Android 10 head units on UIS8581A / SP9863A hardware with Magisk 28 or later.

Do not assume that TS18, TS10, TS10S, or other UIS8581A units are interchangeable. Firmware, board, panel, boot, LCD, MCU, CAN, and populated hardware must match before any device-level change.

The module ID is:

```text
ts18_documentsui_saf_full
```

The ID remains unchanged so existing installations are upgraded instead of creating a second active module.

## Architecture

```text
Client app
  -> Android DocumentsUI picker
     -> stock com.android.externalstorage.documents
        -> /storage/emulated/0 and mounted TS18 USB volumes
     -> com.cbkii.tsdocsui.root.documents
        -> Magisk su helper
           -> / and root-only paths
```

The stock Android ExternalStorageProvider is retained. It is the preferred provider for normal shared storage because it returns Android-compatible document URIs and native seekable file descriptors.

The bundled root provider is separate. It supplies:

- `Internal storage (full)` for `/storage/emulated/0`;
- `Root file system` for `/`;
- available `/storage/usbdisk0` and `/storage/usbdisk1` roots.

Root access does not make read-only device-mapper mounts writable. `/system`, `/vendor`, and similar mounts remain read-only unless the firmware itself mounted them writable.

## Why internal storage was hidden

Exact-device diagnostics proved that the stock provider publishes the `primary:` root and can list the top level of `/storage/emulated/0`.

The remaining failure was in DocumentsUI preferences. This Android 10/Pie picker stores the advanced-device choice separately for each picker action. It reads keys in this form:

```text
includeDeviceRoot-<action>
```

The module writes `includeDeviceRoot-1` through `includeDeviceRoot-8`, together with older compatibility keys. In the default `EXTERNAL_ROOT_MODE=auto`, the values are enabled only after bounded live queries confirm both:

```text
content://com.android.externalstorage.documents/root
content://com.android.externalstorage.documents/document/primary%3A/children
```

After an important module or configuration change, the service removes the DocumentsUI root cache once and force-stops DocumentsUI. The next picker launch reads the corrected preferences.

## Root-provider operation

The Android provider package and authority are:

```text
package:   com.cbkii.tsdocsui.rootprovider
authority: com.cbkii.tsdocsui.root.documents
```

The provider uses a narrow helper installed at:

```text
/data/adb/ts18-documentsui-saf/rootfs-helper.sh
```

The module attempts to create a Magisk allow policy for the provider UID. If automatic policy creation is unavailable, Magisk may show a normal root request.

Seekable editing of root-only files uses a short-lived staging directory:

```text
/storage/emulated/0/.TS18-Root-Provider
```

Closed staging files are removed immediately. Stale files are removed during boot. The provider does not use `/tmp`, `/cache`, or `/data/local/tmp` for working data.

## Runtime configuration

The documented runtime configuration is:

```text
/data/adb/ts18-documentsui-saf.conf
```

The default file is `module/config.default`. The installer preserves only known keys when upgrading an existing configuration.

Important defaults include:

- keeping AOSP DocumentsUI enabled;
- keeping the stock ExternalStorageProvider enabled;
- showing internal storage only after live provider checks pass;
- enabling the root provider;
- allowing create, write, rename, move, copy, and delete operations where the filesystem permits them;
- keeping automatic boot diagnostics disabled.

## Rooted firmware source boundary

The Magisk-rooted TS18 firmware used with this project is sourced from the [4PDA Topway TS10/TS18 community topic](https://4pda.to/forum/index.php?showtopic=1015856).

The firmware is external to this repository. This project does not build, host, sign, or validate it. Do not treat a related TS18 firmware package as proof that it matches another unit. Exact system build, board, screen, panel, boot configuration, and recovery path must be confirmed first.

Installing this Magisk module does not require reflashing firmware when the device already has working Magisk root.

## Repository layout

```text
rootprovider/                   Android DocumentsProvider source
module/                         Magisk module payload
scripts/build-root-provider.py  Build and copy the signed provider APK
scripts/release_version.py      Resolve, validate, and apply release versions
scripts/sync_runtime_version.py Synchronise generated runtime version markers
scripts/release_assets.py       Validate ZIP, checksum, and update metadata
scripts/validate-module.py      Validate APKs, scripts, paths, and module identity
scripts/build-magisk-zip.py     Build the installable Magisk ZIP
tests/                          Release and runtime regression tests
.github/workflows/ci.yml        Build and validate every change
.github/workflows/release-magisk-module.yml
```

Repository agents must follow `AGENTS.md` and `.agents/skills/github-engineering-orchestrator/SKILL.md`.

## Local validation and build

Basic checks:

```bash
python3 -m compileall -q scripts tests
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 scripts/release_version.py --repo-root . --module-prop module/module.prop
python3 scripts/sync_runtime_version.py --repo-root . --check
find module -type f -name '*.sh' -print -exec sh -n {} ';'
sh -n module/META-INF/com/google/android/update-binary
```

A full provider and module build requires JDK 17, Android SDK 35, and Gradle 8.7 or later:

```bash
python3 scripts/build-root-provider.py --repo-root . --gradle gradle --timeout 900
python3 scripts/validate-module.py --module-dir module
python3 scripts/build-magisk-zip.py --module-dir module --out-dir dist
```

The provider signing key is stored as a deterministic base64-encoded JKS so updates keep one signing identity. The decoded key and generated APK are ignored by Git.

## Release process

`module/module.prop` is the single persistent version source.

The manual **Release Magisk module** workflow supports:

- an explicit `version_tag`, or an automatic patch increment when blank;
- an explicit numeric `version_code`, or the current code plus one when blank;
- draft and prerelease states;
- controlled replacement of assets for an existing immutable tag.

For a new release, the workflow:

1. confirms that it is running from the current default branch;
2. updates and commits `module/module.prop`;
3. synchronises unavoidable runtime version markers;
4. derives the Android provider version from the same metadata;
5. builds and validates the provider and Magisk ZIP;
6. creates an immutable tag on the exact version commit;
7. publishes the ZIP, checksum, and `update.json` only when all metadata agrees.

Release ZIPs must remain deterministic, STORE-only, non-ZIP64, and compatible with the existing Magisk installer wrapper.

`scripts/make-update-json.py` fails closed when the source metadata, embedded metadata, tag, filename, required members, archive format, checksum, digest, or release URLs do not agree.

## Device acceptance

CI proves source, APK, script, metadata, and ZIP structure. It cannot prove behaviour on a physical TS18 unit.

A device acceptance pass should test:

- `OPEN_DOCUMENT` from several non-Download internal folders;
- `CREATE_DOCUMENT` in a non-Download folder;
- `OPEN_DOCUMENT_TREE` for `/storage/emulated/0` and nested folders;
- persistable URI access after restarting the client app;
- root-provider browse and file operations where intended;
- reboot and ACC sleep/wake behaviour.

## Diagnostics

Press **Action** for the module in Magisk, or run:

```sh
su -c '/data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-deepdiag.sh full'
```

The verified archive is exported under:

```text
/storage/emulated/0/Download/TS18-SAF-Diagnostics/
```

Diagnostics are user-started, bounded, local-only, and removed from their temporary working directory after the final archive is verified.

## Safety and rollback

The module is systemless. It does not flash boot, MCU, CAN, LCD, logo, or firmware partitions.

The root provider can expose sensitive files and can modify writable paths. Keep destructive operations limited to known targets.

Rollback:

1. disable or remove the module in Magisk;
2. reboot;
3. remove `/data/adb/ts18-documentsui-saf.conf` only when a full configuration reset is wanted;
4. preserve diagnostic archives before cleanup.
