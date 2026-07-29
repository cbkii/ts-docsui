#!/system/bin/sh
MODDIR=${0%/*}
OUT=/storage/emulated/0/Download/TS18-SAF-Diagnostics
mkdir -p "$OUT" 2>/dev/null || true
printf '%s\n' 'TS18 Full File Picker diagnostics'
printf 'Output: %s\n' "$OUT"
printf '%s\n' 'Running the bounded, private-first exact-device evidence collector.'
printf '%s\n' 'For staged acceptance use modes such as boot1, boot2, after-grant, root-denied, usb-inserted and rollback.'
if [ -x "$MODDIR/tools/ts18-saf-evidence-v2.sh" ]; then
  sh "$MODDIR/tools/ts18-saf-evidence-v2.sh" full
elif [ -x "$MODDIR/tools/ts18-saf-deepdiag.sh" ]; then
  printf '%s\n' 'WARN: v2 collector is missing; running the legacy collector.'
  sh "$MODDIR/tools/ts18-saf-deepdiag.sh" full
else
  printf '%s\n' 'STOP: diagnostics scripts are missing'
  exit 1
fi
