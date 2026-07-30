#!/system/bin/sh
# Bounded exact-device diagnostics for the ts-docsui debug variant.
# All working files, logs and final archives stay under shared Download storage.

MODE=${1:-full}
TARGET_USER=${TARGET_USER:-0}
CLIENT_PACKAGE=${TS_DOCSUI_CLIENT_PACKAGE:-${TS18_SAF_CLIENT_PACKAGE:-}}
TS=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo now)
OUT=/storage/emulated/0/Download/ts-docsui/diagnostics
RUN_ID=ts-docsui-${MODE}-${TS}
WORK=$OUT/.work-$RUN_ID
LOG=$WORK/collector.log
SUMMARY=$WORK/SUMMARY.txt
WARNINGS=$WORK/WARNINGS.txt
TIMEOUT_SECONDS=${TS_DOCSUI_TIMEOUT_SECONDS:-20}
MAX_FILES=${TS_DOCSUI_MAX_FILES:-2000}
ROOT_PKG=com.cbkii.tsdocsui.rootprovider
ROOT_AUTH=com.cbkii.tsdocsui.root.documents
ROOT_HELPER=/data/adb/ts-docsui/rootfs-helper.sh
MODULE_DIR=/data/adb/modules/ts-docsui
RESULT=SUCCESS
WARN_COUNT=0

mkdir -p "$WORK" 2>/dev/null || {
  echo "STOP: cannot create $WORK"
  exit 1
}
for directory in identity module packages providers storage paths permissions logs smoke; do
  mkdir -p "$WORK/$directory" 2>/dev/null || {
    echo "STOP: cannot create $WORK/$directory"
    exit 1
  }
done
: > "$WARNINGS"

say() {
  printf '[%s] %s\n' "$(date '+%H:%M:%S' 2>/dev/null || echo time)" "$*" | tee -a "$LOG" >&2
}

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  RESULT='COMPLETED WITH WARNINGS'
  printf '%s\n' "$*" >> "$WARNINGS"
  say "WARN: $*"
}

section() {
  file=$1
  title=$2
  {
    printf '\n===== %s =====\n' "$title"
    printf 'time=%s\n' "$(date '+%F %T %z' 2>/dev/null || echo unknown)"
  } >> "$file" 2>&1
}

find_timeout() {
  if [ -x /data/adb/magisk/busybox ]; then echo '/data/adb/magisk/busybox timeout'
  elif [ -x /system/bin/toybox ]; then echo '/system/bin/toybox timeout'
  elif command -v timeout >/dev/null 2>&1; then echo timeout
  elif command -v toybox >/dev/null 2>&1; then echo 'toybox timeout'
  elif command -v busybox >/dev/null 2>&1; then echo 'busybox timeout'
  else echo ''
  fi
}

TIMEOUT_CMD=$(find_timeout)

run_to() {
  seconds=$1
  file=$2
  shift 2
  {
    printf '\n$'
    printf ' %s' "$@"
    printf '\n'
  } >> "$file" 2>&1
  if [ -z "$TIMEOUT_CMD" ]; then
    printf '[skipped: timeout unavailable]\n' >> "$file"
    return 0
  fi
  # TIMEOUT_CMD intentionally contains one executable and its timeout applet.
  # shellcheck disable=SC2086
  $TIMEOUT_CMD "$seconds" "$@" >> "$file" 2>&1
  rc=$?
  printf '[exit=%s]\n' "$rc" >> "$file"
  return 0
}

run_sh_to() {
  seconds=$1
  file=$2
  shift 2
  command_text=$*
  printf "\n$ sh -c '%s'\n" "$command_text" >> "$file" 2>&1
  if [ -z "$TIMEOUT_CMD" ]; then
    printf '[skipped: timeout unavailable]\n' >> "$file"
    return 0
  fi
  # TIMEOUT_CMD intentionally contains one executable and its timeout applet.
  # shellcheck disable=SC2086
  $TIMEOUT_CMD "$seconds" sh -c "$command_text" >> "$file" 2>&1
  rc=$?
  printf '[exit=%s]\n' "$rc" >> "$file"
  return 0
}

package_uid() {
  package=$1
  uid=$(cmd package list packages -U "$package" 2>/dev/null | sed -n 's/.* uid://p' | head -n 1)
  case "$uid" in ''|*[!0-9]*)
    uid=$(pm dump "$package" 2>/dev/null | sed -n 's/.*userId=\([0-9][0-9]*\).*/\1/p' | head -n 1)
    ;;
  esac
  printf '%s' "$uid"
}

