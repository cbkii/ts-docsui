#!/system/bin/sh
# TS18 Full File Picker late-start service.
# Restores a working DocumentsUI resolver, exposes stock internal storage, and prepares
# the optional Magisk-backed provider without allowing root discovery to block picker launch.

MODDIR=${0%/*}
STATE_DIR=/data/adb/ts18-documentsui-saf
CFG=/data/adb/ts18-documentsui-saf.conf
LOGDIR=$STATE_DIR/logs
LOG=$LOGDIR/service-v130.log
HELPER_SRC=$MODDIR/tools/rootfs-helper.sh
HELPER_DST=$STATE_DIR/rootfs-helper.sh
ROOT_PKG=com.cbkii.tsdocsui.rootprovider
ROOT_COMPONENT=$ROOT_PKG/.RootDocumentsProvider
ROOT_AUTH=com.cbkii.tsdocsui.root.documents
STALE_PROVIDER_PKG=com.ts18.safprovider
APP_MANAGER_PKG=io.github.muntashirakon.AppManager
MIGRATION_DIR=$STATE_DIR/migrations
GENERATED_DIR=$STATE_DIR/generated
MUTATION_COUNT=0
NOOP_COUNT=0

CONFIG_SCHEMA=2
TARGET_USER=0
BOOT_WAIT_ATTEMPTS=45
BOOT_WAIT_SECONDS=2
FIX_ENABLE_AOSP_DOCUMENTSUI=1
FIX_ENABLE_DOCUMENTSUI_COMPONENTS=1
FIX_REPAIR_DOCUMENTSUI_DATA_OWNER=1
FIX_DISABLE_GOOGLE_DOCUMENTSUI=1
FIX_DISABLE_STALE_TS18_PROVIDER=1
FIX_UNINSTALL_STALE_TS18_PROVIDER_FOR_USER=1
FIX_CLEAR_STALE_TS18_PROVIDER_DATA=1
FIX_DISABLE_APP_MANAGER_PICKER_INTERCEPTOR=1
FIX_CLEAR_PICKER_PREFERRED_ACTIVITIES=1
FIX_VERIFY_PICKER_RESOLVER=1
FIX_ENABLE_EXTERNAL_STORAGE_PROVIDER=1
FIX_DISABLE_EXTERNAL_STORAGE_TEST_PROVIDER=1
EXTERNAL_ROOT_MODE=show
FIX_ENABLE_ROOT_FILE_PROVIDER=1
FIX_AUTO_GRANT_ROOT_PROVIDER=1
ROOT_PROVIDER_SHOW_INTERNAL=1
ROOT_PROVIDER_SHOW_DEVICE=1
ROOT_PROVIDER_SHOW_USB=1
ROOT_PROVIDER_ALLOW_CREATE=1
ROOT_PROVIDER_ALLOW_WRITE=1
ROOT_PROVIDER_ALLOW_RENAME=1
ROOT_PROVIDER_ALLOW_DELETE=1
ROOT_PROVIDER_STAGE_DIR=/storage/emulated/0/.TS18-Root-Provider
ROOT_PROVIDER_STAGE_LIMIT_BYTES=268435456
FIX_ENABLE_MIXPLORER_PROVIDER=0
FIX_GRANT_MIXPLORER_STORAGE_PERMS=0
FIX_GRANT_STORAGE_ACCESS=1
FIX_CREATE_STANDARD_INTERNAL_DIRS=1
FIX_REFRESH_PICKER_ON_CHANGE=1
FIX_WARM_UP_PROVIDERS=1
DIAG_AUTO_RUN_ON_BOOT=0
DIAG_OUTPUT_ROOT=/storage/emulated/0/Download/TS18-SAF-Diagnostics
DIAG_COPY_RELEVANT_APKS=1
DIAG_COPY_ALL_APKS=0
DIAG_MAX_COPY_BYTES=52428800

mkdir -p "$LOGDIR" "$MIGRATION_DIR" "$GENERATED_DIR" 2>/dev/null || exit 0
if [ -f "$LOG" ]; then
  size=$(wc -c < "$LOG" 2>/dev/null || echo 0)
  case "$size" in ''|*[!0-9]*) size=0 ;; esac
  if [ "$size" -gt 524288 ]; then
    # Best-effort history only; failure is safe because the current log remains usable.
    mv -f "$LOG" "$LOG.previous" 2>/dev/null || true
  fi
fi

log() {
  echo "[$(date '+%F %T' 2>/dev/null || echo time)] $*" >> "$LOG"
}

is_on() {
  case "$1" in 1|true|TRUE|yes|YES|on|ON|enabled|ENABLED) return 0 ;; *) return 1 ;; esac
}

is_allowed_key() {
  case "$1" in
    CONFIG_SCHEMA|TARGET_USER|BOOT_WAIT_ATTEMPTS|BOOT_WAIT_SECONDS|FIX_ENABLE_AOSP_DOCUMENTSUI|FIX_ENABLE_DOCUMENTSUI_COMPONENTS|FIX_REPAIR_DOCUMENTSUI_DATA_OWNER|FIX_DISABLE_GOOGLE_DOCUMENTSUI|FIX_DISABLE_STALE_TS18_PROVIDER|FIX_UNINSTALL_STALE_TS18_PROVIDER_FOR_USER|FIX_CLEAR_STALE_TS18_PROVIDER_DATA|FIX_DISABLE_APP_MANAGER_PICKER_INTERCEPTOR|FIX_CLEAR_PICKER_PREFERRED_ACTIVITIES|FIX_VERIFY_PICKER_RESOLVER|FIX_ENABLE_EXTERNAL_STORAGE_PROVIDER|FIX_DISABLE_EXTERNAL_STORAGE_TEST_PROVIDER|EXTERNAL_ROOT_MODE|FIX_ENABLE_ROOT_FILE_PROVIDER|FIX_AUTO_GRANT_ROOT_PROVIDER|ROOT_PROVIDER_SHOW_INTERNAL|ROOT_PROVIDER_SHOW_DEVICE|ROOT_PROVIDER_SHOW_USB|ROOT_PROVIDER_ALLOW_CREATE|ROOT_PROVIDER_ALLOW_WRITE|ROOT_PROVIDER_ALLOW_RENAME|ROOT_PROVIDER_ALLOW_DELETE|ROOT_PROVIDER_STAGE_DIR|ROOT_PROVIDER_STAGE_LIMIT_BYTES|FIX_ENABLE_MIXPLORER_PROVIDER|FIX_GRANT_MIXPLORER_STORAGE_PERMS|FIX_GRANT_STORAGE_ACCESS|FIX_CREATE_STANDARD_INTERNAL_DIRS|FIX_REFRESH_PICKER_ON_CHANGE|FIX_WARM_UP_PROVIDERS|DIAG_AUTO_RUN_ON_BOOT|DIAG_OUTPUT_ROOT|DIAG_COPY_RELEVANT_APKS|DIAG_COPY_ALL_APKS|DIAG_MAX_COPY_BYTES) return 0 ;;
    *) return 1 ;;
  esac
}

valid_value() {
  case "$1" in ''|*[!A-Za-z0-9_./:-]*) return 1 ;; *) return 0 ;; esac
}

load_config() {
  if [ ! -f "$CFG" ] && [ -f "$MODDIR/config.default" ]; then
    if cp -f "$MODDIR/config.default" "$CFG" 2>/dev/null; then
      if ! chmod 0644 "$CFG" 2>/dev/null; then
        log "WARN: runtime config created but chmod 0644 was rejected"
      fi
      log "created runtime config from module defaults"
    else
      log "WARN: could not create runtime config"
    fi
  fi
  [ -f "$CFG" ] || return 0
  while IFS='=' read -r key value || [ -n "$key" ]; do
    case "$key" in ''|'#'*) continue ;; esac
    is_allowed_key "$key" || continue
    valid_value "$value" || continue
    eval "$key=\$value"
  done < "$CFG"
}

pkg_exists() {
  pm path "$1" >/dev/null 2>&1
}

pkg_uid() {
  package=$1
  uid=$(cmd package list packages -U "$package" 2>/dev/null | sed -n 's/.* uid://p' | head -n 1)
  case "$uid" in ''|*[!0-9]*)
    uid=$(pm dump "$package" 2>/dev/null | sed -n 's/.*userId=\([0-9][0-9]*\).*/\1/p' | head -n 1)
    ;;
  esac
  printf '%s' "$uid"
}

