#!/system/bin/sh
# Comprehensive manual diagnostics for TS18 Full File Picker.
# Work and final archives stay under /storage/emulated/0/Download.

MODE=${1:-full}
TARGET_USER=${TARGET_USER:-0}
TS=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo now)
OUT_BASE=${TS18_SAF_EXPORT_ROOT:-/storage/emulated/0/Download/TS18-SAF-Diagnostics}
RUN_ID=ts18-docsui-v101-${MODE}-${TS}
WORK=$OUT_BASE/$RUN_ID
LOG=$WORK/collector.log
SUMMARY=$WORK/SUMMARY.txt
TIMEOUT_SECONDS=${TS18_SAF_TIMEOUT_SECONDS:-30}
MAX_COPY_BYTES=${DIAG_MAX_COPY_BYTES:-52428800}
DIAG_COPY_RELEVANT_APKS=${DIAG_COPY_RELEVANT_APKS:-1}
DIAG_COPY_ALL_APKS=${DIAG_COPY_ALL_APKS:-0}
ROOT_AUTH=com.cbkii.tsdocsui.root.documents
ROOT_PKG=com.cbkii.tsdocsui.rootprovider
ROOT_HELPER=/data/adb/ts18-documentsui-saf/rootfs-helper.sh

mkdir -p "$WORK" 2>/dev/null || { echo "STOP: cannot create $WORK"; exit 1; }
for directory in identity module packages providers storage paths permissions root-provider logs crash files apks smoke; do
  mkdir -p "$WORK/$directory" 2>/dev/null || true
done

say() {
  echo "[$(date '+%H:%M:%S' 2>/dev/null || echo time)] $*" | tee -a "$LOG" >&2
}

section() {
  file=$1
  title=$2
  {
    echo
    echo "===== $title ====="
    echo "time=$(date '+%F %T %z' 2>/dev/null || echo unknown)"
  } >> "$file" 2>&1
}

find_timeout() {
  if [ -x /data/adb/magisk/busybox ]; then echo "/data/adb/magisk/busybox timeout"; return; fi
  command -v timeout >/dev/null 2>&1 && { echo timeout; return; }
  command -v busybox >/dev/null 2>&1 && { echo "busybox timeout"; return; }
  echo ""
}
TIMEOUT_CMD=$(find_timeout)

run_to() {
  seconds=$1
  file=$2
  shift 2
  { echo; printf '$'; printf ' %s' "$@"; echo; } >> "$file" 2>&1
  if [ -n "$TIMEOUT_CMD" ]; then
    # shellcheck disable=SC2086
    $TIMEOUT_CMD "$seconds" "$@" >> "$file" 2>&1
  else
    echo "[warn] timeout unavailable" >> "$file"
    "$@" >> "$file" 2>&1
  fi
  rc=$?
  echo "[exit=$rc]" >> "$file"
  return 0
}

run_sh_to() {
  seconds=$1
  file=$2
  shift 2
  command_text=$*
  { echo; echo "\$ sh -c '$command_text'"; } >> "$file" 2>&1
  if [ -n "$TIMEOUT_CMD" ]; then
    # shellcheck disable=SC2086
    $TIMEOUT_CMD "$seconds" sh -c "$command_text" >> "$file" 2>&1
  else
    echo "[warn] timeout unavailable" >> "$file"
    sh -c "$command_text" >> "$file" 2>&1
  fi
  rc=$?
  echo "[exit=$rc]" >> "$file"
  return 0
}

content_query() {
  file=$1
  uri=$2
  { echo; echo "--- $uri user=$TARGET_USER ---"; } >> "$file"
  run_sh_to "$TIMEOUT_SECONDS" "$file" "content query --uri '$uri' --user '$TARGET_USER'"
  run_sh_to "$TIMEOUT_SECONDS" "$file" "content query --uri '$uri'"
}

