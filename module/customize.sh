#!/system/bin/sh
# ts-docsui installer for Magisk 28+ on TS18 Android 10 / API 29.
# Staging and logs stay under shared Download storage, not /data/adb.

SKIPUNZIP=1
MODID=ts-docsui
OUTPUT_ROOT=/storage/emulated/0/Download/ts-docsui
WORKBASE=$OUTPUT_ROOT/.install
STAGE=$WORKBASE/stage
STATE_DIR=/data/adb/ts-docsui
INSTALL_LOG=$OUTPUT_ROOT/logs/install.log
CFG=/data/adb/ts-docsui.conf
MODULE_VERSION=unknown
MODULE_VERSION_CODE=unknown

note() { ui_print "$1"; }
warn() { ui_print "! $1"; }
stop_install() { abort "STOP: $1"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

run_unzip() {
  if have_cmd unzip && unzip "$@"; then return 0; fi
  if [ -x /data/adb/magisk/busybox ] && /data/adb/magisk/busybox unzip "$@"; then return 0; fi
  if have_cmd busybox && busybox unzip "$@"; then return 0; fi
  if have_cmd toybox && toybox unzip "$@"; then return 0; fi
  return 1
}

zip_has() {
  run_unzip -l "$ZIPFILE" "$1" 2>/dev/null | grep -Fq "$1"
}

clean_work() {
  case "$WORKBASE" in
    /storage/emulated/0/Download/ts-docsui/.install)
      rm -rf "$WORKBASE" 2>/dev/null || true
      ;;
  esac
}

extract_file() {
  source_name=$1
  destination=$2
  parent=$(dirname "$destination")
  mkdir -p "$parent" 2>/dev/null || return 1
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

install_config() {
  [ -f "$MODPATH/config.default" ] || return 1
  mkdir -p /data/adb 2>/dev/null || return 1
  if [ -f "$CFG" ]; then
    note "- keeping existing runtime config: $CFG"
    return 0
  fi
  cp -f "$MODPATH/config.default" "$CFG" 2>/dev/null || return 1
  chmod 0644 "$CFG" 2>/dev/null || warn "Could not set runtime config mode"
}

note "- ts-docsui"
note "- Android 10 file picker and root-provider integration for TS18"
note "- Installer work and logs: $OUTPUT_ROOT"

[ "${MAGISK_VER_CODE:-0}" -ge 28000 ] || stop_install "Magisk 28 or newer is required"
SDK=$(getprop ro.build.version.sdk 2>/dev/null || echo unknown)
[ "$SDK" = 29 ] || warn "Designed for Android 10 / SDK 29; detected SDK $SDK"

mkdir -p "$OUTPUT_ROOT/logs" "$STATE_DIR" 2>/dev/null || stop_install "Cannot create Download output and minimal state directories"
clean_work
mkdir -p "$STAGE" 2>/dev/null || stop_install "Cannot create installer staging under Download"
: > "$INSTALL_LOG" 2>/dev/null || stop_install "Cannot create installer log under Download"

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
    stop_install "Unexpected module path: $MODPATH"
    ;;
esac
mkdir -p "$MODPATH" 2>/dev/null || stop_install "Cannot create module directory"

for file in module.prop config.default customize.sh service.sh post-fs-data.sh uninstall.sh README.md; do
  note "- extracting $file"
  extract_file "$file" "$MODPATH/$file" || stop_install "Failed to extract $file"
done

if zip_has action.sh; then
  note "- extracting debug action"
  extract_file action.sh "$MODPATH/action.sh" || stop_install "Failed to extract action.sh"
fi

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
install_config || stop_install "Could not initialise $CFG"

set_perm_recursive "$MODPATH" 0 0 0755 0644 u:object_r:system_file:s0
for script in service.sh post-fs-data.sh uninstall.sh; do
  set_perm "$MODPATH/$script" 0 0 0755 u:object_r:system_file:s0
done
[ ! -f "$MODPATH/action.sh" ] || set_perm "$MODPATH/action.sh" 0 0 0755 u:object_r:system_file:s0
set_perm_recursive "$MODPATH/tools" 0 0 0755 0755 u:object_r:system_file:s0
set_perm "$MODPATH/system/priv-app/DocumentsUI/DocumentsUI.apk" 0 0 0644 u:object_r:system_file:s0
set_perm "$MODPATH/system/priv-app/TS18RootFileProvider/TS18RootFileProvider.apk" 0 0 0644 u:object_r:system_file:s0

if [ -f "$MODPATH/tools/ts18-saf-deepdiag.sh" ]; then
  note "- Debug variant installed; Magisk Action exports diagnostics under Download/ts-docsui/diagnostics"
else
  note "- Final variant installed; diagnostic collectors are not included"
fi

clean_work
note "- Installed. Reboot is required."
note "- Internal storage remains the stock Android provider; root-only paths use the separate root provider."