record_mutation() {
  MUTATION_COUNT=$((MUTATION_COUNT + 1))
  log "MUTATION: $*"
}

record_noop() {
  NOOP_COUNT=$((NOOP_COUNT + 1))
  log "NO-OP: $*"
}

pkg_installed_for_user() {
  pm list packages --user "$TARGET_USER" "$1" 2>/dev/null | grep -Fxq "package:$1"
}

pkg_enabled_for_user() {
  pm list packages -e --user "$TARGET_USER" "$1" 2>/dev/null | grep -Fxq "package:$1"
}

pkg_disabled_for_user() {
  pm list packages -d --user "$TARGET_USER" "$1" 2>/dev/null | grep -Fxq "package:$1"
}

component_override_state() {
  component=$1
  output=$(cmd package get-component-enabled-setting --user "$TARGET_USER" "$component" 2>/dev/null)
  rc=$?
  [ "$rc" -eq 0 ] || { echo unknown; return; }
  case "$output" in
    *COMPONENT_ENABLED_STATE_ENABLED*|enabled) echo enabled ;;
    *COMPONENT_ENABLED_STATE_DISABLED*|*COMPONENT_ENABLED_STATE_DISABLED_USER*|disabled|disabled-user) echo disabled ;;
    *COMPONENT_ENABLED_STATE_DEFAULT*|default) echo default ;;
    *) echo unknown ;;
  esac
}

permission_granted() {
  pm dump "$1" 2>/dev/null | grep -F "$2: granted=true" >/dev/null 2>&1
}

appop_allowed() {
  appops get --user "$TARGET_USER" "$1" "$2" 2>/dev/null | grep -Eq '(^|[[:space:]])allow([[:space:]]|;|$)'
}

run_migration_once() {
  migration=$1
  shift
  marker=$MIGRATION_DIR/$migration
  if [ -f "$marker" ]; then
    record_noop "migration already applied: $migration"
    return 0
  fi
  if "$@"; then
    if : > "$marker" 2>/dev/null; then
      record_mutation "migration applied: $migration"
      return 0
    fi
    log "WARN: migration completed but marker write failed: $migration"
    return 1
  fi
  log "WARN: migration failed and will be retried: $migration"
  return 1
}

ensure_path_owner() {
  path=$1
  uid=$2
  [ -e "$path" ] || return 0
  owner=$(stat -c '%u:%g' "$path" 2>/dev/null)
  if [ "$owner" = "$uid:$uid" ]; then
    record_noop "owner already correct: $path"
    return 0
  fi
  if chown "$uid:$uid" "$path" >> "$LOG" 2>&1; then
    record_mutation "owner repaired: $path uid=$uid"
    return 0
  fi
  log "WARN: owner repair failed: $path uid=$uid"
  return 1
}