capture_package() {
  package=$1
  file=$WORK/packages/$package.txt
  section "$file" "package $package"
  run_to "$TIMEOUT_SECONDS" "$file" pm path "$package"
  run_to "$TIMEOUT_SECONDS" "$file" dumpsys package "$package"
  run_to "$TIMEOUT_SECONDS" "$file" appops get --user "$TARGET_USER" "$package"
  uid=$(package_uid "$package")
  printf 'resolved_uid=%s\n' "${uid:-unknown}" >> "$file"
  if [ -n "$uid" ]; then
    run_sh_to "$TIMEOUT_SECONDS" "$file" "magisk --sqlite 'SELECT uid,policy,until,logging,notification FROM policies WHERE uid=$uid;'"
  fi
  pm path "$package" 2>/dev/null | sed 's/^package://' | while IFS= read -r apk; do
    [ -f "$apk" ] || continue
    sha256sum "$apk" >> "$WORK/packages/APK-SHA256SUMS.txt" 2>/dev/null || printf 'hash failed: %s\n' "$apk" >> "$LOG"
  done
}

probe_uri() {
  label=$1
  uri=$2
  file=$WORK/providers/queries.txt
  printf '\n--- %s ---\nuri=%s\n' "$label" "$uri" >> "$file"
  if [ -z "$TIMEOUT_CMD" ]; then
    printf 'result=inconclusive-timeout-unavailable\n' >> "$file"
    return 0
  fi
  # shellcheck disable=SC2086
  output=$($TIMEOUT_CMD "$TIMEOUT_SECONDS" content query --uri "$uri" --user "$TARGET_USER" 2>&1)
  rc=$?
  printf 'exit=%s\n%s\n' "$rc" "$output" >> "$file"
  [ "$rc" -eq 0 ] || warn "$label provider query failed rc=$rc"
}

capture_namespace() {
  package=$1
  safe=$(printf '%s' "$package" | tr '/:' '__')
  file=$WORK/paths/process-$safe.txt
  section "$file" "process namespace $package"
  pid=$(pidof "$package" 2>/dev/null | awk '{print $1}')
  if [ -z "$pid" ]; then
    printf 'pid=absent\n' >> "$file"
    return 0
  fi
  printf 'pid=%s\n' "$pid" >> "$file"
  run_to "$TIMEOUT_SECONDS" "$file" cat "/proc/$pid/status"
  run_to "$TIMEOUT_SECONDS" "$file" cat "/proc/$pid/mountinfo"
  for path in \
    "/proc/$pid/root/storage/emulated/0" \
    "/proc/$pid/root/storage/usbdisk0" \
    "/proc/$pid/root/mnt/runtime/default/emulated/0" \
    "/proc/$pid/root/mnt/runtime/read/emulated/0" \
    "/proc/$pid/root/mnt/runtime/write/emulated/0" \
    "/proc/$pid/root/mnt/runtime/full/emulated/0"; do
    printf '\n--- %s ---\n' "$path" >> "$file"
    run_sh_to 8 "$file" "ls -ldZ '$path'; find '$path' -mindepth 1 -maxdepth 1 -print | head -n 100"
  done
}

