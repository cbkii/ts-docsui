# Repository agent instructions

These instructions apply to the whole repository. The user’s current request and any more-specific nested `AGENTS.md` remain authoritative.

## Required operating mode

Use the repository-local `github-engineering-orchestrator` skill at `.agents/skills/github-engineering-orchestrator/SKILL.md` for architecture, implementation, pull-request, CI and release work. When the account-level `$github-engineering-orchestrator` skill is available, invoke it as well; this local file supplies the repository-specific contract.

Do not stop at a plan or an unpushed patch when the user has authorised a later completion gate. Refresh live GitHub state, implement on a dedicated branch, validate the exact current head, push it and keep the PR description/checklist accurate.

## Repository contract

- Target platform: TS18 Android 10/API 29 head units with Magisk 28+.
- Module ID: `ts-docsui`.
- Backwards-compatibility wrappers, alternate module IDs and legacy diagnostic entry points are not supported.
- `module/module.prop` is the sole persistent release version source.
- `rootprovider/build.gradle` must derive Android `versionName` and `versionCode` from `module/module.prop`.
- Keep the stock `com.android.externalstorage.documents` provider. The bundled root provider uses the separate package and authority documented in `docs/DEVELOPMENT.md`.
- Do not add or restore obsolete `ExternalStorageProvider.apk`, experimental TS18 provider payloads or unsupported component-override sysconfig files.
- `/data/adb/ts-docsui` is limited to small required runtime state. Logs, diagnostic work and diagnostic archives belong under `/storage/emulated/0/Download/ts-docsui/`.
- Build exactly two deterministic, STORE-only, non-ZIP64 variants:
  - `ts-docsui-v<versionCode>.zip`: lean final runtime module;
  - `ts-docsui-debug-v<versionCode>.zip`: runtime plus the bounded diagnostic collector and Magisk Action.
- `update.json` must reference only the final variant.
- Never claim physical TS18 behaviour was proven by CI. Device acceptance remains an explicit external validation boundary.

## Required validation

Run the narrowest relevant checks first, then the complete repository validation for release or workflow changes:

```bash
python3 -m compileall -q scripts tests
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 scripts/release_version.py --repo-root . --module-prop module/module.prop
find module -type f -name '*.sh' -print -exec sh -n {} ';'
sh -n module/META-INF/com/google/android/update-binary
```

When Java, Android SDK 35 and Gradle 8.7 are available, also run:

```bash
python3 scripts/build-root-provider.py --repo-root . --gradle gradle --timeout 900
python3 scripts/validate-module.py --module-dir module
python3 scripts/build-magisk-zip.py --module-dir module --out-dir dist --variant final
python3 scripts/build-magisk-zip.py --module-dir module --out-dir dist --variant debug
```

For release-path changes, inspect both ZIP inventories and checksums. Confirm the final ZIP excludes `action.sh` and `tools/ts18-saf-deepdiag.sh`, the debug ZIP includes both, and the final ZIP alone is used to generate `update.json`.

## Release workflow rules

- Manual release dispatches run only from the current default branch.
- Blank `version_tag` means automatic patch increment; blank `version_code` means current code plus one.
- New releases commit `module/module.prop` before building and tag that exact source commit.
- Existing tags are immutable. Asset replacement may rebuild only the exact tagged source and must never move the tag.
- A release must fail before publication if module metadata, provider APK metadata, ZIP metadata, checksums, tag or `update.json` disagree.
- Both final and debug ZIPs and their checksum files are release assets.
- Do not publish or merge unless the user’s requested completion objective authorises it.

## Pull-request hardening

Before calling a PR review-ready, inspect the complete diff, changed-file inventory, reviews, comments and all check states on the current head. Classify every finding as valid, already fixed, stale, duplicate, false positive, out of scope or an external boundary. Remove temporary files and stale documentation. Do not repeatedly rerun an unchanged deterministic failure.

For high-risk release, signing, root or boot-time changes, explain in plain English what can fail, who or what is affected, the protections in place and the rollback path.
