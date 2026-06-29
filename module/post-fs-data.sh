#!/system/bin/sh
# TS18 SAF early shared-storage preparation.
# Bounded; no diagnostics output here.
CFG=/data/adb/ts18-documentsui-saf.conf
LOG=/data/adb/ts18-documentsui-saf/logs/post-fs-data-v080.log
TARGET_USER=0
FIX_CREATE_STANDARD_INTERNAL_DIRS=1
mkdir -p /data/adb/ts18-documentsui-saf/logs 2>/dev/null || true
[ -f "$CFG" ] && . "$CFG" 2>/dev/null || true
case "$TARGET_USER" in ''|*[!0-9]*) TARGET_USER=0 ;; esac
{
  echo "===== TS18 SAF v0.8.0 post-fs-data $(date '+%F %T %z' 2>/dev/null || echo unknown) ====="
  raw="/data/media/$TARGET_USER"
  if [ -d /data/media ]; then
    mkdir -p "$raw" 2>/dev/null || true
    chown 1023:1023 "$raw" 2>/dev/null || true
    chmod 0775 "$raw" 2>/dev/null || true
    if [ "${FIX_CREATE_STANDARD_INTERNAL_DIRS:-1}" != "0" ]; then
      for d in Alarms Audiobooks DCIM Documents Download Movies Music Notifications Pictures Podcasts Ringtones Photos; do
        mkdir -p "$raw/$d" 2>/dev/null || true
        chown 1023:1023 "$raw/$d" 2>/dev/null || true
        chmod 0775 "$raw/$d" 2>/dev/null || true
      done
    fi
    restorecon -RF "$raw" >/dev/null 2>&1 || true
    echo "prepared $raw"
  fi
} >> "$LOG" 2>&1
exit 0
