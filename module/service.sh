#!/system/bin/sh
# ts-docsui late-start reconciler for TS18 Android 10 / API 29.
# /data/adb stores only small required state. Logs are written only under Download.

MODDIR=${0%/*}
STATE=/data/adb/ts-docsui
CFG=/data/adb/ts-docsui.conf
OUT=/storage/emulated/0/Download/ts-docsui
LOG=/dev/null
GEN=$STATE/generated
HELPER_SRC=$MODDIR/tools/rootfs-helper.sh
HELPER_DST=$STATE/rootfs-helper.sh
ROOT_PKG=com.cbkii.tsdocsui.rootprovider
ROOT_COMPONENT=$ROOT_PKG/.RootDocumentsProvider
APP_MANAGER=io.github.muntashirakon.AppManager
USER_ID=0
WAIT_TRIES=45
WAIT_SECONDS=2
EXTERNAL_ROOT_MODE=show
ROOT_STAGE=/storage/emulated/0/.ts-docsui-root-provider
ROOT_LIMIT=268435456
MUTATIONS=0
NOOPS=0

# Defaults may be overridden by /data/adb/ts-docsui.conf.
FIX_ENABLE_AOSP_DOCUMENTSUI=1
FIX_ENABLE_DOCUMENTSUI_COMPONENTS=1
FIX_REPAIR_DOCUMENTSUI_DATA_OWNER=1
FIX_DISABLE_GOOGLE_DOCUMENTSUI=1
FIX_DISABLE_APP_MANAGER_PICKER_INTERCEPTOR=1
FIX_CLEAR_PICKER_PREFERRED_ACTIVITIES=1
FIX_VERIFY_PICKER_RESOLVER=1
FIX_ENABLE_EXTERNAL_STORAGE_PROVIDER=1
FIX_DISABLE_EXTERNAL_STORAGE_TEST_PROVIDER=1
FIX_ENABLE_ROOT_FILE_PROVIDER=1
FIX_AUTO_GRANT_ROOT_PROVIDER=1
ROOT_PROVIDER_SHOW_INTERNAL=1
ROOT_PROVIDER_SHOW_DEVICE=1
ROOT_PROVIDER_SHOW_USB=1
ROOT_PROVIDER_ALLOW_CREATE=1
ROOT_PROVIDER_ALLOW_WRITE=1
ROOT_PROVIDER_ALLOW_RENAME=1
ROOT_PROVIDER_ALLOW_DELETE=1
FIX_GRANT_STORAGE_ACCESS=1
FIX_CREATE_STANDARD_INTERNAL_DIRS=1
FIX_REFRESH_PICKER_ON_CHANGE=1
FIX_WARM_UP_PROVIDERS=1

MODULE_VERSION=$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | head -n1)
[ -n "$MODULE_VERSION" ] || MODULE_VERSION=unknown

on() { case "$1" in 1|true|TRUE|yes|YES|on|ON) return 0;; *) return 1;; esac; }
log() { [ "$LOG" = /dev/null ] || printf '[%s] %s\n' "$(date '+%F %T' 2>/dev/null || echo time)" "$*" >>"$LOG"; }
mut() { MUTATIONS=$((MUTATIONS + 1)); log "MUTATION: $*"; }
noop() { NOOPS=$((NOOPS + 1)); log "NO-OP: $*"; }

set_cfg() {
  key=$1 value=$2
  case "$key" in
    TARGET_USER) USER_ID=$value;;
    BOOT_WAIT_ATTEMPTS) WAIT_TRIES=$value;;
    BOOT_WAIT_SECONDS) WAIT_SECONDS=$value;;
    EXTERNAL_ROOT_MODE) EXTERNAL_ROOT_MODE=$value;;
    ROOT_PROVIDER_STAGE_DIR) ROOT_STAGE=$value;;
    ROOT_PROVIDER_STAGE_LIMIT_BYTES) ROOT_LIMIT=$value;;
    FIX_*|ROOT_PROVIDER_SHOW_*|ROOT_PROVIDER_ALLOW_*)
      case "$key" in
        FIX_ENABLE_AOSP_DOCUMENTSUI) FIX_ENABLE_AOSP_DOCUMENTSUI=$value;;
        FIX_ENABLE_DOCUMENTSUI_COMPONENTS) FIX_ENABLE_DOCUMENTSUI_COMPONENTS=$value;;
        FIX_REPAIR_DOCUMENTSUI_DATA_OWNER) FIX_REPAIR_DOCUMENTSUI_DATA_OWNER=$value;;
        FIX_DISABLE_GOOGLE_DOCUMENTSUI) FIX_DISABLE_GOOGLE_DOCUMENTSUI=$value;;
        FIX_DISABLE_APP_MANAGER_PICKER_INTERCEPTOR) FIX_DISABLE_APP_MANAGER_PICKER_INTERCEPTOR=$value;;
        FIX_CLEAR_PICKER_PREFERRED_ACTIVITIES) FIX_CLEAR_PICKER_PREFERRED_ACTIVITIES=$value;;
        FIX_VERIFY_PICKER_RESOLVER) FIX_VERIFY_PICKER_RESOLVER=$value;;
        FIX_ENABLE_EXTERNAL_STORAGE_PROVIDER) FIX_ENABLE_EXTERNAL_STORAGE_PROVIDER=$value;;
        FIX_DISABLE_EXTERNAL_STORAGE_TEST_PROVIDER) FIX_DISABLE_EXTERNAL_STORAGE_TEST_PROVIDER=$value;;
        FIX_ENABLE_ROOT_FILE_PROVIDER) FIX_ENABLE_ROOT_FILE_PROVIDER=$value;;
        FIX_AUTO_GRANT_ROOT_PROVIDER) FIX_AUTO_GRANT_ROOT_PROVIDER=$value;;
        ROOT_PROVIDER_SHOW_INTERNAL) ROOT_PROVIDER_SHOW_INTERNAL=$value;;
        ROOT_PROVIDER_SHOW_DEVICE) ROOT_PROVIDER_SHOW_DEVICE=$value;;
        ROOT_PROVIDER_SHOW_USB) ROOT_PROVIDER_SHOW_USB=$value;;
        ROOT_PROVIDER_ALLOW_CREATE) ROOT_PROVIDER_ALLOW_CREATE=$value;;
        ROOT_PROVIDER_ALLOW_WRITE) ROOT_PROVIDER_ALLOW_WRITE=$value;;
        ROOT_PROVIDER_ALLOW_RENAME) ROOT_PROVIDER_ALLOW_RENAME=$value;;
        ROOT_PROVIDER_ALLOW_DELETE) ROOT_PROVIDER_ALLOW_DELETE=$value;;
        FIX_GRANT_STORAGE_ACCESS) FIX_GRANT_STORAGE_ACCESS=$value;;
        FIX_CREATE_STANDARD_INTERNAL_DIRS) FIX_CREATE_STANDARD_INTERNAL_DIRS=$value;;
        FIX_REFRESH_PICKER_ON_CHANGE) FIX_REFRESH_PICKER_ON_CHANGE=$value;;
        FIX_WARM_UP_PROVIDERS) FIX_WARM_UP_PROVIDERS=$value;;
        *) return 1;;
      esac;;
    *) return 1;;
  esac
}

load_cfg() {
  [ -f "$CFG" ] || cp -f "$MODDIR/config.default" "$CFG" 2>/dev/null || return 0
  while IFS='=' read -r key value || [ -n "$key" ]; do
    case "$key:$value" in ''*|'#'*|*:*[!A-Za-z0-9_./:-]*) continue;; esac
    set_cfg "$key" "$value" || continue
  done <"$CFG"
}

pkg_exists() { pm path "$1" >/dev/null 2>&1; }
pkg_enabled() { pm list packages -e --user "$USER_ID" "$1" 2>/dev/null | grep -Fxq "package:$1"; }
pkg_disabled() { pm list packages -d --user "$USER_ID" "$1" 2>/dev/null | grep -Fxq "package:$1"; }

pkg_uid() {
  uid=$(cmd package list packages -U "$1" 2>/dev/null | sed -n 's/.* uid://p' | head -n1)
  case "$uid" in ''|*[!0-9]*) uid=$(pm dump "$1" 2>/dev/null | sed -n 's/.*userId=\([0-9][0-9]*\).*/\1/p' | head -n1);; esac
  printf '%s' "$uid"
}

