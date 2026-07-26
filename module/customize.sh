#!/system/bin/sh
# TS18 Full File Picker installer for Magisk 28 and newer.
# Installer work uses /data/adb, with /storage/emulated/0 only as a fallback.

SKIPUNZIP=1
MODID=ts18_documentsui_saf_full
OLD_MODID=ts18_docsui_saf
WORKBASE=/data/adb/${MODID}.install
STAGE=$WORKBASE/stage
STATE_DIR=/data/adb/ts18-documentsui-saf
LOGDIR=$STATE_DIR/logs
INSTALL_LOG=$LOGDIR/install.log
CFG=/data/adb/ts18-documentsui-saf.conf
MODULE_VERSION=unknown
MODULE_VERSION_CODE=unknown

note() { ui_print "$1"; }
warn() { ui_print "! $1"; }
stop_install() { abort "STOP: $1"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

choose_workbase() {
  if mkdir -p /data/adb 2>/dev/null; then
    return 0
  fi
  WORKBASE=/storage/emulated/0/${MODID}.install
  STAGE=$WORKBASE/stage
  STATE_DIR=/storage/emulated/0/ts18-documentsui-saf
  LOGDIR=$STATE_DIR/logs
  INSTALL_LOG=$LOGDIR/install.log
  CFG=/storage/emulated/0/ts18-documentsui-saf.conf
  mkdir -p "$WORKBASE" 2>/dev/null
}

run_unzip() {
  if have_cmd unzip && unzip "$@"; then return 0; fi
  if [ -x /data/adb/magisk/busybox ] && /data/adb/magisk/busybox unzip "$@"; then return 0; fi
  if have_cmd busybox && busybox unzip "$@"; then return 0; fi
  if have_cmd toybox && toybox unzip "$@"; then return 0; fi
  return 1
}

clean_work() {
  case "$WORKBASE" in
    /data/adb/${MODID}.install|/storage/emulated/0/${MODID}.install)
      rm -rf "$WORKBASE" 2>/dev/null || true
      ;;
  esac
}

extract_file() {
  source_name=$1
  destination=$2
  mkdir -p "$(dirname "$destination")" 2>/dev/null || return 1
  rm -f "$destination" 2>/dev/null || true
  run_unzip -p "$ZIPFILE" "$source_name" > "$destination" 2>> "$INSTALL_LOG" || return 1
  case "$source_name" in META-INF/*) return 0 ;; *) [ -s "$destination" ] ;; esac
}

extract_tree() {
  prefix=$1
  mkdir -p "$STAGE" 2>/dev/null || return 1
  run_unzip -oq "$ZIPFILE" "${prefix}/*" -d "$STAGE" >> "$INSTALL_LOG" 2>&1 || return 1
  [ -d "$STAGE/$prefix" ] || return 1
  mkdir -p "$MODPATH" 2>/dev/null || return 1
  cp -af "$STAGE/$prefix" "$MODPATH/" >> "$INSTALL_LOG" 2>&1
}

read_module_version() {
  MODULE_VERSION=$(sed -n 's/^version=//p' "$MODPATH/module.prop" 2>/dev/null | head -n 1)
  MODULE_VERSION_CODE=$(sed -n 's/^versionCode=//p' "$MODPATH/module.prop" 2>/dev/null | head -n 1)
  [ -n "$MODULE_VERSION" ] || MODULE_VERSION=unknown
  case "$MODULE_VERSION_CODE" in ''|*[!0-9]*) MODULE_VERSION_CODE=unknown ;; esac
}

merge_config() {
  default_file=$MODPATH/config.default
  [ -f "$default_file" ] || return 1
  mkdir -p "$(dirname "$CFG")" 2>/dev/null || return 1

  if [ ! -f "$CFG" ]; then
    cp -f "$default_file" "$CFG" 2>/dev/null || return 1
    chmod 0644 "$CFG" 2>/dev/null || true
    return 0
  fi

  old_schema=$(sed -n 's/^CONFIG_SCHEMA=//p' "$CFG" 2>/dev/null | head -n 1)
  case "$old_schema" in ''|*[!0-9]*) old_schema=0 ;; esac

  timestamp=$(date +%Y%m%d%H%M%S 2>/dev/null || echo backup)
  backup=${CFG}.pre-${MODULE_VERSION_CODE}.$timestamp
  cp -f "$CFG" "$backup" 2>/dev/null || warn "Could not back up the existing config"

  merged=${CFG}.new
  cp -f "$default_file" "$merged" 2>/dev/null || return 1

  # Preserve values only for keys that still exist in the new documented config.
  while IFS='=' read -r key value || [ -n "$key" ]; do
    case "$key" in ''|'#'*) continue ;; esac
    case "$key" in *[!A-Z0-9_]*) continue ;; esac
    grep -q "^${key}=" "$default_file" 2>/dev/null || continue
    case "$value" in ''|*[!A-Za-z0-9_./:-]*) continue ;; esac
    sed -i "s|^${key}=.*|${key}=${value}|" "$merged" 2>/dev/null || true
  done < "$CFG"

  # Schema 2 repairs the v1.0.1 launch regression. Earlier configs used auto mode,
  # which could hide the proven primary: root after one transient boot query.
  if [ "$old_schema" -lt 2 ]; then
    sed -i \
      -e 's/^CONFIG_SCHEMA=.*/CONFIG_SCHEMA=2/' \
      -e 's/^EXTERNAL_ROOT_MODE=.*/EXTERNAL_ROOT_MODE=show/' \
      -e 's/^FIX_REPAIR_DOCUMENTSUI_DATA_OWNER=.*/FIX_REPAIR_DOCUMENTSUI_DATA_OWNER=1/' \
      -e 's/^FIX_DISABLE_STALE_TS18_PROVIDER=.*/FIX_DISABLE_STALE_TS18_PROVIDER=1/' \
      -e 's/^FIX_CLEAR_PICKER_PREFERRED_ACTIVITIES=.*/FIX_CLEAR_PICKER_PREFERRED_ACTIVITIES=1/' \
      -e 's/^FIX_VERIFY_PICKER_RESOLVER=.*/FIX_VERIFY_PICKER_RESOLVER=1/' \
      "$merged" 2>/dev/null || true
    note "- Migrated picker repair settings to schema 2"
  fi

  mv -f "$merged" "$CFG" 2>/dev/null || return 1
  chmod 0644 "$CFG" 2>/dev/null || true
  return 0
}