install_if_changed() {
  generated=$1
  target=$2
  uid=$3
  mode=$4
  label=$5
  if [ -f "$target" ] && cmp -s "$generated" "$target"; then
    rm -f "$generated"
    record_noop "$label content already current"
    ensure_path_owner "$target" "$uid" || return 1
    current_mode=$(stat -c '%a' "$target" 2>/dev/null)
    if [ "$current_mode" != "$mode" ]; then
      chmod "$mode" "$target" >> "$LOG" 2>&1 || return 1
      record_mutation "$label mode repaired"
    fi
    return 0
  fi
  cp -f "$generated" "$target" >> "$LOG" 2>&1 || return 1
  rm -f "$generated"
  chown "$uid:$uid" "$target" >> "$LOG" 2>&1 || return 1
  chmod "$mode" "$target" >> "$LOG" 2>&1 || return 1
  restorecon "$target" >> "$LOG" 2>&1 || log "WARN: restorecon failed: $target"
  record_mutation "$label content applied"
}

enable_pkg() {
  package=$1
  pkg_exists "$package" || { log "ERROR: package absent: $package"; return 1; }
  if pkg_enabled_for_user "$package"; then
    record_noop "package already enabled: $package"
    return 0
  fi
  if ! pkg_installed_for_user "$package"; then
    output=$(pm install-existing --user "$TARGET_USER" "$package" 2>&1)
    rc=$?
    echo "$output" >> "$LOG"
    [ "$rc" -eq 0 ] || { log "ERROR: install-existing failed: $package rc=$rc"; return "$rc"; }
    record_mutation "installed existing package for user: $package"
  fi
  output=$(pm enable --user "$TARGET_USER" "$package" 2>&1)
  rc=$?
  echo "$output" >> "$LOG"
  if [ "$rc" -eq 0 ]; then
    record_mutation "enabled package: $package"
    return 0
  fi
  log "ERROR: failed to enable package: $package rc=$rc"
  return "$rc"
}

disable_pkg() {
  package=$1
  pkg_exists "$package" || { record_noop "package absent for disable: $package"; return 0; }
  if pkg_disabled_for_user "$package"; then
    record_noop "package already disabled: $package"
    return 0
  fi
  output=$(pm disable-user --user "$TARGET_USER" "$package" 2>&1)
  rc=$?
  echo "$output" >> "$LOG"
  if [ "$rc" -eq 0 ]; then
    record_mutation "disabled package: $package"
    return 0
  fi
  log "WARN: failed to disable package: $package rc=$rc"
  return "$rc"
}