component_state() {
  component=$1 package=${1%%/*} class=${1#*/}
  case "$class" in .*) full=$package$class;; *) full=$class;; esac
  value=$(cmd package get-component-enabled-setting --user "$USER_ID" "$component" 2>/dev/null)
  case "$value" in 1|enabled|*STATE_ENABLED*) echo enabled; return;; 2|3|4|disabled|disabled-user|*STATE_DISABLED*) echo disabled; return;; esac
  dump=$(dumpsys package "$package" 2>/dev/null)
  [ -n "$dump" ] || { echo unknown; return; }
  printf '%s\n' "$dump" | awk -v user="$USER_ID" -v full="$full" -v flat="$component" -v short="$class" '
    $0 ~ "^[[:space:]]*User " user ":" {inside=1; section=""; next}
    inside && $0 ~ "^[[:space:]]*User [0-9]+:" {exit}
    !inside {next}
    /enabledComponents:/ {section="enabled"; next}
    /disabledComponents:/ {section="disabled"; next}
    section!="" {line=$0; gsub(/^[[:space:]]+|[[:space:]]+$/, "", line); if(line==full||line==flat||line==short){print section; found=1; exit}}
    END {if(!found) print "default"}'
}

enable_pkg() {
  pkg=$1
  pkg_exists "$pkg" || { log "ERROR: package absent: $pkg"; return 1; }
  pkg_enabled "$pkg" && { noop "package enabled: $pkg"; return 0; }
  pm install-existing --user "$USER_ID" "$pkg" >>"$LOG" 2>&1 || :
  pm enable --user "$USER_ID" "$pkg" >>"$LOG" 2>&1 || { log "ERROR: enable package failed: $pkg"; return 1; }
  mut "enabled package: $pkg"
}

