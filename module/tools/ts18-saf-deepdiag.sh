#!/system/bin/sh
# TS18 SAF v0.8.0 comprehensive manual diagnostics.
# Final output and work directory are under /storage/emulated/0/Download only.

MODE=${1:-full}
TARGET_USER=${TARGET_USER:-0}
TS=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo now)
OUT_BASE=${TS18_SAF_EXPORT_ROOT:-/storage/emulated/0/Download/TS18-SAF-Diagnostics}
RUN_ID="ts18-saf-v080-${MODE}-${TS}"
WORK="$OUT_BASE/$RUN_ID"
LOG="$WORK/collector.log"
SUMMARY="$WORK/SUMMARY.txt"
TIMEOUT_SECONDS=${TS18_SAF_TIMEOUT_SECONDS:-30}
MAX_COPY_BYTES=${DIAG_MAX_COPY_BYTES:-52428800}
DIAG_COPY_RELEVANT_APKS=${DIAG_COPY_RELEVANT_APKS:-1}
DIAG_COPY_ALL_APKS=${DIAG_COPY_ALL_APKS:-0}

mkdir -p "$WORK" 2>/dev/null || { echo "STOP: cannot create $WORK"; exit 1; }
mkdir -p "$WORK"/identity "$WORK"/packages "$WORK"/providers "$WORK"/storage "$WORK"/paths "$WORK"/files "$WORK"/apks "$WORK"/logs "$WORK"/smoke "$WORK"/module "$WORK"/crash 2>/dev/null || true
say() { echo "[$(date '+%H:%M:%S' 2>/dev/null || echo time)] $*" | tee -a "$LOG" >&2; }
section() { f="$1"; title="$2"; { echo; echo "===== $title ====="; echo "time=$(date '+%F %T %z' 2>/dev/null || echo unknown)"; } >> "$f" 2>&1; }

find_timeout() {
  if [ -x /data/adb/magisk/busybox ]; then echo "/data/adb/magisk/busybox timeout"; return; fi
  command -v timeout >/dev/null 2>&1 && { echo "timeout"; return; }
  command -v busybox >/dev/null 2>&1 && { echo "busybox timeout"; return; }
  command -v toybox >/dev/null 2>&1 && { echo "toybox timeout"; return; }
  echo ""
}
TIMEOUT_CMD="$(find_timeout)"

