#!/system/bin/sh
# Shared bounded collection helpers. Source from ts18-saf-evidence-v2.sh only.

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
  if [ -x /data/adb/magisk/busybox ]; then
    printf '%s\n' '/data/adb/magisk/busybox timeout'
  elif [ -x /system/bin/toybox ]; then
    printf '%s\n' '/system/bin/toybox timeout'
  elif command -v timeout >/dev/null 2>&1; then
    printf '%s\n' timeout
  elif command -v toybox >/dev/null 2>&1; then
    printf '%s\n' 'toybox timeout'
  elif command -v busybox >/dev/null 2>&1; then
    printf '%s\n' 'busybox timeout'
  else
    printf '%s\n' ''
  fi
}

TIMEOUT_CMD=$(find_timeout)

bounded_capture() {
  seconds=$1
  shift
  command_text=$*
  [ -n "$TIMEOUT_CMD" ] || return 125
  # TIMEOUT_CMD intentionally contains one executable and its timeout applet.
  # shellcheck disable=SC2086
  $TIMEOUT_CMD "$seconds" sh -c "$command_text"
}

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

copy_file_limited() {
  source=$1
  destination=$2
  [ -f "$source" ] || return 0
  size=$(wc -c < "$source" 2>/dev/null || echo 0)
  case "$size" in ''|*[!0-9]*) size=0 ;; esac
  if [ "$MAX_COPY_BYTES" -gt 0 ] && [ "$size" -gt "$MAX_COPY_BYTES" ]; then
    printf 'SKIP size=%s path=%s\n' "$size" "$source" >> "$WORK/files/SKIPPED-LARGE-FILES.txt"
    return 0
  fi
  parent=$(dirname "$destination")
  if ! mkdir -p -- "$parent" 2>/dev/null; then
    printf 'copy parent creation failed: %s\n' "$parent" >> "$LOG"
    return 0
  fi
  if ! cp -a -- "$source" "$destination" >> "$LOG" 2>&1; then
    printf 'copy failed: %s\n' "$source" >> "$LOG"
  fi
}

copy_tree_limited() {
  source=$1
  destination=$2
  depth=${3:-3}
  [ -d "$source" ] || return 0
  list=$WORK/files/.copy-list.$$
  if [ -n "$TIMEOUT_CMD" ]; then
    # TIMEOUT_CMD intentionally contains one executable and its timeout applet.
    # shellcheck disable=SC2086
    if ! $TIMEOUT_CMD 20 find "$source" -maxdepth "$depth" -type f -print > "$list" 2>/dev/null; then
      warn "bounded tree inventory incomplete: $source"
    fi
  else
    printf 'SKIP timeout unavailable for tree copy: %s\n' "$source" >> "$LOG"
    return 0
  fi
  count=0
  while IFS= read -r file; do
    count=$((count + 1))
    if [ "$count" -gt 2000 ]; then
      printf 'SKIP tree item limit reached: %s\n' "$source" >> "$LOG"
      break
    fi
    relative=${file#$source/}
    copy_file_limited "$file" "$destination/$relative"
  done < "$list"
  if ! rm -f -- "$list" 2>/dev/null; then
    warn "temporary tree inventory could not be removed: $list"
  fi
}

package_uid() {
  package=$1
  output=$(bounded_capture 8 "cmd package list packages -U '$package'" 2>/dev/null)
  uid=$(printf '%s\n' "$output" | sed -n 's/.* uid://p' | head -n 1)
  case "$uid" in ''|*[!0-9]*)
    output=$(bounded_capture 8 "pm dump '$package'" 2>/dev/null)
    uid=$(printf '%s\n' "$output" | sed -n 's/.*userId=\([0-9][0-9]*\).*/\1/p' | head -n 1)
    ;;
  esac
  printf '%s' "$uid"
}

package_state() {
  package=$1
  enabled=$(bounded_capture 8 "pm list packages -e --user '$TARGET_USER' '$package'" 2>/dev/null)
  if printf '%s\n' "$enabled" | grep -Fxq "package:$package"; then
    printf '%s' enabled
    return 0
  fi
  disabled=$(bounded_capture 8 "pm list packages -d --user '$TARGET_USER' '$package'" 2>/dev/null)
  if printf '%s\n' "$disabled" | grep -Fxq "package:$package"; then
    printf '%s' disabled
  else
    printf '%s' absent-for-user
  fi
}

copy_pkg_apks() {
  package=$1
  destination=$WORK/apks/$package
  if ! mkdir -p -- "$destination" 2>/dev/null; then
    printf 'APK destination unavailable: %s\n' "$destination" >> "$LOG"
    return 0
  fi
  paths=$(bounded_capture 8 "pm path '$package'" 2>/dev/null)
  printf '%s\n' "$paths" | sed 's/^package://' | while IFS= read -r apk; do
    [ -f "$apk" ] || continue
    copy_file_limited "$apk" "$destination/$(basename "$apk")"
    if ! sha256sum "$apk" >> "$WORK/apks/SHA256SUMS.txt" 2>/dev/null; then
      printf 'APK hash failed: %s\n' "$apk" >> "$LOG"
    fi
  done
}

