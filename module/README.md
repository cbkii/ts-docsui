# TS18 SAF DocumentsUI Stable Picker Repair v0.8.0

Purpose: recover the stable picker behaviour after v2.2 diagnostics showed the bundled `com.ts18.safprovider` APK has an invalid DEX and crashes whenever its provider is started.

Default v0.8.0 behaviour:

- Keeps AOSP Android 10 `com.android.documentsui`.
- Removes the invalid `TS18LocalDocumentsProvider.apk` payload.
- Disables/clears stale `com.ts18.safprovider` if left from v2.2.
- Disables AppManager `ActivityInterceptor` for picker stability.
- Keeps existing `com.android.externalstorage` if present, but hides advanced/device roots by DocumentsUI preferences to avoid the broken `s9863a1h10_Natv` / `USB Drive` entries.
- Enables MiXplorer's existing DocumentsProvider as a broad-access fallback if MiXplorer is installed.
- Exports diagnostics only to `/storage/emulated/0/Download/TS18-SAF-Diagnostics`.

This version prioritises no-crash picker operation and useful Downloads/Documents access. A true direct TS18 DocumentsProvider still requires a valid Android-built APK/Dex; v2.2's hand-built provider payload is intentionally removed.
