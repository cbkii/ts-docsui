#!/system/bin/sh
# TS18 SAF service: no-crash picker repair.
# - Keeps stable DocumentsUI overlay.
# - Disables invalid TS18LocalDocumentsProvider.
# - Keeps ExternalStorageProvider if present but hides advanced/broken roots by DocumentsUI prefs.
# - Enables MiXplorer DocumentsProvider as existing broad-access fallback.

MODDIR=${0%/*}
CFG=/data/adb/ts18-documentsui-saf.conf
LOGDIR=/data/adb/ts18-documentsui-saf/logs
LOG=$LOGDIR/service-v080.log
mkdir -p "$LOGDIR" 2>/dev/null || true

TARGET_USER=0
BOOT_WAIT_ATTEMPTS=45
BOOT_WAIT_SECONDS=2
FIX_ENABLE_AOSP_DOCUMENTSUI=1
FIX_ENABLE_DOCUMENTSUI_COMPONENTS=1
FIX_DISABLE_TS18_LOCAL_SAF_PROVIDER=1
FIX_ENABLE_TS18_LOCAL_SAF_PROVIDER=0
FIX_ENABLE_TS18_LOCAL_SAF_PROVIDER_COMPONENTS=0
FIX_DISABLE_APP_MANAGER_PICKER_INTERCEPTOR=1
FIX_DISABLE_GOOGLE_AML_DOCUMENTSUI=1
FIX_REMOVE_USER_DOCUMENTSUI_SHADOWS=0
FIX_TOUCH_CANONICAL_EXTERNALSTORAGE_PROVIDER=1
FIX_ENABLE_CANONICAL_EXTERNALSTORAGE_PROVIDER=1
FIX_DISABLE_EXTERNALSTORAGE_TEST_PROVIDER=1
FIX_HIDE_BROKEN_EXTERNAL_ADVANCED_ROOTS=1
FIX_DISABLE_CANONICAL_EXTERNALSTORAGE_PROVIDER=0
FIX_FORCE_STOP_EXTERNALSTORAGE=0
FIX_CLEAR_EXTERNALSTORAGE_DATA=0
FIX_ENABLE_MIXPLORER_PROVIDER=1
FIX_GRANT_MIXPLORER_STORAGE_PERMS=1
FIX_GRANT_DOCUMENTSUI_RUNTIME_PERMS=1
FIX_SET_DOCUMENTSUI_APPOPS=1
FIX_SET_LEGACY_STORAGE_APPOPS=1
FIX_FIX_APP_DATA_OWNERSHIP=1
FIX_SET_DOCUMENTSUI_DEVICE_ROOT_PREFS=1
FIX_RESET_DOCUMENTSUI_ROOTS_CACHE=1
FIX_CREATE_STANDARD_INTERNAL_DIRS=1
FIX_FORCE_STOP_DOCUMENTSUI=1
FIX_PROVIDER_WARMUP_QUERIES=1
DIAG_AUTO_RUN_ON_BOOT=0

is_allowed_key() {
  case "$1" in
    TARGET_USER|BOOT_WAIT_ATTEMPTS|BOOT_WAIT_SECONDS|FIX_ENABLE_AOSP_DOCUMENTSUI|FIX_ENABLE_DOCUMENTSUI_COMPONENTS|FIX_DISABLE_TS18_LOCAL_SAF_PROVIDER|FIX_ENABLE_TS18_LOCAL_SAF_PROVIDER|FIX_ENABLE_TS18_LOCAL_SAF_PROVIDER_COMPONENTS|FIX_DISABLE_APP_MANAGER_PICKER_INTERCEPTOR|FIX_DISABLE_GOOGLE_AML_DOCUMENTSUI|FIX_REMOVE_USER_DOCUMENTSUI_SHADOWS|FIX_TOUCH_CANONICAL_EXTERNALSTORAGE_PROVIDER|FIX_ENABLE_CANONICAL_EXTERNALSTORAGE_PROVIDER|FIX_DISABLE_EXTERNALSTORAGE_TEST_PROVIDER|FIX_HIDE_BROKEN_EXTERNAL_ADVANCED_ROOTS|FIX_DISABLE_CANONICAL_EXTERNALSTORAGE_PROVIDER|FIX_FORCE_STOP_EXTERNALSTORAGE|FIX_CLEAR_EXTERNALSTORAGE_DATA|FIX_ENABLE_MIXPLORER_PROVIDER|FIX_GRANT_MIXPLORER_STORAGE_PERMS|FIX_GRANT_DOCUMENTSUI_RUNTIME_PERMS|FIX_SET_DOCUMENTSUI_APPOPS|FIX_SET_LEGACY_STORAGE_APPOPS|FIX_FIX_APP_DATA_OWNERSHIP|FIX_SET_DOCUMENTSUI_DEVICE_ROOT_PREFS|FIX_RESET_DOCUMENTSUI_ROOTS_CACHE|FIX_CREATE_STANDARD_INTERNAL_DIRS|FIX_FORCE_STOP_DOCUMENTSUI|FIX_PROVIDER_WARMUP_QUERIES|DIAG_AUTO_RUN_ON_BOOT|DIAG_OUTPUT_ROOT|DIAG_COPY_RELEVANT_APKS|DIAG_COPY_ALL_APKS|DIAG_MAX_COPY_BYTES) return 0 ;;
    *) return 1 ;;
  esac
}
valid_val() { case "$1" in ''|*[!A-Za-z0-9_./:-]*) return 1 ;; *) return 0 ;; esac; }
load_config() {
  if [ ! -f "$CFG" ] && [ -f "$MODDIR/config.default" ]; then
    cp -f "$MODDIR/config.default" "$CFG" 2>/dev/null || true
  fi
  [ -f "$CFG" ] || return 0
  while IFS='=' read -r key val || [ -n "$key" ]; do
    case "$key" in ''|'#'*) continue ;; esac
    is_allowed_key "$key" || continue
    valid_val "$val" || continue
    eval "$key=\$val"
  done < "$CFG"
}
is_on() { case "$1" in 1|true|TRUE|yes|YES|on|ON|enabled|ENABLED) return 0 ;; *) return 1 ;; esac; }
log() { echo "[$(date '+%F %T' 2>/dev/null || echo time)] $*" >> "$LOG"; }
pkg_exists() { pm path "$1" >/dev/null 2>&1; }

pm_enable_pkg() {
  p="$1"
  pkg_exists "$p" || { log "package absent: $p"; return 0; }
  pm install-existing --user "$TARGET_USER" "$p" >>"$LOG" 2>&1 || true
  pm enable --user "$TARGET_USER" "$p" >>"$LOG" 2>&1 || true
  log "enabled package: $p"
}
pm_disable_pkg() {
  p="$1"
  pkg_exists "$p" || { log "package absent for disable: $p"; return 0; }
  pm disable-user --user "$TARGET_USER" "$p" >>"$LOG" 2>&1 || true
  log "disabled package: $p"
}
enable_comp() {
  c="$1"
  pm enable --user "$TARGET_USER" "$c" >>"$LOG" 2>&1 || true
  log "enable component attempted: $c"
}
disable_comp() {
  c="$1"
  pm disable --user "$TARGET_USER" "$c" >>"$LOG" 2>&1 || true
  pm disable-user --user "$TARGET_USER" "$c" >>"$LOG" 2>&1 || true
  log "disable component attempted: $c"
}

pkg_dump_has() { p="$1"; needle="$2"; pm dump "$p" 2>/dev/null | grep -Fq "$needle"; }
grant_if_requested() {
  p="$1"; perm="$2"
  pkg_exists "$p" || return 0
  if pkg_dump_has "$p" "$perm"; then
    pm grant "$p" "$perm" >>"$LOG" 2>&1 || true
    log "grant attempted: $p $perm"
  else
    log "skip grant not requested: $p $perm"
  fi
}
appop_known() {
  op="$1"
  appops get android >/dev/null 2>&1 || true
  appops set android "$op" allow >/dev/null 2>&1
  rc=$?
  # Do not rely on setting android package; fallback string check via appops help where available.
  if [ "$rc" = "0" ]; then return 0; fi
  appops set android "$op" default >/dev/null 2>&1 || true
  appops set com.android.shell "$op" allow >/dev/null 2>&1 && { appops set com.android.shell "$op" default >/dev/null 2>&1 || true; return 0; }
  return 1
}
set_appop_safe() {
  p="$1"; op="$2"
  pkg_exists "$p" || return 0
  case "$op" in MANAGE_EXTERNAL_STORAGE|NO_ISOLATED_STORAGE) log "skip appop unsupported on Android 10 target: $op"; return 0 ;; esac
  appops set "$p" "$op" allow >>"$LOG" 2>&1 || true
  log "appop attempted: $p $op"
}

pkg_uid() {
  p="$1"
  cmd package list packages -U "$p" 2>/dev/null | sed -n 's/.* uid://p' | head -n 1
}
fix_owner() {
  p="$1"; uid="$(pkg_uid "$p")"
  case "$uid" in ''|*[!0-9]*) log "no uid for $p"; return 0 ;; esac
  for d in "/data/user/$TARGET_USER/$p" "/data/data/$p" "/data/user_de/$TARGET_USER/$p"; do
    [ -e "$d" ] || continue
    chown -R "$uid:$uid" "$d" >>"$LOG" 2>&1 || true
    restorecon -RF "$d" >>"$LOG" 2>&1 || true
    log "owner fixed: $d uid=$uid"
  done
}

write_docsui_prefs() {
  p=com.android.documentsui
  uid="$(pkg_uid "$p")"
  case "$uid" in ''|*[!0-9]*) uid=0 ;; esac
  if is_on "$FIX_HIDE_BROKEN_EXTERNAL_ADVANCED_ROOTS"; then
    include=false; show=false; adv=false; device=false
  else
    include=true; show=true; adv=true; device=true
  fi
  for base in "/data/user/$TARGET_USER/$p" "/data/data/$p"; do
    [ -d "$base" ] || mkdir -p "$base" 2>/dev/null || true
    mkdir -p "$base/shared_prefs" 2>/dev/null || true
    for fn in com.android.documentsui_preferences.xml com.android.documentsui.xml DocumentsUI.xml; do
      f="$base/shared_prefs/$fn"
      [ -f "$f" ] && cp -f "$f" "$f.ts18bak.$(date +%Y%m%d%H%M%S 2>/dev/null || echo bak)" 2>/dev/null || true
      cat > "$f" <<EOPREF
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
    <boolean name="includeDeviceRoot" value="$include" />
    <boolean name="showAdvanced" value="$show" />
    <boolean name="advancedDevices" value="$adv" />
    <boolean name="showDeviceStorageOption" value="$device" />
    <boolean name="fileSize" value="true" />
</map>
EOPREF
      chown "$uid:$uid" "$f" 2>/dev/null || true
      chmod 0600 "$f" 2>/dev/null || true
      restorecon "$f" >/dev/null 2>&1 || true
      log "wrote DocumentsUI pref: $f uid=$uid hideAdvanced=$FIX_HIDE_BROKEN_EXTERNAL_ADVANCED_ROOTS"
    done
    chown -R "$uid:$uid" "$base/shared_prefs" 2>/dev/null || true
    restorecon -RF "$base" >/dev/null 2>&1 || true
  done
}

reset_docsui_cache() {
  for base in "/data/user/$TARGET_USER/com.android.documentsui" "/data/data/com.android.documentsui"; do
    [ -d "$base" ] || continue
    mkdir -p "$base/databases" "$base/cache" 2>/dev/null || true
    for pattern in roots.db roots.db-journal roots.db-wal roots.db-shm lastAccessed.db lastAccessed.db-* lastAccess.db lastAccess.db-* pickCount.db pickCount.db-*; do
      rm -f "$base/databases/$pattern" 2>/dev/null || true
    done
    find "$base/cache" -maxdepth 1 -type f -name '*root*' -delete 2>/dev/null || true
    log "reset DocumentsUI cache/db: $base"
  done
}

content_query() {
  uri="$1"
  content query --uri "$uri" --user "$TARGET_USER" >>"$LOG" 2>&1 || content query --uri "$uri" >>"$LOG" 2>&1 || true
}

load_config
case "$TARGET_USER" in ''|*[!0-9]*) TARGET_USER=0 ;; esac
{
  echo "===== TS18 SAF v0.8.0 service $(date '+%F %T %z' 2>/dev/null || echo unknown) ====="
  echo "module=$MODDIR"
  echo "user=$TARGET_USER"
  echo "build=$(getprop ro.build.display.id 2>/dev/null) sdk=$(getprop ro.build.version.sdk 2>/dev/null)"
} >> "$LOG"

i=0
while [ "$i" -lt "$BOOT_WAIT_ATTEMPTS" ]; do
  [ "$(getprop sys.boot_completed 2>/dev/null)" = "1" ] && break
  i=$((i+1)); sleep "$BOOT_WAIT_SECONDS"
done
log "boot wait complete attempt=$i"

is_on "$FIX_ENABLE_AOSP_DOCUMENTSUI" && pm_enable_pkg com.android.documentsui
if is_on "$FIX_DISABLE_GOOGLE_AML_DOCUMENTSUI"; then pm_disable_pkg com.google.android.documentsui; fi
if is_on "$FIX_ENABLE_DOCUMENTSUI_COMPONENTS"; then
  enable_comp com.android.documentsui/.picker.PickActivity
  enable_comp com.android.documentsui/.files.FilesActivity
  enable_comp com.android.documentsui/.LauncherActivity
fi

# v2.2 provider APK was invalid on TS18; always allow disabling stale package/component.
if is_on "$FIX_DISABLE_TS18_LOCAL_SAF_PROVIDER"; then
  disable_comp com.ts18.safprovider/.TS18DocumentsProvider
  pm_disable_pkg com.ts18.safprovider
  pm clear --user "$TARGET_USER" com.ts18.safprovider >>"$LOG" 2>&1 || true
fi

if is_on "$FIX_TOUCH_CANONICAL_EXTERNALSTORAGE_PROVIDER" && pkg_exists com.android.externalstorage; then
  if is_on "$FIX_DISABLE_CANONICAL_EXTERNALSTORAGE_PROVIDER"; then
    disable_comp com.android.externalstorage/.ExternalStorageProvider
  elif is_on "$FIX_ENABLE_CANONICAL_EXTERNALSTORAGE_PROVIDER"; then
    pm_enable_pkg com.android.externalstorage
    enable_comp com.android.externalstorage/.ExternalStorageProvider
  fi
  if is_on "$FIX_DISABLE_EXTERNALSTORAGE_TEST_PROVIDER"; then
    disable_comp com.android.externalstorage/.TestDocumentsProvider
  fi
fi

if is_on "$FIX_ENABLE_MIXPLORER_PROVIDER" && pkg_exists com.mixplorer; then
  pm_enable_pkg com.mixplorer
  enable_comp com.mixplorer/.providers.DocProvider
fi

if is_on "$FIX_DISABLE_APP_MANAGER_PICKER_INTERCEPTOR"; then
  disable_comp io.github.muntashirakon.AppManager/.intercept.ActivityInterceptor
  disable_comp io.github.muntashirakon.AppManager/io.github.muntashirakon.AppManager.intercept.ActivityInterceptor
fi

if is_on "$FIX_GRANT_DOCUMENTSUI_RUNTIME_PERMS"; then
  for perm in android.permission.READ_EXTERNAL_STORAGE android.permission.WRITE_EXTERNAL_STORAGE android.permission.ACCESS_MEDIA_LOCATION; do
    grant_if_requested com.android.documentsui "$perm"
  done
fi
if is_on "$FIX_GRANT_MIXPLORER_STORAGE_PERMS"; then
  for perm in android.permission.READ_EXTERNAL_STORAGE android.permission.WRITE_EXTERNAL_STORAGE android.permission.ACCESS_MEDIA_LOCATION; do
    grant_if_requested com.mixplorer "$perm"
  done
fi
if is_on "$FIX_SET_DOCUMENTSUI_APPOPS"; then
  for op in READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE LEGACY_STORAGE; do
    set_appop_safe com.android.documentsui "$op"
  done
fi
if is_on "$FIX_GRANT_MIXPLORER_STORAGE_PERMS"; then
  for op in READ_EXTERNAL_STORAGE WRITE_EXTERNAL_STORAGE LEGACY_STORAGE; do
    set_appop_safe com.mixplorer "$op"
  done
fi

if is_on "$FIX_FIX_APP_DATA_OWNERSHIP"; then
  fix_owner com.android.documentsui
  fix_owner com.mixplorer
fi
is_on "$FIX_SET_DOCUMENTSUI_DEVICE_ROOT_PREFS" && write_docsui_prefs
is_on "$FIX_RESET_DOCUMENTSUI_ROOTS_CACHE" && reset_docsui_cache

if is_on "$FIX_CREATE_STANDARD_INTERNAL_DIRS"; then
  for d in /storage/emulated/0/Download /storage/emulated/0/Documents /storage/emulated/0/Music /storage/emulated/0/Movies /storage/emulated/0/Pictures /storage/emulated/0/DCIM; do
    mkdir -p "$d" >>"$LOG" 2>&1 || true
  done
fi

if is_on "$FIX_FORCE_STOP_DOCUMENTSUI"; then
  am force-stop com.android.documentsui >>"$LOG" 2>&1 || true
fi
if is_on "$FIX_FORCE_STOP_EXTERNALSTORAGE"; then
  am force-stop com.android.externalstorage >>"$LOG" 2>&1 || true
fi

if is_on "$FIX_PROVIDER_WARMUP_QUERIES"; then
  content_query content://com.android.providers.downloads.documents/root
  content_query content://com.android.externalstorage.documents/root
  content_query content://com.android.externalstorage.documents/document/home%3A/children
  content_query content://com.mixplorer.doc/root
fi

if is_on "$DIAG_AUTO_RUN_ON_BOOT" && [ -x "$MODDIR/tools/ts18-saf-deepdiag.sh" ]; then
  sh "$MODDIR/tools/ts18-saf-deepdiag.sh" boot >>"$LOG" 2>&1 || true
fi

log "service complete"
exit 0
