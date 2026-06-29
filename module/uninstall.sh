#!/system/bin/sh
LOG=/data/adb/ts18-documentsui-saf/logs/uninstall-v080.log
mkdir -p /data/adb/ts18-documentsui-saf/logs 2>/dev/null || true
{
  echo "===== uninstall TS18 SAF v0.8.0 $(date '+%F %T %z' 2>/dev/null || echo unknown) ====="
  echo "Module removed; reboot required."
  echo "Attempting to re-enable AppManager ActivityInterceptor if present."
    pm enable --user 0 io.github.muntashirakon.AppManager/.intercept.ActivityInterceptor 2>&1 || true
  echo "Config remains at /data/adb/ts18-documentsui-saf.conf for audit; delete manually for a clean reinstall."
} >> "$LOG" 2>&1
exit 0