analyse_remounts() {
  raw=$WORK/logs/remount-events.txt
  summary=$WORK/logs/remount-summary.txt
  awk '
    {
      line=$0
      lower=tolower(line)
      if (lower !~ /remountuidexternalstorage|remount.*external/) next
      second=$1 " " substr($2,1,8)
      uid="unknown"; mode="unknown"; phase="event"
      if (lower ~ /start|begin/) phase="start"
      else if (lower ~ /finish|complete| end/) phase="end"
      if (match(lower, /uid[=: (]+[0-9]+/)) { token=substr(lower,RSTART,RLENGTH); gsub(/[^0-9]/,"",token); uid=token }
      if (match(lower, /mode[=: (]+[a-z0-9_-]+/)) { token=substr(lower,RSTART,RLENGTH); sub(/^.*mode[=: (]+/,"",token); mode=token }
      count[second]++; grouped[uid "\t" mode "\t" phase]++; total++
    }
    END {
      peak=0; seconds=0
      for (s in count) { seconds++; if (count[s] > peak) peak=count[s] }
      print "remount_events=" total+0
      print "distinct_seconds=" seconds+0
      print "peak_events_per_second=" peak+0
      print "\n-- grouped uid/mode/phase --"
      for (g in grouped) print grouped[g] "\t" g
    }
  ' "$raw" > "$summary" 2>/dev/null || warn 'remount analysis failed'
}

say "Starting ts-docsui diagnostics mode=$MODE"
say "Output root: $OUT"

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

F=$WORK/module/state.txt
section "$F" module
run_to "$TIMEOUT_SECONDS" "$F" ls -la "$MODULE_DIR"
run_to "$TIMEOUT_SECONDS" "$F" find "$MODULE_DIR" -maxdepth 5 -type f -print
for file in "$MODULE_DIR/module.prop" /data/adb/ts-docsui.conf /data/adb/ts-docsui/applied-state; do
  [ -f "$file" ] || continue
  printf '\n--- %s ---\n' "$file" >> "$F"
  cat "$file" >> "$F" 2>&1
 done
run_to "$TIMEOUT_SECONDS" "$F" find "$OUT" -maxdepth 2 -type f -printf '%p %s bytes\n'

PACKAGES="com.android.documentsui com.google.android.documentsui com.android.externalstorage com.android.providers.downloads com.android.providers.media $ROOT_PKG io.github.muntashirakon.AppManager"
[ -z "$CLIENT_PACKAGE" ] || PACKAGES="$PACKAGES $CLIENT_PACKAGE"
for package in $PACKAGES; do capture_package "$package"; done

F=$WORK/providers/registry.txt
section "$F" provider_registry
run_to "$TIMEOUT_SECONDS" "$F" dumpsys package providers
run_to "$TIMEOUT_SECONDS" "$F" dumpsys activity providers
probe_uri stock-downloads content://com.android.providers.downloads.documents/root
probe_uri stock-external-roots content://com.android.externalstorage.documents/root
probe_uri stock-primary-children content://com.android.externalstorage.documents/document/primary%3A/children
probe_uri root-provider-roots content://$ROOT_AUTH/root

F=$WORK/permissions/uri-grants.txt
section "$F" uri_grants
run_to "$TIMEOUT_SECONDS" "$F" dumpsys activity permissions
run_to "$TIMEOUT_SECONDS" "$F" dumpsys package
if [ -n "$CLIENT_PACKAGE" ]; then
  run_sh_to "$TIMEOUT_SECONDS" "$F" "dumpsys package '$CLIENT_PACKAGE' | grep -i -A40 -B10 'grantedUriPermissions\|persistedUriPermissions\|uriPermission'"
fi

F=$WORK/storage/storage.txt
section "$F" storage
for command_text in \
  'sm list-volumes all' 'sm list-disks' 'sm get-primary-storage-uuid' \
  'dumpsys mount' 'dumpsys storage' 'dumpsys storaged' 'dumpsys user' \
  'mount' 'df -h' 'df -i'; do
  run_sh_to "$TIMEOUT_SECONDS" "$F" "$command_text"
done
for path in /storage/emulated/0 /storage/usbdisk0 /storage/usbdisk1 /mnt/media_rw; do
  run_sh_to 8 "$F" "printf '\n--- $path ---\n'; ls -ldZ '$path'; find '$path' -mindepth 1 -maxdepth 2 -print | head -n '$MAX_FILES'"
done

capture_namespace com.android.documentsui
capture_namespace com.android.externalstorage
capture_namespace "$ROOT_PKG"
[ -z "$CLIENT_PACKAGE" ] || capture_namespace "$CLIENT_PACKAGE"

F=$WORK/logs/logcat-filtered.txt
section "$F" filtered_logs
run_sh_to 45 "$F" "logcat -d -v threadtime -t 20000 | grep -Ei 'DocumentsUI|ExternalStorageProvider|com\.android\.externalstorage|com\.cbkii\.tsdocsui|remountUidExternalStorage|StorageManagerService|AppOpsService|SecurityException|FATAL EXCEPTION|ANR'"
grep -Ei 'remountUidExternalStorage|remount.*external' "$F" > "$WORK/logs/remount-events.txt" 2>/dev/null || :
analyse_remounts

F=$WORK/smoke/root-helper.txt
section "$F" root_helper_smoke
if [ -x "$ROOT_HELPER" ] && [ -x /data/adb/magisk/busybox ]; then
  for action_path in '/storage/emulated/0' '/'; do
    encoded=$(printf '%s' "$action_path" | /data/adb/magisk/busybox base64 2>/dev/null | /data/adb/magisk/busybox tr -d '\r\n')
    run_sh_to "$TIMEOUT_SECONDS" "$F" "'$ROOT_HELPER' stat '$encoded'"
  done
else
  printf 'root helper unavailable\n' >> "$F"
fi

{
  printf 'ts-docsui diagnostic summary\n'
  printf 'result=%s\n' "$RESULT"
  printf 'warnings=%s\n' "$WARN_COUNT"
  printf 'run=%s\n' "$RUN_ID"
  printf 'mode=%s\n' "$MODE"
  printf 'build=%s\n' "$(getprop ro.build.display.id 2>/dev/null)"
  printf 'sdk=%s\n' "$(getprop ro.build.version.sdk 2>/dev/null)"
  printf 'client_package=%s\n' "${CLIENT_PACKAGE:-not-specified}"
  printf 'output_root=%s\n' "$OUT"
} > "$SUMMARY"

ARCHIVE=$OUT/$RUN_ID.tar.gz
CHECKSUM=$ARCHIVE.sha256
say "Creating verified archive: $ARCHIVE"
if tar -czf "$ARCHIVE" -C "$OUT" ".work-$RUN_ID" >/dev/null 2>&1 && \
   tar -tzf "$ARCHIVE" >/dev/null 2>&1 && \
   sha256sum "$ARCHIVE" > "$CHECKSUM" 2>/dev/null; then
  rm -rf "$WORK" 2>/dev/null || warn "could not remove completed work directory: $WORK"
  printf 'RESULT: %s\n' "$RESULT"
  printf 'Archive: %s\n' "$ARCHIVE"
  printf 'Checksum: %s\n' "$CHECKSUM"
  exit 0
fi

printf 'FAILED: archive could not be verified; evidence remains at %s\n' "$WORK" >&2
exit 1
