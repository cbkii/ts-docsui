#!/system/bin/sh
MODDIR=${0%/*}
OUT=/storage/emulated/0/Download/TS18-SAF-Diagnostics
mkdir -p "$OUT" 2>/dev/null || true
printf '%s\n' 'TS18 Full File Picker diagnostics'
printf 'Output: %s\n' "$OUT"
printf '%s\n' 'Running a full, bounded, private-first capture.'
printf '%s\n' 'For staged device acceptance use tools/ts18-saf-deepdiag.sh with modes such as boot1, boot2, after-grant, root-denied, usb-inserted and rollback.'
if [ -x "$MODDIR/tools/ts18-saf-deepdiag.sh" ]; then
  sh "$MODDIR/tools/ts18-saf-deepdiag.sh" full
else
  printf '%s\n' 'STOP: diagnostics script is missing'
  exit 1
fi
