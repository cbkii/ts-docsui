# Technical and developer guide

This document contains the advanced information moved out of the beginner README.

User guides:

- [English](../README.md)
- [简体中文](../README.zh-CN.md)
- [Русский](../README.ru.md)

Physical validation:

- [Exact TS18 acceptance procedure](DEVICE_ACCEPTANCE.md)

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
        -> local discovery and shared-storage listing
        -> bounded Magisk helper after root-only content is opened
           -> / and root-only paths
```

The stock Android ExternalStorageProvider is retained. It is the preferred provider for normal shared storage because it returns Android-compatible document URIs and native seekable file descriptors.

The bundled root provider is separate. It supplies:

- `Internal storage (full)` for `/storage/emulated/0`;
- `Root file system` for `/`;
- available `/storage/usbdisk0` and `/storage/usbdisk1` roots.

Root access does not make read-only device-mapper mounts writable. `/system`, `/vendor`, and similar mounts remain read-only unless the firmware itself mounted them writable.

## DocumentsUI component authority

The exact TS18 Android 10 framework rejects the previously bundled sysconfig declaration with:

```text
Tag component-override is unknown
```

The module therefore does **not** ship `system/etc/sysconfig/ts18-documentsui-saf.xml`. PackageManager runtime reconciliation is the authority for enabling the known DocumentsUI entry points:

```text
com.android.documentsui/.picker.PickActivity
com.android.documentsui/.files.FilesActivity
com.android.documentsui/.files.LauncherActivity
com.android.documentsui/.LauncherActivity
com.android.documentsui/.ViewDownloadsActivity
com.android.documentsui/.ScopedAccessActivity
```

A boot log warning that names the removed sysconfig file is an acceptance failure and usually means an older module payload is still mounted.

## Why internal storage was hidden

Exact-device diagnostics proved that the stock provider publishes the `primary:` root and can list the top level of `/storage/emulated/0`.

The remaining failure was in DocumentsUI preferences. This Android 10/Pie picker stores the advanced-device choice separately for each picker action. It reads keys in this form:

```text
includeDeviceRoot-<action>
```

The module writes `includeDeviceRoot-1` through `includeDeviceRoot-8`, together with older compatibility keys. The default `EXTERNAL_ROOT_MODE=show` keeps the exact-device-proven `primary:` root visible. Optional `auto` mode hides it only after a bounded live check definitively fails; a missing timeout implementation or transient query failure leaves it visible.

```text
content://com.android.externalstorage.documents/root
content://com.android.externalstorage.documents/document/primary%3A/children
```

After an important module or configuration change, the service repairs DocumentsUI data ownership, disables the obsolete `com.ts18.safprovider` experiment and App Manager picker interception, enables the known picker entry points, removes the DocumentsUI root cache once, and force-stops DocumentsUI. The next picker launch reads the corrected preferences.

## Desired-state boot reconciliation

The late-start service reads current state before changing it. It avoids repeating package installation, component changes, permission grants, AppOps writes, preference/helper replacement, Magisk-policy writes and recursive ownership repair when the desired state is already present.

Stale-provider removal and preferred-activity cleanup are one-time migrations. Every run ends with:

```text
reconcile summary mutations=<N> noops=<N>
```

The first migration boot may contain finite, explained mutations. A second settled boot with unchanged configuration should report zero mutations. A functional provider failure is evidence for diagnostics; it must not trigger an AppOps rewrite loop.

Root-provider failure or root denial must not disable, clear, refresh or otherwise mutate stock `com.android.externalstorage`.

## AppOps and external-storage remounts

Exact-device logs showed rapid alternating `remountUidExternalStorage` operations for the stock and root providers. The system-server stack associates those remounts with AppOps change notifications.

The module now treats this as a formal physical acceptance gate:

- AppOps are written only when current state differs;
- the second settled boot must perform no AppOps mutation;
- diagnostics preserve raw and structured remount events;
- counts are grouped by UID, package, mode and phase;
- total and peak events per second are reported;
- a detected storm captures bounded system-server stack evidence;
- provider process mount namespaces are collected.

An AppOps line that says `allow` is not by itself proof that the provider received the intended storage namespace. Functional provider queries and process-specific `/proc/<pid>/mountinfo` evidence are also required.

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

Provider discovery never invokes `su`. Root metadata calls are bounded to four seconds and directory listings to eight seconds. Shared-storage files are copied to the staging file directly when the provider can read them; root-only paths fall back to the Magisk helper. If neither copy can initialise an existing file, the open fails before an empty staging file can be returned or copied back over the source.

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
- showing the proven internal-storage root unless the user explicitly selects another mode;
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
module/tools/ts18-saf-evidence-v2.sh
                                Private-first exact-device collector
module/tools/ts18-saf-deepdiag.sh
                                Legacy compatibility collector
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

Use [DEVICE_ACCEPTANCE.md](DEVICE_ACCEPTANCE.md). The release gate includes:

- first migration boot and second settled boot;
- `OPEN_DOCUMENT`, `CREATE_DOCUMENT` and `OPEN_DOCUMENT_TREE` from real clients;
- persisted URI access after client restart, reboot and ACC sleep/wake;
- root-provider disabled, denied and granted states;
- USB insertion/removal;
- no unsupported sysconfig warning;
- no sustained external-storage remount storm;
- disable/remove plus reboot rollback.

## Diagnostics

Press **Action** for the module in Magisk, or run:

```sh
su -c '/data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-evidence-v2.sh full'
```

For a client-specific capture:

```sh
su -c 'TS18_SAF_CLIENT_PACKAGE=com.tw.media /data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-evidence-v2.sh boot2'
```

The collector:

- derives the installed module version rather than assuming a build;
- works privately under `/data/adb/ts18-documentsui-saf/diagnostics`;
- skips a command instead of running it unbounded when no timeout implementation exists;
- captures package identity, APK hashes and a previous/current package-stack diff;
- captures permissions, AppOps, providers, URI grants and functional root queries;
- captures DocumentsUI, stock provider, root provider and client process mount namespaces;
- structures remount events and flags storm thresholds;
- reports the latest two reconcile summaries;
- exports only a verified tar archive and checksum.

Verified archives are written under:

```text
/storage/emulated/0/Download/TS18-SAF-Diagnostics/
```

Diagnostics are user-started, bounded and local-only. The collector removes its private working directory only after the exported archive passes an integrity check.

## Safety and rollback

The module is systemless. It does not flash boot, MCU, CAN, LCD, logo, or firmware partitions.

The root provider can expose sensitive files and can modify writable paths. Keep destructive operations limited to known targets.

Rollback:

1. disable or remove the module in Magisk;
2. reboot;
3. remove `/data/adb/ts18-documentsui-saf.conf` only when a full configuration reset is wanted;
4. preserve diagnostic archives before cleanup.
