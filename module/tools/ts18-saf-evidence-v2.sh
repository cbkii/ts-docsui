#!/system/bin/sh
# Comprehensive v2 exact-device evidence collector for the TS18 Full File Picker.
# Collection is bounded and local-only. Work stays under /data/adb and only the
# verified archive/checksum are exported to shared storage.

MODE=${1:-full}
TARGET_USER=${TARGET_USER:-0}
STATE_DIR=/data/adb/ts18-documentsui-saf
PRIVATE_BASE=$STATE_DIR/diagnostics
EXPORT_BASE=${TS18_SAF_EXPORT_ROOT:-/storage/emulated/0/Download/TS18-SAF-Diagnostics}
SCRIPT_DIR=${0%/*}
MODULE_DIR=${SCRIPT_DIR%/*}
COMMON_LIB=$SCRIPT_DIR/ts18-saf-evidence-common.sh
REMOUNT_LIB=$SCRIPT_DIR/ts18-saf-evidence-remount.sh
MODULE_PROP=$MODULE_DIR/module.prop
ROOT_AUTH=com.cbkii.tsdocsui.root.documents
ROOT_PKG=com.cbkii.tsdocsui.rootprovider
ROOT_HELPER=$STATE_DIR/rootfs-helper.sh
TIMEOUT_SECONDS=${TS18_SAF_TIMEOUT_SECONDS:-30}
MAX_COPY_BYTES=${DIAG_MAX_COPY_BYTES:-52428800}
DIAG_COPY_RELEVANT_APKS=${DIAG_COPY_RELEVANT_APKS:-1}
DIAG_CAPTURE_SYSTEM_SERVER_STACK=${DIAG_CAPTURE_SYSTEM_SERVER_STACK:-1}
REMOUNT_STORM_TOTAL_THRESHOLD=${REMOUNT_STORM_TOTAL_THRESHOLD:-100}
REMOUNT_STORM_RATE_THRESHOLD=${REMOUNT_STORM_RATE_THRESHOLD:-20}
CLIENT_PACKAGE=${TS18_SAF_CLIENT_PACKAGE:-}

VERSION=$(sed -n 's/^version=//p' "$MODULE_PROP" 2>/dev/null | head -n 1)
VERSION_CODE=$(sed -n 's/^versionCode=//p' "$MODULE_PROP" 2>/dev/null | head -n 1)
[ -n "$VERSION" ] || VERSION=unknown
case "$VERSION_CODE" in ''|*[!0-9]*) VERSION_CODE=unknown ;; esac
TS=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo now)
RUN_ID=ts18-docsui-${VERSION#v}-${VERSION_CODE}-${MODE}-${TS}
WORK=$PRIVATE_BASE/$RUN_ID
LOG=$WORK/collector.log
SUMMARY=$WORK/SUMMARY.txt
WARNINGS=$WORK/WARNINGS.txt
RESULT=SUCCESS
WARN_COUNT=0

umask 077

[ -r "$COMMON_LIB" ] || { printf 'STOP: missing %s\n' "$COMMON_LIB" >&2; exit 1; }
[ -r "$REMOUNT_LIB" ] || { printf 'STOP: missing %s\n' "$REMOUNT_LIB" >&2; exit 1; }
# shellcheck source=module/tools/ts18-saf-evidence-common.sh
. "$COMMON_LIB"
# shellcheck source=module/tools/ts18-saf-evidence-remount.sh
. "$REMOUNT_LIB"

# ----- preflight -----
case "$TARGET_USER" in ''|*[!0-9]*) printf 'STOP: TARGET_USER must be numeric\n' >&2; exit 2 ;; esac
case "$TIMEOUT_SECONDS" in ''|*[!0-9]*) printf 'STOP: TS18_SAF_TIMEOUT_SECONDS must be numeric\n' >&2; exit 2 ;; esac
mkdir -p "$PRIVATE_BASE" "$EXPORT_BASE" 2>/dev/null || { printf 'STOP: cannot create diagnostic directories\n' >&2; exit 1; }
rm -rf "$WORK" 2>/dev/null || true
mkdir -p "$WORK" 2>/dev/null || { printf 'STOP: cannot create %s\n' "$WORK" >&2; exit 1; }
for directory in identity module packages providers storage paths permissions root-provider logs crash files apks smoke uri-grants; do
  mkdir -p "$WORK/$directory" 2>/dev/null || { printf 'STOP: cannot create %s/%s\n' "$WORK" "$directory" >&2; exit 1; }
done
: > "$LOG"
: > "$WARNINGS"

say "Starting TS18 file-picker diagnostics mode=$MODE version=$VERSION ($VERSION_CODE)"
say "Private work directory: $WORK"

# ----- identity and module -----
F=$WORK/identity/system.txt
section "$F" identity
for command_text in \
  'id' 'uname -a' 'getenforce' 'cat /proc/uptime' 'cat /proc/sys/kernel/random/boot_id' \
  'getprop ro.build.display.id' 'getprop ro.build.version.sdk' \
  'getprop ro.product.device' 'getprop ro.product.board' 'getprop ro.hardware' \
  'getprop ro.boot.verifiedbootstate' 'getprop ro.boot.vbmeta.device_state' \
  'magisk -v' 'magisk -V'; do
  run_sh_to "$TIMEOUT_SECONDS" "$F" "$command_text"
done
run_to "$TIMEOUT_SECONDS" "$F" getprop

F=$WORK/module/state.txt
section "$F" module
run_to "$TIMEOUT_SECONDS" "$F" ls -la /data/adb/modules
run_to "$TIMEOUT_SECONDS" "$F" ls -la /data/adb/modules/ts18_documentsui_saf_full
run_to "$TIMEOUT_SECONDS" "$F" find /data/adb/modules/ts18_documentsui_saf_full -maxdepth 7 -type f -print
for source in \
  /data/adb/modules/ts18_documentsui_saf_full/module.prop \
  /data/adb/modules/ts18_documentsui_saf_full/config.default \
  /data/adb/ts18-documentsui-saf.conf \
  /data/adb/ts18-documentsui-saf/applied-state \
  /data/adb/ts18-documentsui-saf/picker-resolver-state \
  /data/adb/ts18-documentsui-saf/rootfs-helper.sh; do
  copy_file_limited "$source" "$WORK/module/$(basename "$source")"
done
find "$STATE_DIR/logs" -maxdepth 1 -type f -name '*.log*' 2>/dev/null | while IFS= read -r source; do
  copy_file_limited "$source" "$WORK/module/logs/$(basename "$source")"
done
collect_reconcile_history

# ----- package stack -----
PACKAGES="com.android.documentsui com.google.android.documentsui com.android.externalstorage com.android.providers.downloads com.android.providers.media $ROOT_PKG com.ts18.safprovider com.mixplorer com.mixplorer.silver io.github.muntashirakon.AppManager me.zhanghai.android.files com.android.storagemanager com.android.sharedstoragebackup"
[ -n "$CLIENT_PACKAGE" ] && PACKAGES="$PACKAGES $CLIENT_PACKAGE"

printf 'package\tuid\tstate\tversionCode\tversionName\tflags\tapkPaths\n' > "$WORK/packages/package-stack.tsv"
F=$WORK/packages/lists.txt
section "$F" packages
run_to "$TIMEOUT_SECONDS" "$F" pm list packages -f -U
run_to "$TIMEOUT_SECONDS" "$F" pm list packages -d -f -U
run_to "$TIMEOUT_SECONDS" "$F" cmd package list users
run_to "$TIMEOUT_SECONDS" "$F" cmd package query-activities -a android.intent.action.OPEN_DOCUMENT_TREE --user "$TARGET_USER"
run_to "$TIMEOUT_SECONDS" "$F" cmd package query-activities -a android.intent.action.OPEN_DOCUMENT -t '*/*' --user "$TARGET_USER"
run_to "$TIMEOUT_SECONDS" "$F" cmd package query-activities -a android.intent.action.CREATE_DOCUMENT -t '*/*' --user "$TARGET_USER"
run_to "$TIMEOUT_SECONDS" "$F" cmd package query-activities -a android.intent.action.GET_CONTENT -t '*/*' --user "$TARGET_USER"

for package in $PACKAGES; do
  package_snapshot_line "$package" >> "$WORK/packages/package-stack.tsv"
  F=$WORK/packages/$package.txt
  section "$F" "package $package"
  run_to "$TIMEOUT_SECONDS" "$F" pm path "$package"
  run_to "$TIMEOUT_SECONDS" "$F" pm dump "$package"
  run_to "$TIMEOUT_SECONDS" "$F" dumpsys package "$package"
  run_to "$TIMEOUT_SECONDS" "$F" appops get --user "$TARGET_USER" "$package"
  uid=$(package_uid "$package")
  printf 'resolved_uid=%s\n' "${uid:-unknown}" >> "$F"
  if [ -n "$uid" ]; then
    run_sh_to "$TIMEOUT_SECONDS" "$F" "magisk --sqlite 'SELECT uid,policy,until,logging,notification FROM policies WHERE uid=$uid;'"
  fi
  [ "$DIAG_COPY_RELEVANT_APKS" = 1 ] && copy_pkg_apks "$package"
done
update_package_baseline

# ----- providers, URI grants and functional queries -----
F=$WORK/providers/registry.txt
section "$F" provider_registry
run_to "$TIMEOUT_SECONDS" "$F" dumpsys package providers
run_to "$TIMEOUT_SECONDS" "$F" dumpsys activity providers
run_sh_to "$TIMEOUT_SECONDS" "$F" "dumpsys package providers | grep -i -A30 -B15 'DOCUMENTS_PROVIDER\|documentsui\|externalstorage\|downloads.documents\|cbkii.tsdocsui\|mixplorer\|AppManager'"

F=$WORK/providers/queries.txt
section "$F" provider_queries
for uri in \
  content://com.android.providers.downloads.documents/root \
  content://com.android.providers.downloads.documents/document/downloads/children \
  content://com.android.externalstorage.documents/root \
  content://com.android.externalstorage.documents/document/primary%3A \
  content://com.android.externalstorage.documents/document/primary%3A/children \
  content://com.android.externalstorage.documents/document/home%3A/children \
  content://$ROOT_AUTH/root; do
  content_query "$F" "$uri"
done

STOCK_PROVIDER_HEALTH=$(probe_content_uri stock-primary-children content://com.android.externalstorage.documents/document/primary%3A/children "$F")
ROOT_PROVIDER_HEALTH=$(probe_content_uri root-provider-roots content://$ROOT_AUTH/root "$F")

root_ids=
if [ -n "$TIMEOUT_CMD" ]; then
  # TIMEOUT_CMD intentionally contains one executable and its timeout applet.
  # shellcheck disable=SC2086
  root_query=$($TIMEOUT_CMD "$TIMEOUT_SECONDS" content query --uri content://$ROOT_AUTH/root --user "$TARGET_USER" 2>/dev/null)
  root_ids=$(printf '%s\n' "$root_query" | sed -n 's/.*document_id=\([^,]*\).*/\1/p')
fi
for document_id in $root_ids; do
  encoded=$(printf '%s' "$document_id" | sed 's/:/%3A/g; s|/|%2F|g; s/+/%2B/g; s/=/%3D/g')
  content_query "$F" "content://$ROOT_AUTH/document/$encoded"
  content_query "$F" "content://$ROOT_AUTH/document/$encoded/children"
done

F=$WORK/uri-grants/state.txt
section "$F" uri_grants
run_to "$TIMEOUT_SECONDS" "$F" dumpsys activity providers
run_to "$TIMEOUT_SECONDS" "$F" dumpsys package
run_sh_to "$TIMEOUT_SECONDS" "$F" "dumpsys activity | grep -i -A20 -B5 'UriPermission\|persisted uri\|granted uri'"
run_sh_to "$TIMEOUT_SECONDS" "$F" "cmd activity get-uid-state $(package_uid "${CLIENT_PACKAGE:-com.android.documentsui}")"
printf 'Automated creation of a persistable client grant is intentionally not attempted.\n' >> "$F"
printf 'Use docs/DEVICE_ACCEPTANCE.md and capture before/after/reboot bundles with TS18_SAF_CLIENT_PACKAGE set.\n' >> "$F"

# The health probes above start the providers before namespace capture.
capture_process_namespace com.android.documentsui
capture_process_namespace com.android.externalstorage
capture_process_namespace "$ROOT_PKG"
[ -n "$CLIENT_PACKAGE" ] && capture_process_namespace "$CLIENT_PACKAGE"

# ----- root helper and storage -----
F=$WORK/root-provider/helper.txt
section "$F" root_provider_helper
safe_root_helper "$F" ping
safe_root_helper "$F" stat /
safe_root_helper "$F" list /
safe_root_helper "$F" stat /storage/emulated/0
safe_root_helper "$F" list /storage/emulated/0
safe_root_helper "$F" stat /system/build.prop

F=$WORK/storage/storage.txt
section "$F" storage
for command_text in \
  'sm list-volumes all' 'sm list-disks' 'sm get-primary-storage-uuid' \
  'dumpsys mount' 'dumpsys storage' 'dumpsys storaged' 'dumpsys user' 'dumpsys diskstats'; do
  run_sh_to "$TIMEOUT_SECONDS" "$F" "$command_text"
done

F=$WORK/paths/mounts.txt
section "$F" mounts_and_paths
for command_text in 'mount' 'cat /proc/mounts' 'cat /proc/self/mountinfo' 'df -h' 'df -i' 'ls -la /' 'ls -la /storage' 'ls -la /mnt' 'ls -la /data/adb'; do
  run_sh_to "$TIMEOUT_SECONDS" "$F" "$command_text"
done
for path in \
  /data/media /data/media/0 /storage /storage/emulated /storage/emulated/0 /sdcard \
  /mnt/runtime/default/emulated/0 /mnt/runtime/read/emulated/0 /mnt/runtime/write/emulated/0 /mnt/runtime/full/emulated/0 \
  /mnt/media_rw /storage/usbdisk0 /storage/usbdisk1 \
  /data/user/0/com.android.documentsui /data/user/0/$ROOT_PKG; do
  printf '\n--- %s ---\n' "$path" >> "$F"
  ls -ldZ "$path" >> "$F" 2>&1 || ls -ld "$path" >> "$F" 2>&1 || true
  readlink -f "$path" >> "$F" 2>&1 || true
  run_sh_to 8 "$F" "find '$path' -mindepth 1 -maxdepth 1 -print | head -n 200"
done

# ----- critical state files and logs -----
say 'Copying relevant package and system state'
for source in \
  /data/system/packages.xml /data/system/packages.list /data/system/packages-stopped.xml \
  /data/system/appops.xml /data/system/storage.xml /data/system/users/0.xml /data/system/users/userlist.xml \
  /system/build.prop /vendor/build.prop /product/build.prop /odm/build.prop /system_ext/build.prop; do
  copy_file_limited "$source" "$WORK/files$source"
done
copy_tree_limited /system/etc/permissions "$WORK/files/system/etc/permissions" 1
copy_tree_limited /system/etc/default-permissions "$WORK/files/system/etc/default-permissions" 1
copy_tree_limited /system/etc/sysconfig "$WORK/files/system/etc/sysconfig" 1
copy_tree_limited /data/anr "$WORK/crash/anr" 1
copy_tree_limited /data/tombstones "$WORK/crash/tombstones" 1
copy_tree_limited /data/system/dropbox "$WORK/crash/dropbox" 1
copy_tree_limited /data/user/0/com.android.documentsui "$WORK/files/data/user/0/com.android.documentsui" 4
copy_tree_limited /data/user/0/$ROOT_PKG "$WORK/files/data/user/0/$ROOT_PKG" 4

F=$WORK/logs/logcat-main.txt
section "$F" logcat_main
run_sh_to 60 "$F" "logcat -d -v threadtime -t 20000"
run_sh_to 30 "$WORK/logs/logcat-events.txt" "logcat -b events -d -v threadtime -t 10000"
run_sh_to 20 "$WORK/logs/logcat-crash.txt" "logcat -b crash -d -v threadtime -t 3000"
run_to "$TIMEOUT_SECONDS" "$WORK/crash/activity-crashes.txt" dumpsys activity crashes
run_sh_to 20 "$WORK/logs/dmesg-tail.txt" "dmesg | tail -n 3000"

grep -Ei 'remountUidExternalStorage|remount.*external|mount mode|ExternalStorageProvider|AppOpsService.*notifyOpChanged|StorageManagerService.*opChanged' \
  "$F" > "$WORK/logs/remount-provider-events.txt" 2>/dev/null || true
analyse_remount_events
capture_system_server_stack

if grep -Eiq 'ts18-documentsui-saf\.xml|component-override.*unknown|Tag component-override is unknown' "$F"; then
  warn 'unsupported TS18 component-override sysconfig warning is still present on the device'
  grep -Ei 'ts18-documentsui-saf\.xml|component-override.*unknown|Tag component-override is unknown' "$F" \
    > "$WORK/logs/unsupported-sysconfig-events.txt" 2>/dev/null || true
fi

# ----- harmless functional smoke tests -----
F=$WORK/smoke/filesystem.txt
section "$F" filesystem_smoke
SMOKE=/storage/emulated/0/Download/TS18-SAF-SMOKE-$TS
run_to "$TIMEOUT_SECONDS" "$F" mkdir -p "$SMOKE"
run_sh_to "$TIMEOUT_SECONDS" "$F" "printf '%s\\n' picker-smoke > '$SMOKE/source.txt'"
run_to "$TIMEOUT_SECONDS" "$F" cat "$SMOKE/source.txt"
run_to "$TIMEOUT_SECONDS" "$F" mv "$SMOKE/source.txt" "$SMOKE/renamed.txt"
run_to "$TIMEOUT_SECONDS" "$F" rm -f -- "$SMOKE/renamed.txt"
run_to "$TIMEOUT_SECONDS" "$F" rmdir "$SMOKE"

F=$WORK/smoke/root-helper.txt
section "$F" root_helper_smoke
ROOT_SMOKE=/storage/emulated/0/Download/TS18-ROOT-SMOKE-$TS
safe_root_helper "$F" create /storage/emulated/0/Download "TS18-ROOT-SMOKE-$TS" dir
safe_root_helper "$F" create "$ROOT_SMOKE" smoke.txt file
run_sh_to "$TIMEOUT_SECONDS" "$F" "printf '%s\\n' root-provider-smoke > '$ROOT_SMOKE/smoke.txt'"
safe_root_helper "$F" stat "$ROOT_SMOKE/smoke.txt"
safe_root_helper "$F" rename "$ROOT_SMOKE/smoke.txt" renamed.txt
safe_root_helper "$F" delete "$ROOT_SMOKE/renamed.txt"
safe_root_helper "$F" delete "$ROOT_SMOKE"

# ----- final summary -----
{
  printf 'TS18 Full File Picker diagnostic summary\n'
  printf 'result=%s\n' "$RESULT"
  printf 'warnings=%s\n' "$WARN_COUNT"
  printf 'run=%s\n' "$RUN_ID"
  printf 'mode=%s\n' "$MODE"
  printf 'module_version=%s\n' "$VERSION"
  printf 'module_version_code=%s\n' "$VERSION_CODE"
  printf 'build=%s\n' "$(getprop ro.build.display.id 2>/dev/null)"
  printf 'sdk=%s\n' "$(getprop ro.build.version.sdk 2>/dev/null)"
  printf 'documentsui=%s\n' "$(pm path com.android.documentsui 2>/dev/null | head -n 1)"
  printf 'externalstorage=%s\n' "$(pm path com.android.externalstorage 2>/dev/null | head -n 1)"
  printf 'rootprovider=%s\n' "$(pm path "$ROOT_PKG" 2>/dev/null | head -n 1)"
  printf 'root_helper=%s\n' "$([ -x "$ROOT_HELPER" ] && echo present || echo missing)"
  printf 'latest_reconcile_mutations=%s\n' "${LATEST_MUTATIONS:-unknown}"
  printf 'latest_reconcile_noops=%s\n' "${LATEST_NOOPS:-unknown}"
  printf 'previous_reconcile_mutations=%s\n' "${PREVIOUS_MUTATIONS:-unknown}"
  printf 'remount_provider_event_count=%s\n' "${REMOUNT_EVENT_COUNT:-0}"
  printf 'remount_peak_events_per_second=%s\n' "${REMOUNT_PEAK_RATE:-0}"
  printf 'remount_storm=%s\n' "${REMOUNT_STORM:-0}"
  printf 'stock_provider_health=%s\n' "${STOCK_PROVIDER_HEALTH:-unknown}"
  printf 'root_provider_health=%s\n' "${ROOT_PROVIDER_HEALTH:-unknown}"
  printf 'client_package=%s\n' "${CLIENT_PACKAGE:-not-specified}"
  printf 'work=%s\n' "$WORK"
} > "$SUMMARY"

ARCHIVE_PRIVATE=$PRIVATE_BASE/$RUN_ID.tar.gz
ARCHIVE=$EXPORT_BASE/$RUN_ID.tar.gz
CHECKSUM=$ARCHIVE.sha256
say "Finalising immutable archive: $ARCHIVE"
# Do not write into WORK after this point: archive input must remain immutable.
if tar -czf "$ARCHIVE_PRIVATE" -C "$PRIVATE_BASE" "$RUN_ID" >/dev/null 2>&1 && \
   tar -tzf "$ARCHIVE_PRIVATE" >/dev/null 2>&1 && \
   cp -f "$ARCHIVE_PRIVATE" "$ARCHIVE" 2>/dev/null && \
   tar -tzf "$ARCHIVE" >/dev/null 2>&1; then
  sha256sum "$ARCHIVE" > "$CHECKSUM" 2>/dev/null || true
  rm -rf "$WORK" "$ARCHIVE_PRIVATE" 2>/dev/null || true
  printf '==================================================\n'
  printf 'RESULT: %s\n' "$RESULT"
  printf 'Warnings: %s\n' "$WARN_COUNT"
  printf 'Archive: %s\n' "$ARCHIVE"
  printf 'Checksum: %s\n' "$CHECKSUM"
  printf '==================================================\n'
  exit 0
fi

printf 'FAILED: archive could not be verified; uncompressed evidence remains at %s\n' "$WORK" >&2
exit 1
