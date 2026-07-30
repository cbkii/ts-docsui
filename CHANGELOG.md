# Changelog

## v1.3.0 / versionCode 130

- Reset the Magisk module ID to `ts-docsui`; older module IDs and upgrade compatibility are intentionally not retained.
- Keep only the current runtime, installer and one bounded diagnostic collector; remove legacy wrappers, split evidence helpers, stale provider payloads, unsupported sysconfig and runtime-version synchronisation.
- Store installer work, service logs, diagnostic work and verified evidence archives under `/storage/emulated/0/Download/ts-docsui/` rather than `/data/adb`.
- Reserve `/data/adb/ts-docsui` for the small root helper, generated preferences and reconciliation markers required at runtime.
- Build two deterministic release variants from the same source and provider APK:
  - `ts-docsui-v<versionCode>.zip` — lean final runtime module;
  - `ts-docsui-debug-v<versionCode>.zip` — runtime plus diagnostics and Magisk Action.
- Point `update.json` only to the final variant while publishing both ZIPs and both SHA-256 files.
- Reconcile package, component, permission, AppOps, file content, directory ownership, modes and preferences before mutation so a settled second boot does not repeat writes.
- Keep the root provider disabled when its staging or preferences cannot be prepared, while leaving stock `com.android.externalstorage.documents` enabled and usable.
- Mark the picker cache state complete only after DocumentsUI preferences were applied successfully.
- Avoid custom-provider warm-up during boot.
- Support Android 10 component-state inspection through package-dump fallback when the adjacent-build getter command is unavailable.
- Preserve structured package, provider, URI-grant, process-namespace, storage, remount and root-helper evidence in the debug collector.
- Add migration-boot, settled-boot, persisted-grant, root-denied, USB, debug-to-final and rollback acceptance procedures.
- Permit release-asset rebuilding only from an existing immutable exact tag and matching release; never create or move a tag in replacement mode.

## v0.8.0 / versionCode 080

- Imported the earlier TS18 SAF Magisk-module baseline for private repository development.
- Added initial packaging scripts and a manual GitHub Actions release workflow.

## Import source

- Imported from `ts18-saf-v23.zip` supplied by CB.