disable_pkg() {
  pkg=$1
  pkg_exists "$pkg" || { noop "package absent: $pkg"; return 0; }
  pkg_disabled "$pkg" && { noop "package disabled: $pkg"; return 0; }
  pm disable-user --user "$USER_ID" "$pkg" >>"$LOG" 2>&1 || { log "WARN: disable package failed: $pkg"; return 1; }
  mut "disabled package: $pkg"
}

set_component() {
  desired=$1 component=$2 state=$(component_state "$2")
  [ "$state" = "$desired" ] && { noop "component $desired: $component"; return 0; }
  if [ "$desired" = enabled ]; then
    pm enable --user "$USER_ID" "$component" >>"$LOG" 2>&1 || return 1
  else
    pm disable-user --user "$USER_ID" "$component" >>"$LOG" 2>&1 || pm disable --user "$USER_ID" "$component" >>"$LOG" 2>&1 || return 1
  fi
  mut "component $desired: $component previous=$state"
}

permission_granted() { pm dump "$1" 2>/dev/null | grep -Fq "$2: granted=true"; }
grant_permission() {
  pkg=$1 permission=$2
  pkg_exists "$pkg" || return 0
  pm dump "$pkg" 2>/dev/null | grep -Fq "$permission" || { noop "permission not requested: $pkg $permission"; return 0; }
  permission_granted "$pkg" "$permission" && { noop "permission granted: $pkg $permission"; return 0; }
  pm grant --user "$USER_ID" "$pkg" "$permission" >>"$LOG" 2>&1 && mut "granted permission: $pkg $permission"
}

set_appop() {
  pkg=$1 op=$2
  pkg_exists "$pkg" || return 0
  appops get --user "$USER_ID" "$pkg" "$op" 2>/dev/null | grep -Eq '(^|[[:space:]])allow([[:space:]]|;|$)' && { noop "app-op allowed: $pkg $op"; return 0; }
  appops set --user "$USER_ID" "$pkg" "$op" allow >>"$LOG" 2>&1 && mut "allowed app-op: $pkg $op"
}

install_changed() {
  source=$1 target=$2 uid=$3 mode=$4 label=$5
  if [ -f "$target" ] && cmp -s "$source" "$target"; then rm -f "$source"; noop "$label current"; else cp -f "$source" "$target" || return 1; rm -f "$source"; mut "$label updated"; fi
  chown "$uid:$uid" "$target" 2>/dev/null || return 1
  chmod "$mode" "$target" 2>/dev/null || return 1
  restorecon "$target" >/dev/null 2>&1 || :
}