copy_file_limited() {
  source=$1
  destination=$2
  [ -f "$source" ] || return 0
  size=$(wc -c < "$source" 2>/dev/null || echo 0)
  case "$size" in ''|*[!0-9]*) size=0 ;; esac
  if [ "$MAX_COPY_BYTES" -gt 0 ] && [ "$size" -gt "$MAX_COPY_BYTES" ]; then
    echo "SKIP size=$size path=$source" >> "$WORK/files/SKIPPED-LARGE-FILES.txt"
    return 0
  fi
  mkdir -p "$(dirname "$destination")" 2>/dev/null || return 0
  cp -a "$source" "$destination" >> "$LOG" 2>&1 || echo "copy failed: $source" >> "$LOG"
}

copy_tree_limited() {
  source=$1
  destination=$2
  depth=${3:-3}
  [ -d "$source" ] || return 0
  find "$source" -maxdepth "$depth" -type f 2>/dev/null | while IFS= read -r file; do
    relative=${file#$source/}
    copy_file_limited "$file" "$destination/$relative"
  done
}

copy_pkg_apks() {
  package=$1
  destination=$WORK/apks/$package
  mkdir -p "$destination" 2>/dev/null || true
  pm path "$package" 2>/dev/null | sed 's/^package://' | while IFS= read -r apk; do
    [ -f "$apk" ] || continue
    copy_file_limited "$apk" "$destination/$(basename "$apk")"
    sha256sum "$apk" >> "$WORK/apks/SHA256SUMS.txt" 2>/dev/null || true
  done
}

safe_root_helper() {
  file=$1
  action=$2
  shift 2
  [ -x "$ROOT_HELPER" ] || { echo "root helper missing: $ROOT_HELPER" >> "$file"; return 0; }
  [ -x /data/adb/magisk/busybox ] || { echo "Magisk BusyBox missing" >> "$file"; return 0; }
  encoded=""
  for value in "$@"; do
    arg=$(printf '%s' "$value" | /data/adb/magisk/busybox base64 2>/dev/null | /data/adb/magisk/busybox tr -d '\r\n')
    encoded="$encoded '$arg'"
  done
  run_sh_to "$TIMEOUT_SECONDS" "$file" "'$ROOT_HELPER' '$action' $encoded"
}

say "Starting TS18 file-picker diagnostics"
say "Output directory: $WORK"

F=$WORK/identity/system.txt
section "$F" identity
for command_text in \
  'id' 'uname -a' 'getenforce' 'cat /proc/uptime' \
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
run_to "$TIMEOUT_SECONDS" "$F" find /data/adb/modules/ts18_documentsui_saf_full -maxdepth 6 -type f -print
for source in \
  /data/adb/modules/ts18_documentsui_saf_full/module.prop \
  /data/adb/modules/ts18_documentsui_saf_full/config.default \
  /data/adb/ts18-documentsui-saf.conf \
  /data/adb/ts18-documentsui-saf/applied-state \
  /data/adb/ts18-documentsui-saf/rootfs-helper.sh \
  /data/adb/ts18-documentsui-saf/logs/install-v100.log \
  /data/adb/ts18-documentsui-saf/logs/service-v100.log \
  /data/adb/ts18-documentsui-saf/logs/post-fs-data-v100.log; do
  copy_file_limited "$source" "$WORK/module/$(basename "$source")"
done

F=$WORK/packages/lists.txt
section "$F" packages
run_to "$TIMEOUT_SECONDS" "$F" pm list packages -f -U
run_to "$TIMEOUT_SECONDS" "$F" pm list packages -d -f -U
run_to "$TIMEOUT_SECONDS" "$F" cmd package list users
run_to "$TIMEOUT_SECONDS" "$F" cmd package query-activities -a android.intent.action.OPEN_DOCUMENT_TREE --user "$TARGET_USER"
run_to "$TIMEOUT_SECONDS" "$F" cmd package query-activities -a android.intent.action.OPEN_DOCUMENT -t '*/*' --user "$TARGET_USER"
run_to "$TIMEOUT_SECONDS" "$F" cmd package query-activities -a android.intent.action.CREATE_DOCUMENT -t '*/*' --user "$TARGET_USER"
run_to "$TIMEOUT_SECONDS" "$F" cmd package query-activities -a android.intent.action.GET_CONTENT -t '*/*' --user "$TARGET_USER"

PACKAGES="com.android.documentsui com.google.android.documentsui com.android.externalstorage com.android.providers.downloads com.android.providers.media $ROOT_PKG com.mixplorer io.github.muntashirakon.AppManager me.zhanghai.android.files com.android.storagemanager com.android.sharedstoragebackup"
for package in $PACKAGES; do
  F=$WORK/packages/$package.txt
  section "$F" "package $package"
  run_to "$TIMEOUT_SECONDS" "$F" pm path "$package"
  run_to "$TIMEOUT_SECONDS" "$F" pm dump "$package"
  run_to "$TIMEOUT_SECONDS" "$F" appops get "$package"
  uid=$(cmd package list packages -U "$package" 2>/dev/null | sed -n 's/.* uid://p' | head -n 1)
  echo "resolved_uid=$uid" >> "$F"
  if [ -n "$uid" ]; then
    run_sh_to "$TIMEOUT_SECONDS" "$F" "magisk --sqlite 'SELECT uid,policy,until,logging,notification FROM policies WHERE uid=$uid;'"
  fi
  [ "$DIAG_COPY_RELEVANT_APKS" = 1 ] && copy_pkg_apks "$package"
done

if [ "$DIAG_COPY_ALL_APKS" = 1 ]; then
  say "Copying all installed APKs"
  pm list packages -f 2>/dev/null | sed -n 's/^package://p' | while IFS= read -r line; do
    apk=${line%%=*}
    package=${line##*=}
    [ -f "$apk" ] && copy_file_limited "$apk" "$WORK/apks/all/$package/$(basename "$apk")"
  done
fi

F=$WORK/providers/registry.txt
section "$F" provider_registry
run_to "$TIMEOUT_SECONDS" "$F" dumpsys package providers
run_to "$TIMEOUT_SECONDS" "$F" dumpsys activity providers
run_sh_to "$TIMEOUT_SECONDS" "$F" "dumpsys package providers | grep -i -A24 -B12 'DOCUMENTS_PROVIDER\|documentsui\|externalstorage\|downloads.documents\|cbkii.tsdocsui\|mixplorer\|AppManager'"

F=$WORK/providers/queries.txt
section "$F" provider_queries
for uri in \
  content://com.android.providers.downloads.documents/root \
  content://com.android.providers.downloads.documents/document/downloads/children \
  content://com.android.externalstorage.documents/root \
  content://com.android.externalstorage.documents/document/primary%3A \
  content://com.android.externalstorage.documents/document/primary%3A/children \
  content://com.android.externalstorage.documents/document/home%3A/children \
  content://$ROOT_AUTH/root \
  content://com.mixplorer.doc/root; do
  content_query "$F" "$uri"
done

# Discover root-provider document IDs and query their first level exactly as DocumentsUI does.
run_sh_to "$TIMEOUT_SECONDS" "$F" "content query --uri content://$ROOT_AUTH/root --user '$TARGET_USER'"
root_ids=$(content query --uri content://$ROOT_AUTH/root --user "$TARGET_USER" 2>/dev/null | sed -n 's/.*document_id=\([^,]*\).*/\1/p')
for document_id in $root_ids; do
  encoded=$(printf '%s' "$document_id" | sed 's/:/%3A/g; s|/|%2F|g; s/+/%2B/g; s/=/%3D/g')
  content_query "$F" "content://$ROOT_AUTH/document/$encoded"
  content_query "$F" "content://$ROOT_AUTH/document/$encoded/children"
done

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
for command_text in 'mount' 'cat /proc/mounts' 'cat /proc/self/mountinfo' 'df -h' 'ls -la /' 'ls -la /storage' 'ls -la /mnt' 'ls -la /data/adb'; do
  run_sh_to "$TIMEOUT_SECONDS" "$F" "$command_text"
done
for path in \
  /data/media /data/media/0 /storage /storage/emulated /storage/emulated/0 /sdcard \
  /mnt/runtime/default/emulated/0 /mnt/runtime/read/emulated/0 /mnt/runtime/write/emulated/0 /mnt/runtime/full/emulated/0 \
  /mnt/media_rw /storage/usbdisk0 /storage/usbdisk1 \
  /data/user/0/com.android.documentsui /data/user/0/$ROOT_PKG; do
  echo "--- $path ---" >> "$F"
  ls -ldZ "$path" >> "$F" 2>&1 || ls -ld "$path" >> "$F" 2>&1 || true
  readlink -f "$path" >> "$F" 2>&1 || true
  run_sh_to "$TIMEOUT_SECONDS" "$F" "ls -la '$path' | head -n 200"
done
run_sh_to "$TIMEOUT_SECONDS" "$F" "find /storage/emulated/0 -maxdepth 4 -print | head -n 5000"
run_sh_to "$TIMEOUT_SECONDS" "$F" "find /data/adb -maxdepth 6 -print | head -n 5000"

say "Copying relevant package and system state"
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

F=$WORK/logs/logcat.txt
section "$F" logs
run_sh_to 45 "$F" "logcat -d -t 10000"
run_sh_to "$TIMEOUT_SECONDS" "$F" "logcat -b events -d -t 5000"
run_sh_to "$TIMEOUT_SECONDS" "$F" "logcat -b crash -d -t 2000"
run_sh_to "$TIMEOUT_SECONDS" "$F" "dumpsys activity crashes"
run_sh_to "$TIMEOUT_SECONDS" "$F" "dmesg | tail -n 3000"

F=$WORK/smoke/filesystem.txt
section "$F" filesystem_smoke
SMOKE=/storage/emulated/0/Download/TS18-SAF-SMOKE-$TS
run_to "$TIMEOUT_SECONDS" "$F" mkdir -p "$SMOKE"
run_sh_to "$TIMEOUT_SECONDS" "$F" "echo picker-smoke > '$SMOKE/source.txt'"
run_to "$TIMEOUT_SECONDS" "$F" cat "$SMOKE/source.txt"
run_to "$TIMEOUT_SECONDS" "$F" mv "$SMOKE/source.txt" "$SMOKE/renamed.txt"
run_to "$TIMEOUT_SECONDS" "$F" rm -f "$SMOKE/renamed.txt"
run_to "$TIMEOUT_SECONDS" "$F" rmdir "$SMOKE"

F=$WORK/smoke/root-helper.txt
section "$F" root_helper_smoke
ROOT_SMOKE=/storage/emulated/0/Download/TS18-ROOT-SMOKE-$TS
safe_root_helper "$F" create /storage/emulated/0/Download "TS18-ROOT-SMOKE-$TS" dir
safe_root_helper "$F" create "$ROOT_SMOKE" smoke.txt file
run_sh_to "$TIMEOUT_SECONDS" "$F" "echo root-provider-smoke > '$ROOT_SMOKE/smoke.txt'"
safe_root_helper "$F" stat "$ROOT_SMOKE/smoke.txt"
safe_root_helper "$F" rename "$ROOT_SMOKE/smoke.txt" renamed.txt
safe_root_helper "$F" delete "$ROOT_SMOKE/renamed.txt"
safe_root_helper "$F" delete "$ROOT_SMOKE"

{
  echo "TS18 Full File Picker diagnostic summary"
  echo "run=$RUN_ID"
  echo "build=$(getprop ro.build.display.id 2>/dev/null)"
  echo "sdk=$(getprop ro.build.version.sdk 2>/dev/null)"
  echo "documentsui=$(pm path com.android.documentsui 2>/dev/null | head -n 1)"
  echo "externalstorage=$(pm path com.android.externalstorage 2>/dev/null | head -n 1)"
  echo "rootprovider=$(pm path $ROOT_PKG 2>/dev/null | head -n 1)"
  echo "root_helper=$([ -x "$ROOT_HELPER" ] && echo present || echo missing)"
  echo "output=$WORK"
} > "$SUMMARY"

ARCHIVE=$OUT_BASE/$RUN_ID.tar.gz
say "Creating archive: $ARCHIVE"
if tar -czf "$ARCHIVE" -C "$OUT_BASE" "$RUN_ID" >> "$LOG" 2>&1; then
  if tar -tzf "$ARCHIVE" >/dev/null 2>&1; then
    sha256sum "$ARCHIVE" > "$ARCHIVE.sha256" 2>/dev/null || true
    rm -rf "$WORK" 2>/dev/null || true
    echo "DONE: $ARCHIVE"
    exit 0
  fi
fi

echo "WARN: archive could not be verified; uncompressed diagnostics remain at $WORK"
exit 1