enable_component() {
  component=$1
  package=${component%%/*}
  pkg_exists "$package" || { log "ERROR: component package absent: $component"; return 1; }
  state=$(component_override_state "$component")
  if [ "$state" = enabled ]; then
    record_noop "component already enabled: $component"
    return 0
  fi
  output=$(pm enable --user "$TARGET_USER" "$component" 2>&1)
  rc=$?
  echo "$output" >> "$LOG"
  if [ "$rc" -eq 0 ]; then
    record_mutation "enabled component: $component previous=$state"
    return 0
  fi
  log "ERROR: failed to enable component: $component rc=$rc"
  return "$rc"
}

disable_component() {
  component=$1
  package=${component%%/*}
  pkg_exists "$package" || { record_noop "component package absent for disable: $component"; return 0; }
  state=$(component_override_state "$component")
  if [ "$state" = disabled ]; then
    record_noop "component already disabled: $component"
    return 0
  fi
  output=$(pm disable-user --user "$TARGET_USER" "$component" 2>&1)
  rc=$?
  echo "$output" >> "$LOG"
  if [ "$rc" -ne 0 ]; then
    output=$(pm disable --user "$TARGET_USER" "$component" 2>&1)
    rc=$?
    echo "$output" >> "$LOG"
  fi
  if [ "$rc" -eq 0 ]; then
    record_mutation "disabled component: $component previous=$state"
    return 0
  fi
  log "WARN: failed to disable component: $component rc=$rc"
  return "$rc"
}

grant_if_requested() {
  package=$1
  permission=$2
  pkg_exists "$package" || return 0
  if ! pm dump "$package" 2>/dev/null | grep -Fq "$permission"; then
    record_noop "permission not requested: $package $permission"
    return 0
  fi
  if permission_granted "$package" "$permission"; then
    record_noop "permission already granted: $package $permission"
    return 0
  fi
  output=$(pm grant --user "$TARGET_USER" "$package" "$permission" 2>&1)
  rc=$?
  echo "$output" >> "$LOG"
  [ "$rc" -eq 0 ] &&
    record_mutation "granted permission: $package $permission" ||
    log "WARN: permission grant failed: $package $permission rc=$rc"
}

set_appop() {
  package=$1
  operation=$2
  pkg_exists "$package" || return 0
  if appop_allowed "$package" "$operation"; then
    record_noop "app-op already allowed: $package $operation"
    return 0
  fi
  output=$(appops set --user "$TARGET_USER" "$package" "$operation" allow 2>&1)
  rc=$?
  echo "$output" >> "$LOG"
  [ "$rc" -eq 0 ] &&
    record_mutation "set app-op: $package $operation" ||
    log "WARN: app-op failed: $package $operation rc=$rc"
}

find_timeout() {
  if [ -x /data/adb/magisk/busybox ]; then
    echo "/data/adb/magisk/busybox timeout"
  elif [ -x /system/bin/toybox ]; then
    echo "/system/bin/toybox timeout"
  elif command -v timeout >/dev/null 2>&1; then
    echo timeout
  elif command -v toybox >/dev/null 2>&1; then
    echo "toybox timeout"
  elif command -v busybox >/dev/null 2>&1; then
    echo "busybox timeout"
  else
    echo ""
  fi
}

TIMEOUT_CMD=$(find_timeout)
BOUNDED_COMMAND_SKIPPED=125
run_bounded_sh() {
  seconds=$1
  shift
  command_text=$*
  if [ -z "$TIMEOUT_CMD" ]; then
    log "WARN: bounded command skipped because no timeout implementation exists: $command_text"
    return "$BOUNDED_COMMAND_SKIPPED"
  fi
  # TIMEOUT_CMD intentionally contains one executable and its timeout applet name.
  # shellcheck disable=SC2086
  $TIMEOUT_CMD "$seconds" sh -c "$command_text"
}

bool_xml() {
  if is_on "$1"; then echo true; else echo false; fi
}

repair_package_data_owner() {
  package=$1
  uid=$(pkg_uid "$package")
  case "$uid" in ''|*[!0-9]*) log "ERROR: UID unavailable for ownership repair: $package"; return 1 ;; esac
  checked=0
  repaired=0
  for base in "/data/user/$TARGET_USER/$package" "/data/data/$package" "/data/user_de/$TARGET_USER/$package"; do
    [ -e "$base" ] || continue
    checked=$((checked + 1))
    mismatch=$(find "$base" -xdev \( ! -user "$uid" -o ! -group "$uid" \) -print -quit 2>/dev/null)
    if [ -z "$mismatch" ]; then
      record_noop "package data ownership already correct: $base"
      continue
    fi
    if chown -R "$uid:$uid" "$base" >> "$LOG" 2>&1; then
      repaired=$((repaired + 1))
      record_mutation "package data ownership repaired: $base uid=$uid first_mismatch=$mismatch"
    else
      log "WARN: owner repair failed: $base uid=$uid"
      continue
    fi
    restorecon -RF "$base" >> "$LOG" 2>&1 ||
      log "WARN: restorecon failed after owner repair: $base"
  done
  log "package data ownership reconciled: $package uid=$uid checked=$checked repaired=$repaired"
  return 0
}

cleanup_stale_provider() {
  pkg_exists "$STALE_PROVIDER_PKG" || { log "stale provider absent: $STALE_PROVIDER_PKG"; return 0; }
  if ! disable_component "$STALE_PROVIDER_PKG/.TS18DocumentsProvider"; then
    log "WARN: stale provider component could not be disabled; package-level disable will still be attempted"
  fi
  if ! disable_pkg "$STALE_PROVIDER_PKG"; then
    log "WARN: stale provider package could not be disabled; per-user uninstall will still be attempted"
  fi
  if is_on "$FIX_UNINSTALL_STALE_TS18_PROVIDER_FOR_USER"; then
    output=$(pm uninstall --user "$TARGET_USER" "$STALE_PROVIDER_PKG" 2>&1)
    rc=$?
    echo "$output" >> "$LOG"
    [ "$rc" -eq 0 ] && log "uninstalled stale provider for user $TARGET_USER" || log "stale provider uninstall not applied rc=$rc"
  fi
  if is_on "$FIX_CLEAR_STALE_TS18_PROVIDER_DATA"; then
    output=$(pm clear --user "$TARGET_USER" "$STALE_PROVIDER_PKG" 2>&1)
    rc=$?
    echo "$output" >> "$LOG"
    [ "$rc" -eq 0 ] && log "cleared stale provider data" || log "stale provider data clear not applied rc=$rc"
  fi
}

clear_picker_preferred_activities() {
  package=$1
  pkg_exists "$package" || { record_noop "preferred-activity package absent: $package"; return 0; }
  output=$(cmd package clear-package-preferred-activities "$package" 2>&1)
  rc=$?
  echo "$output" >> "$LOG"
  if [ "$rc" -ne 0 ]; then
    output=$(pm clear-package-preferred-activities "$package" 2>&1)
    rc=$?
    echo "$output" >> "$LOG"
  fi
  [ "$rc" -eq 0 ] &&
    record_mutation "cleared preferred activities: $package" ||
    log "WARN: could not clear preferred activities: $package rc=$rc"
}

cleanup_picker_preferred_migration() {
  clear_picker_preferred_activities "$APP_MANAGER_PKG"
  clear_picker_preferred_activities com.google.android.documentsui
}

prepare_stage_dir() {
  case "$ROOT_PROVIDER_STAGE_DIR" in
    /storage/emulated/0/*) ;;
    *)
      log "invalid root provider staging path; using shared-storage default"
      ROOT_PROVIDER_STAGE_DIR=/storage/emulated/0/.TS18-Root-Provider
      ;;
  esac
  if [ ! -d "$ROOT_PROVIDER_STAGE_DIR" ]; then
    mkdir -p "$ROOT_PROVIDER_STAGE_DIR" >> "$LOG" 2>&1 || return 1
    record_mutation "created root provider staging directory: $ROOT_PROVIDER_STAGE_DIR"
  else
    record_noop "root provider staging directory already exists"
  fi
  stage_mode=$(stat -c '%a' "$ROOT_PROVIDER_STAGE_DIR" 2>/dev/null)
  if [ "$stage_mode" != 777 ]; then
    if chmod 0777 "$ROOT_PROVIDER_STAGE_DIR" >> "$LOG" 2>&1; then
      record_mutation "root provider staging mode repaired: previous=$stage_mode"
    else
      log "WARN: staging chmod was rejected; shared-storage mediation may still provide access"
    fi
  else
    record_noop "root provider staging mode already current"
  fi
  deleted=$(find "$ROOT_PROVIDER_STAGE_DIR" -maxdepth 1 -type f -name 'root-*.stage' -mmin +60 -print -delete 2>> "$LOG")
  if [ -n "$deleted" ]; then
    record_mutation "removed stale staging files: $deleted"
  else
    record_noop "no stale staging files"
  fi
  log "root provider staging directory ready: $ROOT_PROVIDER_STAGE_DIR"
}

write_root_provider_prefs() {
  uid=$(pkg_uid "$ROOT_PKG")
  case "$uid" in ''|*[!0-9]*) log "ERROR: root provider UID unavailable"; return 1 ;; esac
  base=/data/user/$TARGET_USER/$ROOT_PKG
  prefs_dir=$base/shared_prefs
  prefs_file=$prefs_dir/provider.xml
  generated=$GENERATED_DIR/root-provider.xml
  mkdir -p "$prefs_dir" 2>/dev/null || { log "ERROR: cannot create root provider prefs"; return 1; }
  ensure_path_owner "$base" "$uid" || return 1
  ensure_path_owner "$prefs_dir" "$uid" || return 1
  cat > "$generated" <<EOPREF
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name="showInternal" value="$(bool_xml "$ROOT_PROVIDER_SHOW_INTERNAL")" />
    <boolean name="showDevice" value="$(bool_xml "$ROOT_PROVIDER_SHOW_DEVICE")" />
    <boolean name="showUsb" value="$(bool_xml "$ROOT_PROVIDER_SHOW_USB")" />
    <boolean name="allowCreate" value="$(bool_xml "$ROOT_PROVIDER_ALLOW_CREATE")" />
    <boolean name="allowWrite" value="$(bool_xml "$ROOT_PROVIDER_ALLOW_WRITE")" />
    <boolean name="allowRename" value="$(bool_xml "$ROOT_PROVIDER_ALLOW_RENAME")" />
    <boolean name="allowDelete" value="$(bool_xml "$ROOT_PROVIDER_ALLOW_DELETE")" />
    <string name="stageDir">$ROOT_PROVIDER_STAGE_DIR</string>
    <long name="stageLimitBytes" value="$ROOT_PROVIDER_STAGE_LIMIT_BYTES" />
</map>
EOPREF
  install_if_changed "$generated" "$prefs_file" "$uid" 600 "root-provider preferences"
}

find_magisk_bin() {
  if command -v magisk >/dev/null 2>&1; then
    command -v magisk
  elif [ -x /data/adb/magisk/magisk ]; then
    echo /data/adb/magisk/magisk
  elif [ -x /sbin/magisk ]; then
    echo /sbin/magisk
  else
    echo ""
  fi
}

auto_grant_root() {
  is_on "$FIX_AUTO_GRANT_ROOT_PROVIDER" || return 0
  uid=$(pkg_uid "$ROOT_PKG")
  case "$uid" in ''|*[!0-9]*) log "WARN: cannot auto-grant root: UID unavailable"; return 1 ;; esac
  magisk_bin=$(find_magisk_bin)
  [ -n "$magisk_bin" ] || { log "WARN: cannot auto-grant root: magisk command missing"; return 1; }
  current=$("$magisk_bin" --sqlite "SELECT policy FROM policies WHERE uid=$uid;" 2>/dev/null)
  if echo "$current" | grep -Eq 'policy[^0-9]*2|(^|[|[:space:]])2([|[:space:]]|$)'; then
    record_noop "Magisk root policy already granted: $ROOT_PKG uid=$uid"
    return 0
  fi
  sql="REPLACE INTO policies (uid, policy, until, logging, notification) VALUES ($uid, 2, 0, 1, 0);"
  if "$magisk_bin" --sqlite "$sql" >> "$LOG" 2>&1; then
    record_mutation "Magisk root policy granted: $ROOT_PKG uid=$uid"
    return 0
  fi
  log "WARN: Magisk root policy grant failed; picker remains usable and root access may prompt later"
  return 1
}

install_helper() {
  [ -f "$HELPER_SRC" ] || { log "ERROR: root helper source missing: $HELPER_SRC"; return 1; }
  mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  helper_current=0
  if [ -f "$HELPER_DST" ] && cmp -s "$HELPER_SRC" "$HELPER_DST"; then
    owner=$(stat -c '%u:%g' "$HELPER_DST" 2>/dev/null)
    mode=$(stat -c '%a' "$HELPER_DST" 2>/dev/null)
    [ "$owner" = 0:0 ] && [ "$mode" = 755 ] && helper_current=1
  fi
  if [ "$helper_current" -eq 1 ]; then
    record_noop "root helper already current: $HELPER_DST"
    return 0
  fi
  cp -f "$HELPER_SRC" "$HELPER_DST" >> "$LOG" 2>&1 || return 1
  chown 0:0 "$HELPER_DST" >> "$LOG" 2>&1 ||
    log "WARN: helper ownership repair failed"
  if ! chmod 0755 "$HELPER_DST" >> "$LOG" 2>&1; then
    log "ERROR: helper executable mode could not be set"
    return 1
  fi
  restorecon "$HELPER_DST" >> "$LOG" 2>&1 ||
    log "WARN: helper restorecon failed"
  record_mutation "installed or repaired root helper: $HELPER_DST"
  return 0
}

external_provider_healthy() {
  # Return 0=healthy, 1=definitively unavailable, 2=inconclusive/transient.
  pkg_exists com.android.externalstorage || return 1
  roots=$(run_bounded_sh 8 "content query --uri content://com.android.externalstorage.documents/root --user '$TARGET_USER'" 2>&1)
  rc=$?
  echo "$roots" >> "$LOG"
  [ "$rc" -eq "$BOUNDED_COMMAND_SKIPPED" ] && return 2
  [ "$rc" -eq 0 ] || return 2
  echo "$roots" | grep -q 'root_id=primary' || return 1
  children=$(run_bounded_sh 10 "content query --uri content://com.android.externalstorage.documents/document/primary%3A/children --user '$TARGET_USER'" 2>&1)
  rc=$?
  echo "$children" >> "$LOG"
  [ "$rc" -eq "$BOUNDED_COMMAND_SKIPPED" ] && return 2
  [ "$rc" -eq 0 ] || return 2
  # An empty primary directory is still a valid provider result.
  return 0
}

write_documentsui_prefs() {
  show=$1
  uid=$(pkg_uid com.android.documentsui)
  case "$uid" in ''|*[!0-9]*) log "ERROR: DocumentsUI UID unavailable"; return 1 ;; esac
  if [ "$show" = 1 ]; then value=true; else value=false; fi
  generated=$GENERATED_DIR/documentsui-preferences.xml
  cat > "$generated" <<EOPREF
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name="includeDeviceRoot" value="$value" />
    <boolean name="includeDeviceRoot-1" value="$value" />
    <boolean name="includeDeviceRoot-2" value="$value" />
    <boolean name="includeDeviceRoot-3" value="$value" />
    <boolean name="includeDeviceRoot-4" value="$value" />
    <boolean name="includeDeviceRoot-5" value="$value" />
    <boolean name="includeDeviceRoot-6" value="$value" />
    <boolean name="includeDeviceRoot-7" value="$value" />
    <boolean name="includeDeviceRoot-8" value="$value" />
    <boolean name="showAdvanced" value="$value" />
    <boolean name="advancedDevices" value="$value" />
    <boolean name="showDeviceStorageOption" value="$value" />
    <boolean name="fileSize" value="true" />
</map>
EOPREF
  template=$generated
  applied=0
  for base in "/data/user/$TARGET_USER/com.android.documentsui" "/data/data/com.android.documentsui"; do
    mkdir -p "$base/shared_prefs" 2>/dev/null || continue
    ensure_path_owner "$base" "$uid" || return 1
    ensure_path_owner "$base/shared_prefs" "$uid" || return 1
    for name in com.android.documentsui_preferences.xml com.android.documentsui.xml DocumentsUI.xml; do
      generated=$GENERATED_DIR/$name
      cp -f "$template" "$generated" || return 1
      install_if_changed "$generated" "$base/shared_prefs/$name" "$uid" 600         "DocumentsUI preferences $base/$name" || return 1
      applied=$((applied + 1))
    done
  done
  rm -f "$template"
  log "DocumentsUI action-scoped internal roots visible=$show uid=$uid files=$applied"
}

refresh_picker_once() {
  show=$1
  is_on "$FIX_REFRESH_PICKER_ON_CHANGE" || return 0
  config_hash=$(sha256sum "$CFG" 2>/dev/null | awk '{print $1}')
  [ -n "$config_hash" ] || config_hash=unknown
  desired="v1.3.0:$show:$config_hash"
  # Missing state is expected on first install; unreadable state simply forces one safe refresh.
  current=$(cat "$STATE_DIR/applied-state" 2>/dev/null)
  [ -n "$current" ] || current=""
  [ "$current" = "$desired" ] && { log "picker state already current"; return 0; }

  for base in "/data/user/$TARGET_USER/com.android.documentsui" "/data/data/com.android.documentsui"; do
    [ -d "$base" ] || continue
    if ! rm -f -- "$base"/databases/roots.db* "$base"/databases/lastAccess.db* \
      "$base"/databases/lastAccessed.db* "$base"/databases/pickCount.db* >> "$LOG" 2>&1; then
      log "WARN: optional DocumentsUI root-cache database cleanup failed: $base"
    fi
    if [ -d "$base/cache" ] && ! find "$base/cache" -maxdepth 1 -type f -name '*root*' -delete >> "$LOG" 2>&1; then
      log "WARN: optional DocumentsUI root-cache file cleanup failed: $base/cache"
    fi
  done
  if ! am force-stop com.android.documentsui >> "$LOG" 2>&1; then
    log "WARN: DocumentsUI was not running or could not be force-stopped; cache files were already refreshed"
  fi
  if ! am force-stop "$ROOT_PKG" >> "$LOG" 2>&1; then
    log "WARN: root provider was not running or could not be force-stopped"
  fi
  if ! echo "$desired" > "$STATE_DIR/applied-state" 2>/dev/null; then
    log "WARN: applied-state marker could not be written; next boot will repeat the safe refresh"
  fi
  log "picker cache refreshed for new module/config state"
}

find_mixplorer_package() {
  for package in com.mixplorer.silver com.mixplorer; do
    if pkg_exists "$package"; then
      echo "$package"
      return 0
    fi
  done
  echo ""
}

resolve_picker_action() {
  action=$1
  case "$action" in
    android.intent.action.OPEN_DOCUMENT_TREE)
      query="cmd package resolve-activity --brief --user '$TARGET_USER' -a '$action'"
      fallback="cmd package resolve-activity --brief -a '$action'"
      ;;
    *)
      query="cmd package resolve-activity --brief --user '$TARGET_USER' -a '$action' -c android.intent.category.OPENABLE -t '*/*'"
      fallback="cmd package resolve-activity --brief -a '$action' -c android.intent.category.OPENABLE -t '*/*'"
      ;;
  esac
  output=$(run_bounded_sh 6 "$query" 2>&1)
  rc=$?
  if [ "$rc" -eq "$BOUNDED_COMMAND_SKIPPED" ]; then
    echo "resolve $action skipped: $output" >> "$LOG"
    return 2
  fi
  if [ "$rc" -ne 0 ] || [ -z "$output" ]; then
    output=$(run_bounded_sh 6 "$fallback" 2>&1)
    rc=$?
  fi
  if [ "$rc" -eq "$BOUNDED_COMMAND_SKIPPED" ]; then
    echo "resolve $action fallback skipped: $output" >> "$LOG"
    return 2
  fi
  echo "resolve $action rc=$rc: $output" >> "$LOG"
  [ "$rc" -eq 0 ] && echo "$output" | grep -q 'com.android.documentsui/'
}

write_resolver_state() {
  state=$1
  if ! echo "$state $(date '+%F %T %z' 2>/dev/null || echo unknown)" > "$STATE_DIR/picker-resolver-state" 2>/dev/null; then
    log "WARN: picker resolver state marker could not be written"
  fi
}

verify_picker_resolver() {
  failed=0
  skipped=0
  for action in android.intent.action.OPEN_DOCUMENT_TREE android.intent.action.OPEN_DOCUMENT android.intent.action.GET_CONTENT; do
    resolve_picker_action "$action"
    rc=$?
    case "$rc" in
      0) log "picker resolver OK: $action" ;;
      2)
        log "WARN: picker resolver verification skipped because no bounded runner exists: $action"
        skipped=$((skipped + 1))
        ;;
      *)
        log "ERROR: picker resolver is not DocumentsUI: $action"
        failed=$((failed + 1))
        ;;
    esac
  done
  if [ "$failed" -gt 0 ]; then
    write_resolver_state "failed=$failed skipped=$skipped"
    return 1
  fi
  if [ "$skipped" -gt 0 ]; then
    write_resolver_state "inconclusive skipped=$skipped"
    return 0
  fi
  write_resolver_state "healthy"
  return 0
}

