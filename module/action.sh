#!/system/bin/sh
MODDIR=${0%/*}
OUT=/storage/emulated/0/Download/TS18-SAF-Diagnostics
mkdir -p "$OUT" 2>/dev/null || true
echo "TS18 Full File Picker diagnostics"
echo "Output: $OUT"
if [ -x "$MODDIR/tools/ts18-saf-deepdiag.sh" ]; then
  sh "$MODDIR/tools/ts18-saf-deepdiag.sh" full
else
  echo "STOP: diagnostics script is missing"
  exit 1
fi
