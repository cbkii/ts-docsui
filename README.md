# TS18 Full File Picker Magisk Module

Magisk 28+ module for TS18 Android 10 head units. It restores the Android system file picker, exposes all of `/storage/emulated/0`, and adds a Magisk-root DocumentsProvider for browsing and selecting files or folders anywhere under `/`.

## Module identity

- `id=ts18_documentsui_saf_full`
- Release version and version code are read from `module/module.prop`.

The module ID intentionally matches existing TS18 SAF module installations so this release upgrades them instead of creating a second active overlay.

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

The stock ExternalStorageProvider is retained rather than replaced. Current TS18 diagnostics prove that its `primary:` root and `primary:/children` query successfully enumerate `/storage/emulated/0`; previous module releases hid that working root through DocumentsUI preferences. The root provider is a separate package and authority, so it cannot collide with the stock provider.

## v1.2 internal-storage fix

Android 10 DocumentsUI does not read one global `includeDeviceRoot` preference for every picker flow. It reads an action-scoped key such as `includeDeviceRoot-3` for `OPEN_DOCUMENT` or `includeDeviceRoot-6` for `OPEN_DOCUMENT_TREE`. Earlier module versions wrote only the unsuffixed key, so the provider could successfully return `primary:` and every top-level folder while the visible picker still filtered the root out.

v1.2 writes the action-scoped keys used by the bundled Android 10 picker, retains older compatibility keys, refreshes the picker cache once on upgrade, and then force-stops DocumentsUI so the next picker launch reads the corrected state. In the default `EXTERNAL_ROOT_MODE=auto`, these keys are enabled only after both the live `primary:` root query and its child listing succeed.

## Repository layout

```text
rootprovider/                   Android DocumentsProvider source
module/                         Magisk module payload
scripts/build-root-provider.py  Build and copy the signed provider APK
scripts/release_version.py      Resolve, validate, and apply release versions
scripts/release_assets.py       Validate the exact ZIP, checksum and update metadata
scripts/validate-module.py      Validate APKs, scripts, paths, and module identity
scripts/build-magisk-zip.py     Build the installable Magisk ZIP
tests/                          Release-version and runtime-regression tests
.github/workflows/ci.yml        Build and validate every change
.github/workflows/release-magisk-module.yml
```

Repository agents must follow `AGENTS.md`. The repository-local orchestration skill is stored at `.agents/skills/github-engineering-orchestrator/SKILL.md`.

## Local build

Requires JDK 17, Android SDK 35, and Gradle 8.7+:

```bash
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 scripts/build-root-provider.py --gradle gradle
python3 scripts/validate-module.py --module-dir module
python3 scripts/build-magisk-zip.py --module-dir module --out-dir dist
```

The provider signing key is stored as a deterministic base64-encoded JKS so updates retain one signing identity. The decoded JKS and generated provider APK are ignored by Git.

## Manual release workflow

Run **Release Magisk module** from the default branch.

- `version_tag`: enter `vMAJOR.MINOR.PATCH` or leave blank to increment the highest current/tagged patch version.
- `version_code`: enter a positive integer or leave blank to increment the current `module.prop` code by one.
- `draft` and `prerelease`: control the new GitHub release state.
- `replace_existing_assets`: rebuilds only the exact existing tag and replaces its module ZIP, checksum, and `update.json`; it never moves a tag.

For a new release, the workflow updates and commits `module/module.prop` before building, derives the Android provider version from that same file, validates all metadata, creates an annotated tag on the version commit, and then publishes the release. Default-branch freshness, tag/release collisions, monotonic version codes, APK metadata, STORE-only ZIP structure, checksums and `update.json` URLs are enforced before publishing.

`scripts/make-update-json.py` is deliberately fail-closed: it refuses to write update metadata unless the source and embedded `module.prop`, canonical tag, deterministic ZIP name, required ZIP members, STORE-only archive, checksum filename and SHA-256 digest all agree.

## Device validation status

CI proves that the provider compiles, Android lint passes, APK/ZIP structures are valid, action-scoped DocumentsUI preference coverage is present, and module scripts pass syntax checks. The supplied TS18 diagnostics prove the stock provider exposes `primary:` and enumerates the top level of `/storage/emulated/0`, but physical picker acceptance still requires installing v1.2 and selecting folders through real `OPEN_DOCUMENT`, `CREATE_DOCUMENT`, and `OPEN_DOCUMENT_TREE` client flows.

This module does not flash boot, MCU, CAN, LCD, logo, or firmware partitions.
