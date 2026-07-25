#!/system/bin/sh
# Early preparation for TS18 shared storage. No diagnostics are collected here.

STATE_DIR=/data/adb/ts18-documentsui-saf
LOGDIR=$STATE_DIR/logs
LOG=$LOGDIR/post-fs-data-v100.log
mkdir -p "$LOGDIR" 2>/dev/null || exit 0

{
  echo "===== TS18 Full File Picker v1.0.0 $(date '+%F %T %z' 2>/dev/null || echo unknown) ====="
  if [ -d /data/media ]; then
    mkdir -p /data/media/0 2>/dev/null || true
    chown 1023:1023 /data/media/0 2>/dev/null || true
    chmod 0775 /data/media/0 2>/dev/null || true
    for folder in Alarms Audiobooks DCIM Documents Download Movies Music Notifications Pictures Podcasts Ringtones; do
      mkdir -p "/data/media/0/$folder" 2>/dev/null || true
      chown 1023:1023 "/data/media/0/$folder" 2>/dev/null || true
      chmod 0775 "/data/media/0/$folder" 2>/dev/null || true
    done
    restorecon -RF /data/media/0 >/dev/null 2>&1 || true
    echo "prepared /data/media/0"
  fi
} >> "$LOG" 2>&1
exit 0