repair_owner() {
  pkg=$1 uid=$(pkg_uid "$1")
  case "$uid" in ''|*[!0-9]*) return 1;; esac
  for base in "/data/user/$USER_ID/$pkg" "/data/data/$pkg"; do
    [ -d "$base" ] || continue
    mismatch=$(find "$base" -xdev \( ! -user "$uid" -o ! -group "$uid" \) -print -quit 2>/dev/null)
    [ -n "$mismatch" ] || { noop "ownership current: $base"; continue; }
    chown -R "$uid:$uid" "$base" >>"$LOG" 2>&1 || return 1
    restorecon -RF "$base" >>"$LOG" 2>&1 || :
    mut "ownership repaired: $base"
  done
}

bool() { on "$1" && echo true || echo false; }

write_root_prefs() {
  uid=$(pkg_uid "$ROOT_PKG"); case "$uid" in ''|*[!0-9]*) return 1;; esac
  base=/data/user/$USER_ID/$ROOT_PKG/shared_prefs
  mkdir -p "$base" "$GEN" || return 1
  file=$GEN/root-provider.xml
  cat >"$file" <<XML
<?xml version='1.0' encoding='utf-8' standalone='yes' ?>
<map>
<boolean name="showInternal" value="$(bool "$ROOT_PROVIDER_SHOW_INTERNAL")" />
<boolean name="showDevice" value="$(bool "$ROOT_PROVIDER_SHOW_DEVICE")" />
<boolean name="showUsb" value="$(bool "$ROOT_PROVIDER_SHOW_USB")" />
<boolean name="allowCreate" value="$(bool "$ROOT_PROVIDER_ALLOW_CREATE")" />
<boolean name="allowWrite" value="$(bool "$ROOT_PROVIDER_ALLOW_WRITE")" />
<boolean name="allowRename" value="$(bool "$ROOT_PROVIDER_ALLOW_RENAME")" />
<boolean name="allowDelete" value="$(bool "$ROOT_PROVIDER_ALLOW_DELETE")" />
<string name="stageDir">$ROOT_STAGE</string>
<long name="stageLimitBytes" value="$ROOT_LIMIT" />
</map>
XML
  install_changed "$file" "$base/provider.xml" "$uid" 600 "root-provider preferences"
}

write_documentsui_prefs() {
  show=$1 uid=$(pkg_uid com.android.documentsui); case "$uid" in ''|*[!0-9]*) return 1;; esac
  [ "$show" = 1 ] && value=true || value=false
  base=/data/user/$USER_ID/com.android.documentsui/shared_prefs
  mkdir -p "$base" "$GEN" || return 1
  template=$GEN/documentsui.xml
  {
    echo "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>"; echo '<map>'
    for key in includeDeviceRoot includeDeviceRoot-1 includeDeviceRoot-2 includeDeviceRoot-3 includeDeviceRoot-4 includeDeviceRoot-5 includeDeviceRoot-6 includeDeviceRoot-7 includeDeviceRoot-8 showAdvanced advancedDevices showDeviceStorageOption; do echo "<boolean name=\"$key\" value=\"$value\" />"; done
    echo '<boolean name="fileSize" value="true" />'; echo '</map>'
  } >"$template"
  for name in com.android.documentsui_preferences.xml com.android.documentsui.xml DocumentsUI.xml; do cp -f "$template" "$GEN/$name" || return 1; install_changed "$GEN/$name" "$base/$name" "$uid" 600 "DocumentsUI $name" || return 1; done
  rm -f "$template"
}

install_helper() {
  [ -f "$HELPER_SRC" ] || return 1
  mkdir -p "$STATE" || return 1
  [ -f "$HELPER_DST" ] && cmp -s "$HELPER_SRC" "$HELPER_DST" && [ "$(stat -c %a "$HELPER_DST" 2>/dev/null)" = 755 ] && { noop "root helper current"; return 0; }
  cp -f "$HELPER_SRC" "$HELPER_DST" || return 1
  chown 0:0 "$HELPER_DST"; chmod 0755 "$HELPER_DST"; restorecon "$HELPER_DST" >/dev/null 2>&1 || :
  mut "root helper updated"
}