load_config
case "$CONFIG_SCHEMA" in ''|*[!0-9]*) CONFIG_SCHEMA=2 ;; esac
case "$TARGET_USER" in ''|*[!0-9]*) TARGET_USER=0 ;; esac
case "$BOOT_WAIT_ATTEMPTS" in ''|*[!0-9]*) BOOT_WAIT_ATTEMPTS=45 ;; esac
case "$BOOT_WAIT_SECONDS" in ''|*[!0-9]*) BOOT_WAIT_SECONDS=2 ;; esac
case "$ROOT_PROVIDER_STAGE_LIMIT_BYTES" in ''|*[!0-9]*) ROOT_PROVIDER_STAGE_LIMIT_BYTES=268435456 ;; esac
case "$ROOT_PROVIDER_STAGE_DIR" in /storage/emulated/0/*) ;; *) ROOT_PROVIDER_STAGE_DIR=/storage/emulated/0/.TS18-Root-Provider ;; esac

log "===== TS18 Full File Picker v1.3.0 start ====="
log "build=$(getprop ro.build.display.id 2>/dev/null) sdk=$(getprop ro.build.version.sdk 2>/dev/null) user=$TARGET_USER schema=$CONFIG_SCHEMA"

attempt=0
while [ "$attempt" -lt "$BOOT_WAIT_ATTEMPTS" ]; do
  [ "$(getprop sys.boot_completed 2>/dev/null)" = 1 ] && break
  attempt=$((attempt + 1))
  sleep "$BOOT_WAIT_SECONDS"
done
log "boot wait completed after $attempt checks"

if is_on "$FIX_DISABLE_STALE_TS18_PROVIDER"; then
  run_migration_once stale-provider-v121 cleanup_stale_provider ||
    log "WARN: stale provider migration remains pending"
fi

if is_on "$FIX_DISABLE_APP_MANAGER_PICKER_INTERCEPTOR"; then
  if ! disable_component "$APP_MANAGER_PKG/.intercept.ActivityInterceptor"; then
    log "WARN: short App Manager interceptor component was not present or could not be disabled"
  fi
  if ! disable_component "$APP_MANAGER_PKG/io.github.muntashirakon.AppManager.intercept.ActivityInterceptor"; then
    log "WARN: fully-qualified App Manager interceptor component was not present or could not be disabled"
  fi
fi
if is_on "$FIX_CLEAR_PICKER_PREFERRED_ACTIVITIES"; then
  run_migration_once picker-preferred-v121 cleanup_picker_preferred_migration ||
    log "WARN: picker preferred-activity migration remains pending"
fi

if is_on "$FIX_ENABLE_AOSP_DOCUMENTSUI"; then
  enable_pkg com.android.documentsui || log "ERROR: DocumentsUI package could not be enabled"
fi
if is_on "$FIX_ENABLE_DOCUMENTSUI_COMPONENTS"; then
  for component in \
    com.android.documentsui/.picker.PickActivity \
    com.android.documentsui/.files.FilesActivity \
    com.android.documentsui/.files.LauncherActivity \
    com.android.documentsui/.LauncherActivity \
    com.android.documentsui/.ViewDownloadsActivity \
    com.android.documentsui/.ScopedAccessActivity; do
    if ! enable_component "$component"; then
      log "ERROR: DocumentsUI entrypoint could not be enabled: $component"
    fi
  done
fi
if is_on "$FIX_DISABLE_GOOGLE_DOCUMENTSUI"; then
  if ! disable_pkg com.google.android.documentsui; then
    log "WARN: competing Google DocumentsUI package could not be disabled"
  fi
fi

if is_on "$FIX_ENABLE_EXTERNAL_STORAGE_PROVIDER"; then
  if ! enable_pkg com.android.externalstorage; then
    log "ERROR: stock ExternalStorageProvider package could not be enabled"
  fi
  if ! enable_component com.android.externalstorage/.ExternalStorageProvider; then
    log "ERROR: stock ExternalStorageProvider component could not be enabled"
  fi
  if ! enable_component com.android.externalstorage/.MountReceiver; then
    log "WARN: ExternalStorageProvider mount receiver could not be enabled"
  fi
fi
if is_on "$FIX_DISABLE_EXTERNAL_STORAGE_TEST_PROVIDER"; then
  if ! disable_component com.android.externalstorage/.TestDocumentsProvider; then
    log "WARN: optional ExternalStorageProvider test component could not be disabled"
  fi
fi

if is_on "$FIX_REPAIR_DOCUMENTSUI_DATA_OWNER"; then
  if ! repair_package_data_owner com.android.documentsui; then
    log "ERROR: DocumentsUI private-data ownership repair failed"
  fi
fi

if is_on "$FIX_ENABLE_ROOT_FILE_PROVIDER"; then
  if install_helper; then
    if ! enable_pkg "$ROOT_PKG"; then
      log "WARN: root provider package unavailable; stock picker remains enabled"
    fi
    if ! prepare_stage_dir; then
      log "WARN: root provider staging directory unavailable; stock picker remains enabled"
    fi
    if ! auto_grant_root; then
      log "WARN: root provider may request Magisk permission when root-only content is opened"
    fi
    if ! write_root_provider_prefs; then
      log "WARN: root provider preferences could not be written; built-in safe defaults remain"
    fi
    if ! enable_component "$ROOT_COMPONENT"; then
      log "WARN: root provider component unavailable; stock picker remains enabled"
    fi
  else
    if ! disable_component "$ROOT_COMPONENT"; then
      log "WARN: failed root-provider component could not be disabled"
    fi
    log "WARN: root provider disabled because helper installation failed; stock picker remains enabled"
  fi
else
  if ! disable_component "$ROOT_COMPONENT"; then
    log "WARN: root-provider component could not be disabled by configuration"
  fi
fi

MIXPLORER_PKG=$(find_mixplorer_package)
if is_on "$FIX_ENABLE_MIXPLORER_PROVIDER" && [ -n "$MIXPLORER_PKG" ]; then
  if ! enable_pkg "$MIXPLORER_PKG"; then
    log "WARN: optional MiXplorer package could not be enabled"
  fi
  if ! enable_component "$MIXPLORER_PKG/com.mixplorer.providers.DocProvider"; then
    log "WARN: optional MiXplorer DocumentsProvider could not be enabled"
  fi
fi

if is_on "$FIX_GRANT_STORAGE_ACCESS"; then
  for package in com.android.documentsui com.android.externalstorage "$ROOT_PKG"; do
    grant_if_requested "$package" android.permission.READ_EXTERNAL_STORAGE
    grant_if_requested "$package" android.permission.WRITE_EXTERNAL_STORAGE
    set_appop "$package" READ_EXTERNAL_STORAGE
    set_appop "$package" WRITE_EXTERNAL_STORAGE
    set_appop "$package" LEGACY_STORAGE
  done
fi
if is_on "$FIX_GRANT_MIXPLORER_STORAGE_PERMS" && [ -n "$MIXPLORER_PKG" ]; then
  grant_if_requested "$MIXPLORER_PKG" android.permission.READ_EXTERNAL_STORAGE
  grant_if_requested "$MIXPLORER_PKG" android.permission.WRITE_EXTERNAL_STORAGE
  set_appop "$MIXPLORER_PKG" READ_EXTERNAL_STORAGE
  set_appop "$MIXPLORER_PKG" WRITE_EXTERNAL_STORAGE
  set_appop "$MIXPLORER_PKG" LEGACY_STORAGE
fi

if is_on "$FIX_CREATE_STANDARD_INTERNAL_DIRS"; then
  for directory in Download Documents Music Movies Pictures DCIM Alarms Audiobooks Notifications Podcasts Ringtones; do
    if ! mkdir -p "/storage/emulated/0/$directory" >> "$LOG" 2>&1; then
      log "WARN: optional standard shared-storage directory could not be created: $directory"
    fi
  done
fi

external_show=1
case "$EXTERNAL_ROOT_MODE" in
  show) external_show=1 ;;
  hide) external_show=0 ;;
  auto)
    external_provider_healthy
    health_rc=$?
    case "$health_rc" in
      0)
        external_show=1
        log "external primary root and child listing passed"
        ;;
      1)
        external_show=0
        log "WARN: external primary root is definitively unavailable in auto mode"
        ;;
      *)
        # Missing timeout or transient provider failure is inconclusive, not proof that
        # exact-device-proven primary storage should be hidden.
        external_show=1
        log "WARN: external primary root test was inconclusive in auto mode; kept primary visible"
        ;;
    esac
    ;;
  *)
    external_show=1
    log "WARN: unknown EXTERNAL_ROOT_MODE=$EXTERNAL_ROOT_MODE; defaulted to show"
    ;;
esac
if ! write_documentsui_prefs "$external_show"; then
  log "ERROR: DocumentsUI advanced-root preferences could not be repaired"
fi
refresh_picker_once "$external_show"

if is_on "$FIX_WARM_UP_PROVIDERS"; then
  for warmup_uri in \
    content://com.android.providers.downloads.documents/root \
    content://com.android.externalstorage.documents/root \
    content://$ROOT_AUTH/root; do
    if ! run_bounded_sh 8 "content query --uri '$warmup_uri' --user '$TARGET_USER'" >> "$LOG" 2>&1; then
      log "WARN: optional provider warm-up did not complete: $warmup_uri"
    fi
  done
fi

if is_on "$FIX_VERIFY_PICKER_RESOLVER"; then
  if ! verify_picker_resolver; then
    log "ERROR: one or more picker actions still resolve away from DocumentsUI"
  fi
fi

if is_on "$DIAG_AUTO_RUN_ON_BOOT" && [ -x "$MODDIR/tools/ts18-saf-deepdiag.sh" ]; then
  if ! sh "$MODDIR/tools/ts18-saf-deepdiag.sh" boot >> "$LOG" 2>&1; then
    # Diagnostics are optional evidence collection and must not invalidate picker repair.
    log "WARN: optional boot diagnostics failed"
  fi
fi

log "reconcile summary mutations=$MUTATION_COUNT noops=$NOOP_COUNT"
log "service complete"
exit 0
