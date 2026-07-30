#!/system/bin/sh
# Remove ts-docsui-owned minimal runtime state and its Magisk root policy.
# Download diagnostics/logs are preserved so evidence is not destroyed automatically.

ROOT_PKG=com.cbkii.tsdocsui.rootprovider
uid=$(cmd package list packages -U "$ROOT_PKG" 2>/dev/null | sed -n 's/.* uid://p' | head -n 1)
magisk_bin=$(command -v magisk 2>/dev/null)
[ -n "$magisk_bin" ] || [ ! -x /data/adb/magisk/magisk ] || magisk_bin=/data/adb/magisk/magisk
[ -n "$magisk_bin" ] || [ ! -x /sbin/magisk ] || magisk_bin=/sbin/magisk
case "$uid" in
  ''|*[!0-9]*) ;;
  *) [ -z "$magisk_bin" ] || "$magisk_bin" --sqlite "DELETE FROM policies WHERE uid=$uid;" >/dev/null 2>&1 || true ;;
esac

pm disable-user --user 0 "$ROOT_PKG/.RootDocumentsProvider" >/dev/null 2>&1 || true
pm clear --user 0 "$ROOT_PKG" >/dev/null 2>&1 || true
pm enable --user 0 io.github.muntashirakon.AppManager/.intercept.ActivityInterceptor >/dev/null 2>&1 || true
pm enable --user 0 com.google.android.documentsui >/dev/null 2>&1 || true

rm -rf /data/adb/ts-docsui 2>/dev/null || true
rm -f /data/adb/ts-docsui.conf 2>/dev/null || true
exit 0
