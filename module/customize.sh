#!/system/bin/sh
# TS18 SAF DocsUI installer.
# Installer work is under /data/adb, with /storage/emulated/0 fallback only.

SKIPUNZIP=1
MODID="ts18_documentsui_saf_full"
WORKBASE="/data/adb/${MODID}.install"
STAGE="${WORKBASE}/stage"
LOGDIR="/data/adb/ts18-documentsui-saf/logs"
INSTALL_LOG="${LOGDIR}/install-v080.log"

ui_die() { abort "STOP: $1"; }
ui_note() { ui_print "$1"; }
ui_warn() { ui_print "! $1"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

choose_workbase() {
  mkdir -p /data/adb 2>/dev/null && return 0
  WORKBASE="/storage/emulated/0/${MODID}.install"
  STAGE="${WORKBASE}/stage"
  LOGDIR="/storage/emulated/0/ts18-documentsui-saf/logs"
  INSTALL_LOG="${LOGDIR}/install-v080.log"
  mkdir -p "$WORKBASE" 2>/dev/null || return 1
  return 0
}

run_unzip() {
  if have_cmd unzip && unzip "$@"; then return 0; fi
  if [ -x /data/adb/magisk/busybox ] && /data/adb/magisk/busybox unzip "$@"; then return 0; fi
  if have_cmd busybox && busybox unzip "$@"; then return 0; fi
  if have_cmd toybox && toybox unzip "$@"; then return 0; fi
  return 1
}

clean_owned_work() {
  case "$WORKBASE" in
    /data/adb/${MODID}.install|/storage/emulated/0/${MODID}.install) rm -rf "$WORKBASE" 2>/dev/null || true ;;
  esac
}

extract_file() {
  name="$1"; dest="$2"
  mkdir -p "$(dirname "$dest")" 2>/dev/null || return 1
  rm -f "$dest" 2>/dev/null || true
  run_unzip -p "$ZIPFILE" "$name" > "$dest" 2>>"$INSTALL_LOG" || return 1
  case "$name" in META-INF/*) return 0 ;; *) [ -s "$dest" ] ;; esac
}

extract_tree() {
  prefix="$1"
  mkdir -p "$STAGE" 2>/dev/null || return 1
  run_unzip -oq "$ZIPFILE" "${prefix}/*" -d "$STAGE" >>"$INSTALL_LOG" 2>&1 || return 1
  [ -d "$STAGE/$prefix" ] || return 1
  mkdir -p "$MODPATH" 2>/dev/null || return 1
  cp -af "$STAGE/$prefix" "$MODPATH/" >>"$INSTALL_LOG" 2>&1 || return 1
}

ui_note "- TS18 SAF v0.8.0 stable no-crash picker repair"
ui_note "- AOSP DocumentsUI + invalid TS18 provider removed/disabled"
ui_note "- Keep existing ExternalStorageProvider but hide broken advanced roots by default"
ui_note "- Installer work: /data/adb, fallback /storage/emulated/0"

[ "${MAGISK_VER_CODE:-0}" -ge 28100 ] || ui_die "Magisk 28.1+ required; detected ${MAGISK_VER_CODE:-unknown}"
SDK=$(getprop ro.build.version.sdk 2>/dev/null || echo unknown)
[ "$SDK" = 29 ] || ui_warn "Expected SDK 29 Android 10, detected $SDK"

choose_workbase || ui_die "Cannot create /data/adb or /storage/emulated/0 installer workspace"
mkdir -p "$LOGDIR" 2>/dev/null || true
: > "$INSTALL_LOG" 2>/dev/null || true
clean_owned_work
mkdir -p "$STAGE" "$LOGDIR" 2>/dev/null || ui_die "Cannot create staging directory: $STAGE"
: > "$INSTALL_LOG" 2>/dev/null || true

echo "zip=$ZIPFILE" >> "$INSTALL_LOG"
echo "modpath=$MODPATH" >> "$INSTALL_LOG"
echo "workbase=$WORKBASE" >> "$INSTALL_LOG"

case "$MODPATH" in
  /data/adb/modules/${MODID}|/data/adb/modules_update/${MODID}|/sbin/.magisk/modules/${MODID}|/dev/*/${MODID}) rm -rf "$MODPATH"/* 2>/dev/null || true ;;
  *) ui_warn "Unexpected MODPATH: $MODPATH; not clearing existing files" ;;
esac
mkdir -p "$MODPATH" 2>/dev/null || ui_die "Cannot create MODPATH"

for f in module.prop config.default customize.sh service.sh post-fs-data.sh uninstall.sh action.sh README.md; do
  ui_note "- extracting $f"
  extract_file "$f" "$MODPATH/$f" || ui_die "Failed to extract $f"
done
for d in system tools; do
  ui_note "- extracting $d"
  extract_tree "$d" || ui_die "Failed to extract $d"
done

mkdir -p /data/adb 2>/dev/null || true
if [ -f /data/adb/ts18-documentsui-saf.conf ]; then
  cp -f /data/adb/ts18-documentsui-saf.conf "/data/adb/ts18-documentsui-saf.conf.pre-v080.$(date +%Y%m%d%H%M%S 2>/dev/null || echo backup)" 2>/dev/null || true
fi
cp -f "$MODPATH/config.default" /data/adb/ts18-documentsui-saf.conf 2>/dev/null || ui_warn "Could not write /data/adb config"
chmod 0644 /data/adb/ts18-documentsui-saf.conf 2>/dev/null || true

[ -s "$MODPATH/system/priv-app/DocumentsUI/DocumentsUI.apk" ] || ui_die "DocumentsUI.apk missing/empty"
[ ! -e "$MODPATH/system/priv-app/TS18LocalDocumentsProvider/TS18LocalDocumentsProvider.apk" ] || ui_die "Unexpected invalid TS18LocalDocumentsProvider payload present"
[ ! -e "$MODPATH/system/priv-app/ExternalStorageProvider/ExternalStorageProvider.apk" ] || ui_die "Unexpected ExternalStorageProvider payload present"
[ -f "$MODPATH/tools/ts18-saf-deepdiag.sh" ] || ui_die "Deep diagnostics missing"

set_perm_recursive "$MODPATH" 0 0 0755 0644 u:object_r:system_file:s0
for s in service.sh post-fs-data.sh uninstall.sh action.sh; do set_perm "$MODPATH/$s" 0 0 0755 u:object_r:system_file:s0; done
set_perm_recursive "$MODPATH/tools" 0 0 0755 0755 u:object_r:system_file:s0
set_perm "$MODPATH/system/priv-app/DocumentsUI/DocumentsUI.apk" 0 0 0644 u:object_r:system_file:s0

clean_owned_work
ui_note "- Installed v0.8.0. Reboot required."
ui_note "- Manual diagnostics: Magisk Action or tools/ts18-saf-deepdiag.sh"