run_to() {
  sec="$1"; file="$2"; shift 2
  { echo; echo "\$ $*"; } >> "$file" 2>&1
  if [ -n "$TIMEOUT_CMD" ]; then
    # shellcheck disable=SC2086
    $TIMEOUT_CMD "$sec" "$@" >> "$file" 2>&1
  else
    echo "[warn] timeout unavailable; running without outer timeout" >> "$file"
    "$@" >> "$file" 2>&1
  fi
  rc=$?
  echo "[exit=$rc]" >> "$file" 2>&1
  return 0
}
run_sh_to() {
  sec="$1"; file="$2"; shift 2; cmd="$*"
  { echo; echo "\$ sh -c '$cmd'"; } >> "$file" 2>&1
  if [ -n "$TIMEOUT_CMD" ]; then
    # shellcheck disable=SC2086
    $TIMEOUT_CMD "$sec" sh -c "$cmd" >> "$file" 2>&1
  else
    echo "[warn] timeout unavailable; running without outer timeout" >> "$file"
    sh -c "$cmd" >> "$file" 2>&1
  fi
  echo "[exit=$?]" >> "$file" 2>&1
}
content_query_to() {
  file="$1"; uri="$2"
  { echo; echo "--- content query $uri user=$TARGET_USER ---"; } >> "$file"
  run_sh_to "$TIMEOUT_SECONDS" "$file" "content query --uri '$uri' --user '$TARGET_USER'"
  run_sh_to "$TIMEOUT_SECONDS" "$file" "content --user '$TARGET_USER' query --uri '$uri'"
  run_sh_to "$TIMEOUT_SECONDS" "$file" "content query --uri '$uri'"
}
copy_file_limited() {
  src="$1"; dst="$2"
  [ -e "$src" ] || return 0
  size=$(wc -c < "$src" 2>/dev/null || echo 0)
  case "$size" in ''|*[!0-9]*) size=0 ;; esac
  mkdir -p "$(dirname "$dst")" 2>/dev/null || return 0
  if [ "$MAX_COPY_BYTES" -gt 0 ] && [ "$size" -gt "$MAX_COPY_BYTES" ]; then
    echo "SKIP large file $src size=$size max=$MAX_COPY_BYTES" >> "$WORK/files/SKIPPED-LARGE-FILES.txt"
    return 0
  fi
  cp -a "$src" "$dst" >> "$LOG" 2>&1 || echo "copy failed: $src" >> "$LOG"
}
copy_tree_limited() {
  src="$1"; dst="$2"; maxdepth="${3:-3}"
  [ -d "$src" ] || return 0
  mkdir -p "$dst" 2>/dev/null || true
  find "$src" -maxdepth "$maxdepth" -type f 2>/dev/null | while IFS= read -r f; do
    rel=${f#$src/}
    copy_file_limited "$f" "$dst/$rel"
  done
}
copy_pkg_apks() {
  pkg="$1"; dst="$WORK/apks/$pkg"; mkdir -p "$dst" 2>/dev/null || true
  pm path "$pkg" 2>/dev/null | sed 's/^package://' | while IFS= read -r apk; do
    [ -n "$apk" ] || continue
    copy_file_limited "$apk" "$dst/$(basename "$apk")"
    sha256sum "$apk" >> "$WORK/apks/SHA256SUMS.txt" 2>/dev/null || true
  done
}

say "Starting TS18 SAF v0.8.0 diagnostics mode=$MODE"
say "Output directory: $WORK"
say "Timeout command: ${TIMEOUT_CMD:-none} seconds=$TIMEOUT_SECONDS"

F="$WORK/identity/system.txt"; section "$F" identity
for c in 'id' 'uname -a' 'getenforce' 'cat /proc/uptime' 'getprop ro.build.display.id' 'getprop ro.build.version.sdk' 'getprop ro.product.device' 'getprop ro.product.board' 'getprop ro.hardware' 'getprop ro.boot.verifiedbootstate' 'getprop ro.boot.vbmeta.device_state'; do run_sh_to "$TIMEOUT_SECONDS" "$F" "$c"; done
run_to "$TIMEOUT_SECONDS" "$F" getprop

F="$WORK/module/module-state.txt"; section "$F" module
for p in /data/adb/modules/ts18_documentsui_saf_full/module.prop /data/adb/modules/ts18_documentsui_saf_full/config.default /data/adb/ts18-documentsui-saf.conf /data/adb/ts18-documentsui-saf/logs/service-v080.log /data/adb/ts18-documentsui-saf/logs/post-fs-data-v080.log /data/adb/ts18-documentsui-saf/logs/install-v080.log; do copy_file_limited "$p" "$WORK/module/$(basename "$p")"; done
run_to "$TIMEOUT_SECONDS" "$F" ls -la /data/adb/modules
run_to "$TIMEOUT_SECONDS" "$F" ls -la /data/adb/modules/ts18_documentsui_saf_full
run_to "$TIMEOUT_SECONDS" "$F" find /data/adb/modules/ts18_documentsui_saf_full -maxdepth 5 -type f -print

F="$WORK/packages/package-lists.txt"; section "$F" packages
run_to "$TIMEOUT_SECONDS" "$F" pm list packages -f -U
run_to "$TIMEOUT_SECONDS" "$F" pm list packages -d -f -U
run_to "$TIMEOUT_SECONDS" "$F" pm list permissions -d -g
run_to "$TIMEOUT_SECONDS" "$F" cmd package list users
run_to "$TIMEOUT_SECONDS" "$F" cmd package resolve-activity --brief -a android.intent.action.OPEN_DOCUMENT_TREE
run_to "$TIMEOUT_SECONDS" "$F" cmd package query-activities -a android.intent.action.OPEN_DOCUMENT_TREE
run_to "$TIMEOUT_SECONDS" "$F" cmd package query-activities -a android.intent.action.GET_CONTENT -t '*/*'
run_to "$TIMEOUT_SECONDS" "$F" cmd package query-activities -a android.intent.action.OPEN_DOCUMENT -t '*/*'

PKGS="com.android.documentsui com.google.android.documentsui com.ts18.safprovider com.android.externalstorage com.android.providers.downloads com.android.providers.media com.android.storagemanager com.android.storageclearmanager com.android.sharedstoragebackup com.mixplorer me.zhanghai.android.files io.github.muntashirakon.AppManager com.google.android.documentsui"
for pkg in $PKGS; do
  F="$WORK/packages/$pkg.txt"; section "$F" "package $pkg"
  run_to "$TIMEOUT_SECONDS" "$F" pm path "$pkg"
  run_to "$TIMEOUT_SECONDS" "$F" pm dump "$pkg"
  run_to "$TIMEOUT_SECONDS" "$F" appops get "$pkg"
  if [ "$DIAG_COPY_RELEVANT_APKS" = "1" ]; then copy_pkg_apks "$pkg"; fi
done
if [ "$DIAG_COPY_ALL_APKS" = "1" ]; then
  say "Copying all APKs is enabled; this may be large"
  pm list packages -f 2>/dev/null | sed -n 's/^package://p' | while IFS= read -r line; do
    apk=${line%%=*}; pkg=${line##*=}; [ -n "$apk" ] && [ -n "$pkg" ] || continue
    copy_file_limited "$apk" "$WORK/apks/all/$pkg/$(basename "$apk")"
  done
fi

F="$WORK/providers/provider-registry.txt"; section "$F" providers
run_to "$TIMEOUT_SECONDS" "$F" dumpsys package providers
run_sh_to "$TIMEOUT_SECONDS" "$F" "dumpsys package providers | grep -i -A18 -B10 'android.content.action.DOCUMENTS_PROVIDER\|documentsui\|downloads.documents\|externalstorage\|ts18.safprovider\|mixplorer\|zhanghai\|AppManager'"
run_to "$TIMEOUT_SECONDS" "$F" dumpsys activity providers

F="$WORK/providers/content-queries.txt"; section "$F" "content queries"
for uri in \
  content://com.ts18.safprovider.documents/root \
  content://com.ts18.safprovider.documents/document/ts18_internal%3A \
  content://com.ts18.safprovider.documents/document/ts18_internal%3A/children \
  content://com.android.providers.downloads.documents/root \
  content://com.android.providers.downloads.documents/document/downloads \
  content://com.android.providers.downloads.documents/document/downloads/children \
  content://com.android.externalstorage.documents/root \
  content://com.android.externalstorage.documents/document/home%3A \
  content://com.android.externalstorage.documents/document/home%3A/children \
  content://com.android.externalstorage.documents/document/primary%3A \
  content://com.android.externalstorage.documents/document/primary%3A/children \
  content://com.mixplorer.doc/root; do
  content_query_to "$F" "$uri"
done

F="$WORK/storage/storage-manager.txt"; section "$F" storage
for c in 'sm list-volumes all' 'sm list-disks' 'sm get-primary-storage-uuid' 'cmd storage help' 'cmd storage list-volumes all' 'dumpsys mount' 'dumpsys storage' 'dumpsys storaged' 'dumpsys user' 'dumpsys diskstats'; do run_sh_to "$TIMEOUT_SECONDS" "$F" "$c"; done

F="$WORK/paths/mounts-and-paths.txt"; section "$F" paths
for c in 'mount' 'cat /proc/mounts' 'cat /proc/self/mountinfo' 'df -h' 'ls -la /' 'ls -la /storage' 'ls -la /mnt' 'ls -la /data/adb'; do run_sh_to "$TIMEOUT_SECONDS" "$F" "$c"; done
for p in /data/media /data/media/0 /storage /storage/emulated /storage/emulated/0 /sdcard /mnt/runtime/default/emulated/0 /mnt/runtime/read/emulated/0 /mnt/runtime/write/emulated/0 /mnt/runtime/full/emulated/0 /mnt/media_rw /mnt/media_rw/usbdisk0 /mnt/media_rw/usbdisk1 /storage/usbdisk0 /storage/usbdisk1 /data/user/0/com.android.documentsui /data/user/0/com.ts18.safprovider /data/data/com.android.documentsui /data/data/com.ts18.safprovider; do
  echo "--- $p ---" >> "$F"
  ls -ldZ "$p" >> "$F" 2>&1 || ls -ld "$p" >> "$F" 2>&1 || true
  readlink -f "$p" >> "$F" 2>&1 || true
  ls -laZ "$p" | head -n 120 >> "$F" 2>&1 || ls -la "$p" | head -n 120 >> "$F" 2>&1 || true
done
run_sh_to "$TIMEOUT_SECONDS" "$F" "find /storage/emulated/0 -maxdepth 4 -print | head -n 3000"
run_sh_to "$TIMEOUT_SECONDS" "$F" "find /data/adb -maxdepth 6 -print"
run_sh_to "$TIMEOUT_SECONDS" "$F" "find /data/user/0/com.android.documentsui /data/user/0/com.ts18.safprovider /data/data/com.android.documentsui /data/data/com.ts18.safprovider -maxdepth 6 -print 2>/dev/null"

say "Copying relevant system/app state files"
for p in \
  /data/system/packages.xml /data/system/packages.list /data/system/packages-stopped.xml /data/system/appops.xml /data/system/storage.xml /data/system/users/0.xml /data/system/users/userlist.xml \
  /system/build.prop /vendor/build.prop /product/build.prop /odm/build.prop /system_ext/build.prop \
  /data/anr/traces.txt; do copy_file_limited "$p" "$WORK/files${p}"; done
copy_tree_limited /system/etc/permissions "$WORK/files/system/etc/permissions" 1
copy_tree_limited /system/etc/default-permissions "$WORK/files/system/etc/default-permissions" 1
copy_tree_limited /system/etc/sysconfig "$WORK/files/system/etc/sysconfig" 1
copy_tree_limited /data/anr "$WORK/crash/data-anr" 1
copy_tree_limited /data/tombstones "$WORK/crash/tombstones" 1
copy_tree_limited /data/system/dropbox "$WORK/crash/dropbox" 1
copy_tree_limited /data/user/0/com.android.documentsui "$WORK/files/data/user/0/com.android.documentsui" 4
copy_tree_limited /data/user/0/com.ts18.safprovider "$WORK/files/data/user/0/com.ts18.safprovider" 4

F="$WORK/smoke/filesystem-smoke.txt"; section "$F" smoke
for root in /storage/emulated/0/Download /storage/emulated/0/Documents /storage/usbdisk0 /storage/usbdisk1; do
  [ -d "$root" ] || { echo "skip absent $root" >> "$F"; continue; }
  SD="$root/TS18-SAF-SMOKE-$TS"; SF="$SD/smoke.txt"; SR="$SD/smoke-renamed.txt"
  run_to "$TIMEOUT_SECONDS" "$F" mkdir -p "$SD"
  run_sh_to "$TIMEOUT_SECONDS" "$F" "echo ts18-saf-v080 > '$SF'"
  run_to "$TIMEOUT_SECONDS" "$F" cat "$SF"
  run_to "$TIMEOUT_SECONDS" "$F" mv "$SF" "$SR"
  run_to "$TIMEOUT_SECONDS" "$F" rm -f "$SR"
  run_to "$TIMEOUT_SECONDS" "$F" rmdir "$SD"
done

F="$WORK/logs/logs.txt"; section "$F" logs
run_sh_to 45 "$F" "logcat -d -t 5000"
run_sh_to 45 "$F" "logcat -b crash -d -t 1000"
run_sh_to 45 "$F" "logcat -d -t 5000 | grep -iE 'DocumentsUI|TS18DocumentsProvider|safprovider|ExternalStorage|DownloadStorage|DocumentsProvider|ActivityInterceptor|AppManager|AndroidRuntime|FATAL EXCEPTION|SecurityException|Permission Denial|FileNotFoundException|NullPointerException|SQLite|roots|picker'"
run_sh_to 45 "$F" "dmesg | tail -n 1000"
run_to "$TIMEOUT_SECONDS" "$F" dumpsys activity crashes
run_to "$TIMEOUT_SECONDS" "$F" dumpsys activity lastanr
run_to "$TIMEOUT_SECONDS" "$F" dumpsys window windows
run_to "$TIMEOUT_SECONDS" "$F" dumpsys activity activities

cat > "$SUMMARY" <<EOF
TS18 SAF v0.8.0 diagnostics
Run: $RUN_ID
Mode: $MODE
Output: $WORK
Archive: $OUT_BASE/$RUN_ID.tar.gz
Build: $(getprop ro.build.display.id 2>/dev/null) SDK $(getprop ro.build.version.sdk 2>/dev/null)
Identity: $(id 2>/dev/null)

Important files:
- providers/content-queries.txt
- providers/provider-registry.txt
- packages/com.android.documentsui.txt
- packages/com.ts18.safprovider.txt
- packages/io.github.muntashirakon.AppManager.txt
- storage/storage-manager.txt
- paths/mounts-and-paths.txt
- logs/logs.txt
- smoke/filesystem-smoke.txt
EOF

say "Packing archive"
ARCHIVE="$OUT_BASE/$RUN_ID.tar.gz"
( cd "$OUT_BASE" && tar -czf "$ARCHIVE" "$RUN_ID" ) >> "$LOG" 2>&1 || say "WARN: archive packing failed"
sha256sum "$ARCHIVE" > "$ARCHIVE.sha256" 2>/dev/null || true
say "Archive: $ARCHIVE"
say "Done"
cat "$SUMMARY"
exit 0