package_snapshot_line() {
  package=$1
  uid=$(package_uid "$package")
  state=$(package_state "$package")
  paths=$(bounded_capture 8 "pm path '$package'" 2>/dev/null | sed 's/^package://' | tr '\n' ';' | sed 's/;$//')
  dump=$(bounded_capture 12 "dumpsys package '$package'" 2>/dev/null)
  version=$(printf '%s\n' "$dump" | sed -n 's/.*versionName=//p' | head -n 1 | tr '\t\r\n' ' ')
  code=$(printf '%s\n' "$dump" | sed -n 's/.*versionCode=\([0-9][0-9]*\).*/\1/p' | head -n 1)
  flags=$(printf '%s\n' "$dump" | sed -n 's/.*pkgFlags=\[\(.*\)\].*/\1/p' | head -n 1 | tr '\t\r\n' ' ')
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$package" "${uid:-unknown}" "$state" "${code:-unknown}" "${version:-unknown}" "${flags:-unknown}" "${paths:-none}"
}

content_query() {
  file=$1
  uri=$2
  printf '\n--- %s user=%s ---\n' "$uri" "$TARGET_USER" >> "$file"
  run_sh_to "$TIMEOUT_SECONDS" "$file" "content query --uri '$uri' --user '$TARGET_USER'"
}

probe_content_uri() {
  label=$1
  uri=$2
  file=$3
  if [ -z "$TIMEOUT_CMD" ]; then
    printf '%s=skipped-timeout-unavailable\n' "$label" >> "$file"
    printf '%s' inconclusive
    return 0
  fi
  # TIMEOUT_CMD intentionally contains one executable and its timeout applet.
  # shellcheck disable=SC2086
  output=$($TIMEOUT_CMD "$TIMEOUT_SECONDS" content query --uri "$uri" --user "$TARGET_USER" 2>&1)
  rc=$?
  {
    printf '\n--- health probe %s ---\n' "$label"
    printf 'uri=%s\n' "$uri"
    printf 'exit=%s\n' "$rc"
    printf '%s\n' "$output"
  } >> "$file"
  if [ "$rc" -eq 0 ]; then
    printf '%s' passed
  else
    printf '%s' failed
  fi
}

safe_root_helper() {
  file=$1
  action=$2
  shift 2
  [ -x "$ROOT_HELPER" ] || { printf 'root helper missing: %s\n' "$ROOT_HELPER" >> "$file"; return 0; }
  [ -x /data/adb/magisk/busybox ] || { printf 'Magisk BusyBox missing\n' >> "$file"; return 0; }
  encoded=
  for value in "$@"; do
    arg=$(printf '%s' "$value" | /data/adb/magisk/busybox base64 2>/dev/null | /data/adb/magisk/busybox tr -d '\r\n')
    encoded="$encoded '$arg'"
  done
  run_sh_to "$TIMEOUT_SECONDS" "$file" "'$ROOT_HELPER' '$action' $encoded"
}

resolve_pid() {
  package=$1
  pid=$(bounded_capture 5 "pidof '$package'" 2>/dev/null | awk '{print $1}')
  if [ -z "$pid" ]; then
    pid=$(bounded_capture 5 "ps -A" 2>/dev/null | awk -v name="$package" '$NF == name {print $2; exit}')
  fi
  printf '%s' "$pid"
}

capture_process_namespace() {
  package=$1
  safe_name=$(printf '%s' "$package" | tr '/:' '__')
  file=$WORK/paths/process-$safe_name.txt
  section "$file" "process namespace $package"
  pid=$(resolve_pid "$package")
  if [ -z "$pid" ]; then
    printf 'pid=absent\n' >> "$file"
    return 0
  fi
  printf 'pid=%s\n' "$pid" >> "$file"
  copy_file_limited "/proc/$pid/status" "$WORK/paths/process-$safe_name-status.txt"
  copy_file_limited "/proc/$pid/mountinfo" "$WORK/paths/process-$safe_name-mountinfo.txt"
  for path in \
    "/proc/$pid/root/storage" \
    "/proc/$pid/root/storage/emulated" \
    "/proc/$pid/root/storage/emulated/0" \
    "/proc/$pid/root/storage/usbdisk0" \
    "/proc/$pid/root/mnt/runtime/default/emulated/0" \
    "/proc/$pid/root/mnt/runtime/read/emulated/0" \
    "/proc/$pid/root/mnt/runtime/write/emulated/0" \
    "/proc/$pid/root/mnt/runtime/full/emulated/0"; do
    printf '\n--- %s ---\n' "$path" >> "$file"
    if ! ls -ldZ "$path" >> "$file" 2>&1; then
      ls -ld "$path" >> "$file" 2>&1 || printf 'path unavailable: %s\n' "$path" >> "$file"
    fi
    if ! readlink -f "$path" >> "$file" 2>&1; then
      printf 'canonical path unavailable: %s\n' "$path" >> "$file"
    fi
    run_sh_to 8 "$file" "find '$path' -mindepth 1 -maxdepth 1 -print | head -n 200"
  done
}