prepare_stage() {
  case "$ROOT_STAGE" in /storage/emulated/0/*) ;; *) ROOT_STAGE=/storage/emulated/0/.ts-docsui-root-provider;; esac
  mkdir -p "$ROOT_STAGE" || return 1
  chmod 0777 "$ROOT_STAGE" 2>/dev/null || :
  find "$ROOT_STAGE" -maxdepth 1 -type f -name 'root-*.stage' -mmin +60 -delete 2>/dev/null || :
}

auto_root() {
  on "$FIX_AUTO_GRANT_ROOT_PROVIDER" || return 0
  uid=$(pkg_uid "$ROOT_PKG"); case "$uid" in ''|*[!0-9]*) return 1;; esac
  magisk=$(command -v magisk 2>/dev/null); [ -n "$magisk" ] || magisk=/data/adb/magisk/magisk
  [ -x "$magisk" ] || return 1
  current=$($magisk --sqlite "SELECT policy FROM policies WHERE uid=$uid;" 2>/dev/null)
  echo "$current" | grep -Eq '(^|[^0-9])2([^0-9]|$)' && { noop "root policy granted"; return 0; }
  $magisk --sqlite "REPLACE INTO policies (uid,policy,until,logging,notification) VALUES ($uid,2,0,1,0);" >>"$LOG" 2>&1 && mut "root policy granted"
}

find_timeout() { [ -x /data/adb/magisk/busybox ] && { echo '/data/adb/magisk/busybox timeout'; return; }; [ -x /system/bin/toybox ] && { echo '/system/bin/toybox timeout'; return; }; command -v timeout 2>/dev/null || true; }
TIMEOUT=$(find_timeout)
bounded() { seconds=$1; shift; [ -n "$TIMEOUT" ] || return 125; $TIMEOUT "$seconds" sh -c "$*"; }

primary_healthy() {
  roots=$(bounded 8 "content query --uri content://com.android.externalstorage.documents/root --user '$USER_ID'" 2>&1) || return 2
  echo "$roots" | grep -q 'root_id=primary' || return 1
  bounded 10 "content query --uri content://com.android.externalstorage.documents/document/primary%3A/children --user '$USER_ID'" >/dev/null 2>&1 || return 2
}

clear_preferred_once() {
  marker=$STATE/preferred-cleared
  [ -f "$marker" ] && { noop "preferred activities already cleared"; return 0; }
  for pkg in "$APP_MANAGER" com.google.android.documentsui; do pkg_exists "$pkg" || continue; cmd package clear-package-preferred-activities "$pkg" >>"$LOG" 2>&1 || pm clear-package-preferred-activities "$pkg" >>"$LOG" 2>&1 || return 1; done
  : >"$marker" || return 1
  mut "preferred activities cleared"
}

refresh_once() {
  show=$1 hash=$(sha256sum "$CFG" 2>/dev/null | awk '{print $1}') desired="$MODULE_VERSION:$show:$hash"
  [ "$(cat "$STATE/applied-state" 2>/dev/null)" = "$desired" ] && { noop "picker cache current"; return 0; }
  base=/data/user/$USER_ID/com.android.documentsui
  rm -f "$base"/databases/roots.db* "$base"/databases/lastAccess*.db* "$base"/databases/pickCount.db* >>"$LOG" 2>&1 || :
  am force-stop com.android.documentsui >>"$LOG" 2>&1 || :
  am force-stop "$ROOT_PKG" >>"$LOG" 2>&1 || :
  printf '%s\n' "$desired" >"$STATE/applied-state" || return 1
  mut "picker cache refreshed"
}

verify_resolver() {
  failed=0
  for action in android.intent.action.OPEN_DOCUMENT_TREE android.intent.action.OPEN_DOCUMENT android.intent.action.GET_CONTENT; do
    extra="-c android.intent.category.OPENABLE -t '*/*'"; [ "$action" = android.intent.action.OPEN_DOCUMENT_TREE ] && extra=
    result=$(bounded 6 "cmd package resolve-activity --brief --user '$USER_ID' -a '$action' $extra" 2>&1)
    echo "$result" | grep -q 'com.android.documentsui/' || failed=$((failed + 1))
  done
  [ "$failed" -eq 0 ] || { log "ERROR: picker resolver failures=$failed"; return 1; }
  noop "picker resolver verified"
}