note "- TS18 Full File Picker"
note "- Repairs picker intent routing and restores internal/root storage sources"
note "- Uses /data/adb for installer work"

[ "${MAGISK_VER_CODE:-0}" -ge 28000 ] || stop_install "Magisk 28 or newer is required"
SDK=$(getprop ro.build.version.sdk 2>/dev/null || echo unknown)
[ "$SDK" = 29 ] || warn "Designed for Android 10 / SDK 29; detected SDK $SDK"

choose_workbase || stop_install "Cannot create installer work under /data/adb or /storage/emulated/0"
clean_work
mkdir -p "$STAGE" "$LOGDIR" 2>/dev/null || stop_install "Cannot create installer folders"
: > "$INSTALL_LOG" 2>/dev/null || true

{
  echo "zip=$ZIPFILE"
  echo "modpath=$MODPATH"
  echo "workbase=$WORKBASE"
  echo "sdk=$SDK"
  echo "magisk=${MAGISK_VER_CODE:-unknown}"
} >> "$INSTALL_LOG"

case "$MODPATH" in
  /data/adb/modules/$MODID|/data/adb/modules_update/$MODID|/sbin/.magisk/modules/$MODID|/dev/*/$MODID)
    rm -rf "$MODPATH"/* 2>/dev/null || true
    ;;
  *)
    warn "Unexpected module path: $MODPATH; old files were not cleared"
    ;;
esac
mkdir -p "$MODPATH" 2>/dev/null || stop_install "Cannot create module directory"

for file in module.prop config.default customize.sh service.sh post-fs-data.sh uninstall.sh action.sh README.md; do
  note "- extracting $file"
  extract_file "$file" "$MODPATH/$file" || stop_install "Failed to extract $file"
done
for directory in system tools; do
  note "- extracting $directory"
  extract_tree "$directory" || stop_install "Failed to extract $directory"
done

read_module_version
note "- Version $MODULE_VERSION ($MODULE_VERSION_CODE)"
echo "version=$MODULE_VERSION versionCode=$MODULE_VERSION_CODE" >> "$INSTALL_LOG"

[ -s "$MODPATH/system/priv-app/DocumentsUI/DocumentsUI.apk" ] || stop_install "DocumentsUI.apk is missing"
[ -s "$MODPATH/system/priv-app/TS18RootFileProvider/TS18RootFileProvider.apk" ] || stop_install "TS18RootFileProvider.apk is missing"
[ -f "$MODPATH/tools/rootfs-helper.sh" ] || stop_install "Root helper is missing"
[ -f "$MODPATH/tools/ts18-saf-deepdiag.sh" ] || stop_install "Diagnostics script is missing"

merge_config || warn "Could not merge the runtime config; module defaults will be used"

# Remove a short-lived alternate module ID so both overlays cannot run together.
for stale in "/data/adb/modules/$OLD_MODID" "/data/adb/modules_update/$OLD_MODID"; do
  [ -d "$stale" ] || continue
  case "$stale" in /data/adb/modules/$OLD_MODID|/data/adb/modules_update/$OLD_MODID) rm -rf "$stale" 2>/dev/null || true ;; esac
done

set_perm_recursive "$MODPATH" 0 0 0755 0644 u:object_r:system_file:s0
for script in service.sh post-fs-data.sh uninstall.sh action.sh; do
  set_perm "$MODPATH/$script" 0 0 0755 u:object_r:system_file:s0
done
set_perm_recursive "$MODPATH/tools" 0 0 0755 0755 u:object_r:system_file:s0
set_perm "$MODPATH/system/priv-app/DocumentsUI/DocumentsUI.apk" 0 0 0644 u:object_r:system_file:s0
set_perm "$MODPATH/system/priv-app/TS18RootFileProvider/TS18RootFileProvider.apk" 0 0 0644 u:object_r:system_file:s0

clean_work
note "- Installed. Reboot is required."
note "- After reboot picker intents should resolve to DocumentsUI."
note "- Internal storage is always shown; root-only content remains a separate source."
note "- Magisk Action creates diagnostics in Download/TS18-SAF-Diagnostics."
