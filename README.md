# TS18 Full File Picker Magisk Module

Magisk 28+ module for TS18 Android 10 head units. It restores the Android system file picker, exposes all of `/storage/emulated/0`, and adds a Magisk-root DocumentsProvider for browsing and selecting files or folders anywhere under `/`.

## Module identity

- `id=ts18_documentsui_saf_full`
- `version=v1.0.0`
- `versionCode=100`

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

## Repository layout

```text
rootprovider/                  Android DocumentsProvider source
module/                        Magisk module payload
scripts/build-root-provider.py Build and copy the signed provider APK
scripts/validate-module.py     Validate APKs, scripts, paths, and module identity
scripts/build-magisk-zip.py    Build the installable Magisk ZIP
.github/workflows/ci.yml       Build and validate every change
.github/workflows/release-magisk-module.yml
```

## Local build

Requires JDK 17, Android SDK 35, and Gradle 8.7+:

```bash
python3 scripts/build-root-provider.py --gradle gradle
python3 scripts/validate-module.py \
  --module-dir module \
  --expected-version v1.0.0 \
  --expected-version-code 100
python3 scripts/build-magisk-zip.py --module-dir module --out-dir dist
```

The provider signing key is stored as a deterministic base64-encoded JKS so updates retain one signing identity. The decoded JKS and generated provider APK are ignored by Git.

## Device validation status

CI proves that the provider compiles, Android lint passes, APK/ZIP structures are valid, and module scripts pass syntax checks. Physical TS18 validation is still required after installation; use the Magisk Action collector if any provider root fails.

This module does not flash boot, MCU, CAN, LCD, logo, or firmware partitions.