load_cfg
case "$USER_ID:$WAIT_TRIES:$WAIT_SECONDS:$ROOT_LIMIT" in *[!0-9:]*) USER_ID=0; WAIT_TRIES=45; WAIT_SECONDS=2; ROOT_LIMIT=268435456;; esac
attempt=0
while [ "$attempt" -lt "$WAIT_TRIES" ] && [ "$(getprop sys.boot_completed 2>/dev/null)" != 1 ]; do attempt=$((attempt + 1)); sleep "$WAIT_SECONDS"; done
mkdir -p "$STATE" "$GEN" || exit 0
if mkdir -p "$OUT/logs" 2>/dev/null; then LOG=$OUT/logs/service.log; [ "$(wc -c <"$LOG" 2>/dev/null || echo 0)" -le 524288 ] || mv -f "$LOG" "$LOG.previous" 2>/dev/null || :; fi
log "===== ts-docsui $MODULE_VERSION start ====="

on "$FIX_DISABLE_APP_MANAGER_PICKER_INTERCEPTOR" && { set_component disabled "$APP_MANAGER/.intercept.ActivityInterceptor" || :; set_component disabled "$APP_MANAGER/io.github.muntashirakon.AppManager.intercept.ActivityInterceptor" || :; }
on "$FIX_CLEAR_PICKER_PREFERRED_ACTIVITIES" && clear_preferred_once || :
on "$FIX_ENABLE_AOSP_DOCUMENTSUI" && enable_pkg com.android.documentsui || :
if on "$FIX_ENABLE_DOCUMENTSUI_COMPONENTS"; then for c in .picker.PickActivity .files.FilesActivity .files.LauncherActivity .LauncherActivity .ViewDownloadsActivity .ScopedAccessActivity; do set_component enabled "com.android.documentsui/$c" || log "ERROR: picker component unavailable: $c"; done; fi
on "$FIX_DISABLE_GOOGLE_DOCUMENTSUI" && disable_pkg com.google.android.documentsui || :
if on "$FIX_ENABLE_EXTERNAL_STORAGE_PROVIDER"; then enable_pkg com.android.externalstorage || :; set_component enabled com.android.externalstorage/.ExternalStorageProvider || :; set_component enabled com.android.externalstorage/.MountReceiver || :; fi
on "$FIX_DISABLE_EXTERNAL_STORAGE_TEST_PROVIDER" && set_component disabled com.android.externalstorage/.TestDocumentsProvider || :
on "$FIX_REPAIR_DOCUMENTSUI_DATA_OWNER" && repair_owner com.android.documentsui || :

if on "$FIX_ENABLE_ROOT_FILE_PROVIDER" && install_helper && enable_pkg "$ROOT_PKG"; then prepare_stage || :; auto_root || :; write_root_prefs || :; set_component enabled "$ROOT_COMPONENT" || :; else set_component disabled "$ROOT_COMPONENT" || :; log 'WARN: root provider unavailable; stock storage remains enabled'; fi

if on "$FIX_GRANT_STORAGE_ACCESS"; then for pkg in com.android.documentsui com.android.externalstorage "$ROOT_PKG"; do grant_permission "$pkg" android.permission.READ_EXTERNAL_STORAGE; grant_permission "$pkg" android.permission.WRITE_EXTERNAL_STORAGE; set_appop "$pkg" READ_EXTERNAL_STORAGE; set_appop "$pkg" WRITE_EXTERNAL_STORAGE; set_appop "$pkg" LEGACY_STORAGE; done; fi
if on "$FIX_CREATE_STANDARD_INTERNAL_DIRS"; then for d in Download Documents Music Movies Pictures DCIM Alarms Audiobooks Notifications Podcasts Ringtones; do mkdir -p "/storage/emulated/0/$d" >>"$LOG" 2>&1 || :; done; fi

show=1
case "$EXTERNAL_ROOT_MODE" in hide) show=0;; auto) primary_healthy; [ "$?" -eq 1 ] && show=0;; esac
write_documentsui_prefs "$show" || log 'ERROR: DocumentsUI preferences failed'
on "$FIX_REFRESH_PICKER_ON_CHANGE" && refresh_once "$show" || :
if on "$FIX_WARM_UP_PROVIDERS"; then for uri in content://com.android.providers.downloads.documents/root content://com.android.externalstorage.documents/root; do bounded 8 "content query --uri '$uri' --user '$USER_ID'" >>"$LOG" 2>&1 || :; done; fi
on "$FIX_VERIFY_PICKER_RESOLVER" && verify_resolver || :
rm -f "$GEN"/* 2>/dev/null || :
log "reconcile summary mutations=$MUTATIONS noops=$NOOPS"
exit 0
