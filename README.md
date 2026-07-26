# TS18 Full File Picker Magisk Module

Magisk 28+ module for TS18 Android 10 head units. It restores Android's system file picker, exposes all of `/storage/emulated/0`, and adds a separate Magisk-backed provider for root-only paths under `/`.

## Module identity

- `id=ts18_documentsui_saf_full`
- Release version and version code come from `module/module.prop`.

The stable module ID upgrades an existing installation instead of mounting a second competing overlay.

## Architecture

```text
Client app
  -> Android DocumentsUI picker
     -> stock com.android.externalstorage.documents
        -> /storage/emulated/0 and mounted TS18 USB volumes
     -> com.cbkii.tsdocsui.root.documents
        -> local, non-root discovery and shared-storage listing
        -> bounded Magisk helper only after root-only content is opened
           -> / and root-only paths
```

Exact-device diagnostics proved that the stock ExternalStorageProvider publishes `primary:` and enumerates `/storage/emulated/0`. It remains the preferred shared-storage provider because it supplies native Android URI and file-descriptor behaviour.

## Repairs included after the broken 101 build

The first versionCode `101` build could leave the complete picker blank or apparently frozen. The repaired implementation addresses the interacting causes while preserving the later v1.2 action-scoped storage fix:

- `queryRoots()` no longer launches `su` while DocumentsUI discovers providers;
- root metadata and directory calls are bounded and begin only after root-only content is opened;
- DocumentsUI private-data ownership is repaired to its actual package UID;
- the obsolete `com.ts18.safprovider` experiment and App Manager picker interception are disabled;
- all relevant DocumentsUI entry points are enabled and picker intent resolution is checked;
- the exact-device-proven `primary:` root is shown by default and is not hidden by an inconclusive boot-time probe;
- `includeDeviceRoot-1` through `includeDeviceRoot-8` remain written for Android 10's action-specific picker flows;
- existing pre-schema-2 runtime configuration is backed up and migrated once.

Root-provider failure is isolated: normal DocumentsUI and stock `primary:` storage remain usable even when Magisk root cannot be granted.

## Repository layout

```text
rootprovider/                   Android DocumentsProvider source
module/                         Magisk module payload
scripts/build-root-provider.py  Build and copy the signed provider APK
scripts/release_version.py      Resolve, validate, and apply release versions
scripts/release_assets.py       Validate exact release assets and metadata
scripts/validate-module.py      Validate APKs, scripts, paths, and module identity
scripts/build-magisk-zip.py     Build the installable Magisk ZIP
tests/                          Release, packaging and picker-regression tests
.github/workflows/ci.yml        Build and validate every change
.github/workflows/release-magisk-module.yml
```

Repository agents must follow `AGENTS.md` and `.agents/skills/github-engineering-orchestrator/SKILL.md`.

## Local build

Requires JDK 17, Android SDK 35, and Gradle 8.7+:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
find module -type f -name '*.sh' -print -exec sh -n {} ';'
python3 scripts/build-root-provider.py --gradle gradle
python3 scripts/validate-module.py --module-dir module
python3 scripts/build-magisk-zip.py --module-dir module --out-dir dist
```

## Device installation and acceptance

Install the validated Magisk ZIP over the existing module and reboot. The installer preserves a timestamped backup of the previous runtime configuration before schema migration.

After reboot, verify:

```sh
su -c 'cmd package resolve-activity --brief --user 0 -a android.intent.action.OPEN_DOCUMENT_TREE'
su -c 'content query --uri content://com.android.externalstorage.documents/root --user 0'
su -c 'content query --uri content://com.cbkii.tsdocsui.root.documents/root --user 0'
su -c '/data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-launch.sh internal'
```

Expected picker resolver: `com.android.documentsui/.picker.PickActivity`. Expected stock storage root: `primary`. The launcher probe writes `/storage/emulated/0/Download/TS18-SAF-launch.log`.

Test real client flows for `GET_CONTENT`, `OPEN_DOCUMENT`, `CREATE_DOCUMENT`, and `OPEN_DOCUMENT_TREE`, including non-Downloads folders and persistable access after the client restarts.

Rollback is reversible: disable or remove the Magisk module and reboot. The module does not flash boot, MCU, CAN, LCD, logo, firmware, or read-only system partitions.

## Manual release workflow

Run **Release Magisk module** from the current default branch.

- `version_tag`: `vMAJOR.MINOR.PATCH`, or blank to auto-increment the highest patch version.
- `version_code`: positive integer, or blank to increment the current code.
- `draft` and `prerelease`: control release state.
- `replace_existing_assets`: rebuilds only an exact existing immutable tag; it never moves the tag.

The workflow commits synchronized version metadata before building, derives the provider version from the same source, validates the APK/module/STORE-only ZIP/checksum/update metadata, creates an annotated tag, and publishes only after those checks pass.

## Device validation status

CI can prove compilation, Android lint, source contracts, shell/XML validity, APK metadata, and exact ZIP structure. It cannot prove that a physical TS18 has clean PackageManager state or that every OEM client launches the picker. Physical installation and acceptance remain required before promoting the repair as stable.
