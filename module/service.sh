#!/system/bin/sh
# TS18 Full File Picker late-start service.
# Restores a working DocumentsUI resolver, exposes stock internal storage, and prepares
# the optional Magisk-backed provider without allowing root discovery to block picker launch.

MODDIR=${0%/*}
STATE_DIR=/data/adb/ts18-documentsui-saf
CFG=/data/adb/ts18-documentsui-saf.conf
LOGDIR=$STATE_DIR/logs
LOG=$LOGDIR/service-v101.log
HELPER_SRC=$MODDIR/tools/rootfs-helper.sh
HELPER_DST=$STATE_DIR/rootfs-helper.sh
ROOT_PKG=com.cbkii.tsdocsui.rootprovider
ROOT_COMPONENT=$ROOT_PKG/.RootDocumentsProvider
ROOT_AUTH=com.cbkii.tsdocsui.root.documents
STALE_PROVIDER_PKG=com.ts18.safprovider
APP_MANAGER_PKG=io.github.muntashirakon.AppManager

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

mkdir -p "$LOGDIR" 2>/dev/null || exit 0
if [ -f "$LOG" ]; then
  size=$(wc -c < "$LOG" 2>/dev/null || echo 0)
  case "$size" in ''|*[!0-9]*) size=0 ;; esac
  if [ "$size" -gt 524288 ]; then
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
      chmod 0644 "$CFG" 2>/dev/null || true
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

enable_pkg() {
  package=$1
  pkg_exists "$package" || { log "ERROR: package absent: $package"; return 1; }
  pm install-existing --user "$TARGET_USER" "$package" >> "$LOG" 2>&1 || true
  output=$(pm enable --user "$TARGET_USER" "$package" 2>&1)
  rc=$?
  echo "$output" >> "$LOG"
  if [ "$rc" -eq 0 ]; then
    log "enabled package: $package"
    return 0
  fi
  log "ERROR: failed to enable package: $package rc=$rc"
  return "$rc"
}

disable_pkg() {
  package=$1
  pkg_exists "$package" || { log "package absent for disable: $package"; return 0; }
  output=$(pm disable-user --user "$TARGET_USER" "$package" 2>&1)
  rc=$?
  echo "$output" >> "$LOG"
  if [ "$rc" -eq 0 ]; then
    log "disabled package: $package"
    return 0
  fi
  log "WARN: failed to disable package: $package rc=$rc"
  return "$rc"
}

enable_component() {
  component=$1
  package=${component%%/*}
  pkg_exists "$package" || { log "ERROR: component package absent: $component"; return 1; }
  output=$(pm enable --user "$TARGET_USER" "$component" 2>&1)
  rc=$?
  echo "$output" >> "$LOG"
  if [ "$rc" -eq 0 ]; then
    log "enabled component: $component"
    return 0
  fi
  log "ERROR: failed to enable component: $component rc=$rc"
  return "$rc"
}

disable_component() {
  component=$1
  package=${component%%/*}
  pkg_exists "$package" || { log "component package absent for disable: $component"; return 0; }
  output=$(pm disable-user --user "$TARGET_USER" "$component" 2>&1)
  rc=$?
  echo "$output" >> "$LOG"
  if [ "$rc" -ne 0 ]; then
    output=$(pm disable --user "$TARGET_USER" "$component" 2>&1)
    rc=$?
    echo "$output" >> "$LOG"
  fi
  if [ "$rc" -eq 0 ]; then
    log "disabled component: $component"
    return 0
  fi
  log "WARN: failed to disable component: $component rc=$rc"
  return "$rc"
}

grant_if_requested() {
  package=$1
  permission=$2
  pkg_exists "$package" || return 0
  if pm dump "$package" 2>/dev/null | grep -Fq "$permission"; then
    output=$(pm grant --user "$TARGET_USER" "$package" "$permission" 2>&1)
    rc=$?
    echo "$output" >> "$LOG"
    [ "$rc" -eq 0 ] && log "granted permission: $package $permission" || log "WARN: permission grant failed: $package $permission rc=$rc"
  else
    log "skip permission not requested: $package $permission"
  fi
}

set_appop() {
  package=$1
  operation=$2
  pkg_exists "$package" || return 0
  output=$(appops set --user "$TARGET_USER" "$package" "$operation" allow 2>&1)
  rc=$?
  echo "$output" >> "$LOG"
  [ "$rc" -eq 0 ] && log "set app-op: $package $operation" || log "WARN: app-op failed: $package $operation rc=$rc"
}

find_timeout() {
  if [ -x /data/adb/magisk/busybox ]; then
    echo "/data/adb/magisk/busybox timeout"
  elif command -v timeout >/dev/null 2>&1; then
    echo timeout
  elif command -v busybox >/dev/null 2>&1; then
    echo "busybox timeout"
  else
    echo ""
  fi
}

TIMEOUT_CMD=$(find_timeout)
run_bounded_sh() {
  seconds=$1
  shift
  command_text=$*
  if [ -z "$TIMEOUT_CMD" ]; then
    log "WARN: timeout unavailable; skipped bounded command: $command_text"
    return 124
  fi
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
  repaired=0
  for base in "/data/user/$TARGET_USER/$package" "/data/data/$package" "/data/user_de/$TARGET_USER/$package"; do
    [ -e "$base" ] || continue
    if chown -R "$uid:$uid" "$base" >> "$LOG" 2>&1; then
      repaired=$((repaired + 1))
    else
      log "WARN: owner repair failed: $base uid=$uid"
    fi
    restorecon -RF "$base" >> "$LOG" 2>&1 || true
  done
  log "package data ownership checked: $package uid=$uid paths=$repaired"
  return 0
}

cleanup_stale_provider() {
  pkg_exists "$STALE_PROVIDER_PKG" || { log "stale provider absent: $STALE_PROVIDER_PKG"; return 0; }
  disable_component "$STALE_PROVIDER_PKG/.TS18DocumentsProvider" || true
  disable_pkg "$STALE_PROVIDER_PKG" || true
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
  pkg_exists "$package" || return 0
  output=$(cmd package clear-package-preferred-activities "$package" 2>&1)
  rc=$?
  echo "$output" >> "$LOG"
  if [ "$rc" -ne 0 ]; then
    output=$(pm clear-package-preferred-activities "$package" 2>&1)
    rc=$?
    echo "$output" >> "$LOG"
  fi
  [ "$rc" -eq 0 ] && log "cleared preferred activities: $package" || log "WARN: could not clear preferred activities: $package rc=$rc"
}

prepare_stage_dir() {
  case "$ROOT_PROVIDER_STAGE_DIR" in
    /storage/emulated/0/*) ;;
    *)
      log "invalid root provider staging path; using shared-storage default"
      ROOT_PROVIDER_STAGE_DIR=/storage/emulated/0/.TS18-Root-Provider
      ;;
  esac
  mkdir -p "$ROOT_PROVIDER_STAGE_DIR" >> "$LOG" 2>&1 || return 1
  chmod 0777 "$ROOT_PROVIDER_STAGE_DIR" >> "$LOG" 2>&1 || true
  find "$ROOT_PROVIDER_STAGE_DIR" -maxdepth 1 -type f -name 'root-*.stage' -mmin +60 -delete >> "$LOG" 2>&1 || true
  log "root provider staging directory ready: $ROOT_PROVIDER_STAGE_DIR"
}

write_root_provider_prefs() {
  uid=$(pkg_uid "$ROOT_PKG")
  case "$uid" in ''|*[!0-9]*) log "ERROR: root provider UID unavailable"; return 1 ;; esac
  base=/data/user/$TARGET_USER/$ROOT_PKG
  prefs_dir=$base/shared_prefs
  prefs_file=$prefs_dir/provider.xml
  mkdir -p "$prefs_dir" 2>/dev/null || { log "ERROR: cannot create root provider prefs"; return 1; }
  cat > "$prefs_file" <<EOPREF
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
  chown -R "$uid:$uid" "$base" 2>/dev/null || true
  chmod 0600 "$prefs_file" 2>/dev/null || true
  restorecon -RF "$base" >/dev/null 2>&1 || true
  log "wrote root provider preferences uid=$uid"
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
  sql="REPLACE INTO policies (uid, policy, until, logging, notification) VALUES ($uid, 2, 0, 1, 0);"
  if "$magisk_bin" --sqlite "$sql" >> "$LOG" 2>&1; then
    log "Magisk root policy granted to $ROOT_PKG uid=$uid"
    return 0
  fi
  log "WARN: Magisk root policy grant failed; picker remains usable and root access may prompt later"
  return 1
}

install_helper() {
  [ -f "$HELPER_SRC" ] || { log "ERROR: root helper source missing: $HELPER_SRC"; return 1; }
  mkdir -p "$STATE_DIR" 2>/dev/null || return 1
  cp -f "$HELPER_SRC" "$HELPER_DST" >> "$LOG" 2>&1 || return 1
  chown 0:0 "$HELPER_DST" 2>/dev/null || true
  chmod 0755 "$HELPER_DST" 2>/dev/null || true
  restorecon "$HELPER_DST" >/dev/null 2>&1 || true
  log "installed root helper: $HELPER_DST"
  return 0
}

external_provider_healthy() {
  pkg_exists com.android.externalstorage || return 1
  roots=$(run_bounded_sh 8 "content query --uri content://com.android.externalstorage.documents/root --user '$TARGET_USER'" 2>&1)
  rc=$?
  echo "$roots" >> "$LOG"
  [ "$rc" -eq 0 ] || return 1
  echo "$roots" | grep -q 'root_id=primary' || return 1
  children=$(run_bounded_sh 10 "content query --uri content://com.android.externalstorage.documents/document/primary%3A/children --user '$TARGET_USER'" 2>&1)
  rc=$?
  echo "$children" >> "$LOG"
  [ "$rc" -eq 0 ] || return 1
  echo "$children" | grep -q 'document_id=primary:' || return 1
  return 0
}

write_documentsui_prefs() {
  show=$1
  uid=$(pkg_uid com.android.documentsui)
  case "$uid" in ''|*[!0-9]*) log "ERROR: DocumentsUI UID unavailable"; return 1 ;; esac
  if [ "$show" = 1 ]; then value=true; else value=false; fi
  for base in "/data/user/$TARGET_USER/com.android.documentsui" "/data/data/com.android.documentsui"; do
    mkdir -p "$base/shared_prefs" 2>/dev/null || continue
    for name in com.android.documentsui_preferences.xml com.android.documentsui.xml DocumentsUI.xml; do
      file=$base/shared_prefs/$name
      cat > "$file" <<EOPREF
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name="includeDeviceRoot" value="$value" />
    <boolean name="showAdvanced" value="$value" />
    <boolean name="advancedDevices" value="$value" />
    <boolean name="showDeviceStorageOption" value="$value" />
    <boolean name="fileSize" value="true" />
</map>
EOPREF
      chown "$uid:$uid" "$file" 2>/dev/null || true
      chmod 0600 "$file" 2>/dev/null || true
    done
    chown -R "$uid:$uid" "$base/shared_prefs" 2>/dev/null || true
    restorecon -RF "$base" >/dev/null 2>&1 || true
  done
  log "DocumentsUI internal roots visible=$show uid=$uid"
}

refresh_picker_once() {
  show=$1
  is_on "$FIX_REFRESH_PICKER_ON_CHANGE" || return 0
  config_hash=$(sha256sum "$CFG" 2>/dev/null | awk '{print $1}')
  [ -n "$config_hash" ] || config_hash=unknown
  desired="v1.0.1:$show:$config_hash"
  current=$(cat "$STATE_DIR/applied-state" 2>/dev/null || true)
  [ "$current" = "$desired" ] && { log "picker state already current"; return 0; }

  for base in "/data/user/$TARGET_USER/com.android.documentsui" "/data/data/com.android.documentsui"; do
    [ -d "$base" ] || continue
    rm -f "$base"/databases/roots.db* "$base"/databases/lastAccess.db* \
      "$base"/databases/lastAccessed.db* "$base"/databases/pickCount.db* 2>/dev/null || true
    find "$base/cache" -maxdepth 1 -type f -name '*root*' -delete 2>/dev/null || true
  done
  am force-stop com.android.documentsui >> "$LOG" 2>&1 || true
  am force-stop "$ROOT_PKG" >> "$LOG" 2>&1 || true
  echo "$desired" > "$STATE_DIR/applied-state" 2>/dev/null || true
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
  if [ "$rc" -ne 0 ] || [ -z "$output" ]; then
    output=$(run_bounded_sh 6 "$fallback" 2>&1)
    rc=$?
  fi
  echo "resolve $action rc=$rc: $output" >> "$LOG"
  [ "$rc" -eq 0 ] && echo "$output" | grep -q 'com.android.documentsui/'
}

verify_picker_resolver() {
  failed=0
  for action in android.intent.action.OPEN_DOCUMENT_TREE android.intent.action.OPEN_DOCUMENT android.intent.action.GET_CONTENT; do
    if resolve_picker_action "$action"; then
      log "picker resolver OK: $action"
    else
      log "ERROR: picker resolver is not DocumentsUI: $action"
      failed=$((failed + 1))
    fi
  done
  if [ "$failed" -eq 0 ]; then
    echo "healthy $(date '+%F %T %z' 2>/dev/null || echo unknown)" > "$STATE_DIR/picker-resolver-state" 2>/dev/null || true
    return 0
  fi
  echo "failed=$failed $(date '+%F %T %z' 2>/dev/null || echo unknown)" > "$STATE_DIR/picker-resolver-state" 2>/dev/null || true
  return 1
}

load_config
case "$CONFIG_SCHEMA" in ''|*[!0-9]*) CONFIG_SCHEMA=2 ;; esac
case "$TARGET_USER" in ''|*[!0-9]*) TARGET_USER=0 ;; esac
case "$BOOT_WAIT_ATTEMPTS" in ''|*[!0-9]*) BOOT_WAIT_ATTEMPTS=45 ;; esac
case "$BOOT_WAIT_SECONDS" in ''|*[!0-9]*) BOOT_WAIT_SECONDS=2 ;; esac
case "$ROOT_PROVIDER_STAGE_LIMIT_BYTES" in ''|*[!0-9]*) ROOT_PROVIDER_STAGE_LIMIT_BYTES=268435456 ;; esac
case "$ROOT_PROVIDER_STAGE_DIR" in /storage/emulated/0/*) ;; *) ROOT_PROVIDER_STAGE_DIR=/storage/emulated/0/.TS18-Root-Provider ;; esac

log "===== TS18 Full File Picker v1.0.1 start ====="
log "build=$(getprop ro.build.display.id 2>/dev/null) sdk=$(getprop ro.build.version.sdk 2>/dev/null) user=$TARGET_USER schema=$CONFIG_SCHEMA"

attempt=0
while [ "$attempt" -lt "$BOOT_WAIT_ATTEMPTS" ]; do
  [ "$(getprop sys.boot_completed 2>/dev/null)" = 1 ] && break
  attempt=$((attempt + 1))
  sleep "$BOOT_WAIT_SECONDS"
done
log "boot wait completed after $attempt checks"

if is_on "$FIX_DISABLE_STALE_TS18_PROVIDER"; then
  cleanup_stale_provider
fi

if is_on "$FIX_DISABLE_APP_MANAGER_PICKER_INTERCEPTOR"; then
  disable_component "$APP_MANAGER_PKG/.intercept.ActivityInterceptor" || true
  disable_component "$APP_MANAGER_PKG/io.github.muntashirakon.AppManager.intercept.ActivityInterceptor" || true
fi
if is_on "$FIX_CLEAR_PICKER_PREFERRED_ACTIVITIES"; then
  clear_picker_preferred_activities "$APP_MANAGER_PKG"
  clear_picker_preferred_activities com.google.android.documentsui
fi

if is_on "$FIX_ENABLE_AOSP_DOCUMENTSUI"; then
  enable_pkg com.android.documentsui || log "ERROR: DocumentsUI package could not be enabled"
fi
if is_on "$FIX_ENABLE_DOCUMENTSUI_COMPONENTS"; then
  enable_component com.android.documentsui/.picker.PickActivity || true
  enable_component com.android.documentsui/.files.FilesActivity || true
  enable_component com.android.documentsui/.files.LauncherActivity || true
  enable_component com.android.documentsui/.LauncherActivity || true
  enable_component com.android.documentsui/.ViewDownloadsActivity || true
  enable_component com.android.documentsui/.ScopedAccessActivity || true
fi
if is_on "$FIX_DISABLE_GOOGLE_DOCUMENTSUI"; then
  disable_pkg com.google.android.documentsui || true
fi

if is_on "$FIX_ENABLE_EXTERNAL_STORAGE_PROVIDER"; then
  enable_pkg com.android.externalstorage || true
  enable_component com.android.externalstorage/.ExternalStorageProvider || true
  enable_component com.android.externalstorage/.MountReceiver || true
fi
if is_on "$FIX_DISABLE_EXTERNAL_STORAGE_TEST_PROVIDER"; then
  disable_component com.android.externalstorage/.TestDocumentsProvider || true
fi

if is_on "$FIX_REPAIR_DOCUMENTSUI_DATA_OWNER"; then
  repair_package_data_owner com.android.documentsui || true
fi

if is_on "$FIX_ENABLE_ROOT_FILE_PROVIDER"; then
  if install_helper; then
    enable_pkg "$ROOT_PKG" || true
    prepare_stage_dir || log "WARN: root provider staging directory unavailable"
    auto_grant_root || true
    write_root_provider_prefs || true
    enable_component "$ROOT_COMPONENT" || log "WARN: root provider component unavailable; stock picker remains enabled"
  else
    disable_component "$ROOT_COMPONENT" || true
    log "WARN: root provider disabled because helper installation failed; stock picker remains enabled"
  fi
else
  disable_component "$ROOT_COMPONENT" || true
fi

MIXPLORER_PKG=$(find_mixplorer_package)
if is_on "$FIX_ENABLE_MIXPLORER_PROVIDER" && [ -n "$MIXPLORER_PKG" ]; then
  enable_pkg "$MIXPLORER_PKG" || true
  enable_component "$MIXPLORER_PKG/com.mixplorer.providers.DocProvider" || true
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
    mkdir -p "/storage/emulated/0/$directory" >> "$LOG" 2>&1 || true
  done
fi

external_show=1
case "$EXTERNAL_ROOT_MODE" in
  show) external_show=1 ;;
  hide) external_show=0 ;;
  auto)
    if external_provider_healthy; then
      external_show=1
      log "external primary root and child listing passed"
    else
      external_show=0
      log "WARN: external primary root test failed in auto mode; root provider remains available"
    fi
    ;;
  *)
    external_show=1
    log "WARN: unknown EXTERNAL_ROOT_MODE=$EXTERNAL_ROOT_MODE; defaulted to show"
    ;;
esac
write_documentsui_prefs "$external_show" || true
if is_on "$FIX_REPAIR_DOCUMENTSUI_DATA_OWNER"; then
  repair_package_data_owner com.android.documentsui || true
fi
refresh_picker_once "$external_show"

if is_on "$FIX_WARM_UP_PROVIDERS"; then
  run_bounded_sh 8 "content query --uri content://com.android.providers.downloads.documents/root --user '$TARGET_USER'" >> "$LOG" 2>&1 || true
  run_bounded_sh 8 "content query --uri content://com.android.externalstorage.documents/root --user '$TARGET_USER'" >> "$LOG" 2>&1 || true
  run_bounded_sh 8 "content query --uri content://$ROOT_AUTH/root --user '$TARGET_USER'" >> "$LOG" 2>&1 || true
fi

if is_on "$FIX_VERIFY_PICKER_RESOLVER"; then
  verify_picker_resolver || log "ERROR: one or more picker actions still resolve away from DocumentsUI"
fi

if is_on "$DIAG_AUTO_RUN_ON_BOOT" && [ -x "$MODDIR/tools/ts18-saf-deepdiag.sh" ]; then
  sh "$MODDIR/tools/ts18-saf-deepdiag.sh" boot >> "$LOG" 2>&1 || true
fi

log "service complete"
exit 0
