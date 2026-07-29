# Changelog

## v1.3.0 / versionCode 130

- Reconcile package, component, permission, AppOps, ownership and preference state before mutation.
- Make stale-provider and preferred-activity cleanup explicit one-time migrations.
- Skip identical preference writes and duplicate recursive ownership repair; log mutation/no-op totals.
- Keep root-provider failure isolated from the stock ExternalStorageProvider.
- Add remount/provider event counts and the boot reconcile summary to diagnostics.

## v0.8.0 / versionCode 080

- Reset imported TS18 SAF DocumentsUI module version to `v0.8.0` / `080` for private repository development.
- Preserve the v2.3 functional baseline: AOSP Android 10 DocumentsUI overlay, stale invalid TS18 local SAF provider disabled, AppManager picker interceptor disabled, advanced/broken external roots hidden by default, MiXplorer provider fallback support, and Download-export diagnostics.
- Add repository packaging scripts and a manual GitHub Actions release workflow for installable Magisk ZIPs.

## Import source

- Imported from `ts18-saf-v23.zip` supplied by CB.
