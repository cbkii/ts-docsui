# TS18 Full File Picker Magisk Module

Magisk 28+ module for TS18 Android 10 head units. It restores the Android system file picker, exposes all of `/storage/emulated/0`, and adds a separate Magisk-root DocumentsProvider for browsing and selecting files or folders anywhere under `/`.

## Module identity

- `id=ts18_documentsui_saf_full`
- Release version and version code are read from `module/module.prop`.

The module ID intentionally matches existing TS18 SAF module installations so a repaired release upgrades them instead of creating a second active overlay.

## Architecture

```text
Client app
  -> Android DocumentsUI picker
     -> stock com.android.externalstorage.documents
        -> /storage/emulated/0 and mounted TS18 USB volumes
     -> com.cbkii.tsdocsui.root.documents
        -> fast local root discovery (never su)
        -> bounded Magisk helper only after root-only content is opened
           -> / and root-only paths
```

The stock ExternalStorageProvider is retained rather than replaced. Exact-device diagnostics proved that its `primary:` root and `primary:/children` query enumerate `/storage/emulated/0`. The module therefore shows that root by default instead of hiding it after one transient boot-time test.

The separate root provider must not block picker startup. `queryRoots()` and root-document metadata use local Android file/stat calls only. Direct shared-storage listing is attempted before any root fallback. Root shell calls are bounded and occur only when the user opens content that genuinely needs them.

## v1.0.1 launch-regression repair

The first `101` release could leave the complete picker blank or apparently frozen. The repair branch addresses four interacting causes:

1. provider discovery synchronously launched several Magisk `su` processes while DocumentsUI was loading;
2. old module scripts could leave `com.android.documentsui` private data owned by `system:system` instead of the package UID;
3. obsolete `com.ts18.safprovider` and App Manager picker interception could remain registered;
4. `EXTERNAL_ROOT_MODE=auto` could hide the proven `primary:` root after a transient early query failure.

The repaired module removes root work from picker discovery, repairs package-data ownership, disables the stale provider/interceptor, enables all relevant DocumentsUI entry points, verifies intent resolution, and migrates pre-schema-2 configurations to `EXTERNAL_ROOT_MODE=show` once. Later user choices are preserved.

## Repository layout

```text
rootprovider/                   Android DocumentsProvider source
module/                         Magisk module payload
scripts/build-root-provider.py  Build and copy the signed provider APK
scripts/release_version.py      Resolve, validate, and apply release versions
scripts/release_assets.py       Validate the exact ZIP, checksum and update metadata
scripts/validate-module.py      Validate APKs, scripts, paths, and module identity
scripts/build-magisk-zip.py     Build the installable Magisk ZIP
tests/                          Release, packaging and picker-recovery tests
.github/workflows/ci.yml        Build and validate every change
.github/workflows/release-magisk-module.yml
```

Repository agents must follow `AGENTS.md`. The repository-local orchestration skill is stored at `.agents/skills/github-engineering-orchestrator/SKILL.md`.

## Local build

Requires JDK 17, Android SDK 35, and Gradle 8.7+:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
find module -type f -name '*.sh' -print -exec sh -n {} ';'
python3 scripts/build-root-provider.py --gradle gradle
python3 scripts/validate-module.py --module-dir module
python3 scripts/build-magisk-zip.py --module-dir module --out-dir dist
```

The provider signing key is stored as a deterministic base64-encoded JKS so updates retain one signing identity. The decoded JKS and generated provider APK are ignored by Git.

## Device installation and acceptance

Install the validated Magisk ZIP over the existing module and reboot. The schema migration keeps a timestamped copy of the prior runtime config at `/data/adb/ts18-documentsui-saf.conf.pre-<versionCode>.<timestamp>`.

After reboot, verify:

```sh
su -c 'cmd package resolve-activity --brief --user 0 -a android.intent.action.OPEN_DOCUMENT_TREE'
su -c 'content query --uri content://com.android.externalstorage.documents/root --user 0'
su -c 'content query --uri content://com.cbkii.tsdocsui.root.documents/root --user 0'
su -c '/data/adb/modules/ts18_documentsui_saf_full/tools/ts18-saf-launch.sh internal'
```

Expected resolver: `com.android.documentsui/.picker.PickActivity`. Expected stock storage root: `primary`. The manual launcher writes resolver and launch output to `/storage/emulated/0/Download/TS18-SAF-launch.log`.

Rollback is reversible: disable or remove the Magisk module and reboot. The module does not flash boot, MCU, CAN, LCD, logo, or firmware partitions.

## Manual release workflow

Run **Release Magisk module** from the default branch.

- `version_tag`: enter `vMAJOR.MINOR.PATCH` or leave blank to increment the highest current/tagged patch version.
- `version_code`: enter a positive integer or leave blank to increment the current `module.prop` code by one.
- `draft` and `prerelease`: control the new GitHub release state.
- `replace_existing_assets`: rebuilds only the exact existing tag and replaces its module ZIP, checksum, and `update.json`; it never moves a tag.

For a new release, the workflow updates and commits `module/module.prop` before building, derives the Android provider version from that same file, validates all metadata, creates an annotated tag on the version commit, and then publishes the release. Default-branch freshness, tag/release collisions, monotonic version codes, APK metadata, STORE-only ZIP structure, checksums and `update.json` URLs are enforced before publishing.

`scripts/make-update-json.py` is deliberately fail-closed: it refuses to write update metadata unless the source and embedded `module.prop`, canonical tag, deterministic ZIP name, required ZIP members, STORE-only archive, checksum filename and SHA-256 digest all agree.

## Device validation status

CI proves that the provider compiles, Android lint passes, source contracts hold, APK/ZIP structures are valid, and module scripts pass syntax checks. It does not prove that a specific physical TS18 installation has clean package-manager state. Physical validation remains required after installation; use the Magisk Action collector if any provider root or picker intent still fails.
