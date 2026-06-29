# TS18 SAF DocumentsUI Magisk Module

Private development repository for the TS18 Android 10 SAF/DocumentsUI Magisk module.

Current module metadata:

- `id=ts18_documentsui_saf_full`
- `version=v0.8.0`
- `versionCode=080`

## Layout

```text
module/                       Magisk module contents; this is what gets zipped at release time
scripts/validate-module.py    Structural validation for the module directory
scripts/build-magisk-zip.py   Builds an installable Magisk ZIP into dist/
scripts/make-update-json.py   Creates release update.json for GitHub Release assets
scripts/create-private-github-repo-termux.sh
.github/workflows/release-magisk-module.yml
```

The installer ZIP must contain the files inside `module/` at the ZIP root, not the `module/` directory itself.

## Local build

```bash
python3 scripts/validate-module.py --module-dir module
python3 scripts/build-magisk-zip.py --module-dir module --out-dir dist
```

The output ZIP is installable in Magisk.

## Private GitHub repo bootstrap

From the unpacked repo directory, after `gh auth login`:

```bash
./scripts/create-private-github-repo-termux.sh cbkii/ts18-saf-documentsui-magisk
```

The script initialises Git if needed, commits the scaffold, creates a private GitHub repo if missing, adds `origin`, and pushes the current branch.

## Manual release workflow

After the repo is on GitHub, run **Actions → Build and release Magisk module → Run workflow**.

The workflow:

1. validates `module/`;
2. builds an installable Magisk ZIP;
3. uploads it as a workflow artifact;
4. optionally creates or updates a GitHub Release with the ZIP, SHA256, and `update.json`.

For a private repo, Magisk's in-app `updateJson` URL is not added to `module.prop` because private GitHub release assets are not anonymously reachable by the TS18 unit. Download the ZIP from the private Release or workflow artifact and install it manually in Magisk.

## TS18 safety notes

This module remains a TS18 Android 10 / SDK 29 repair module. It does not flash boot, MCU, CAN, LCD, BOOT/display, or firmware partitions. It is a systemless Magisk overlay plus bounded boot/action scripts. Keep rollback media and known-good boot images separately.
