#!/system/bin/sh
MODDIR=${0%/*}
OUT=/storage/emulated/0/Download/TS18-SAF-Diagnostics
mkdir -p "$OUT" 2>/dev/null || true
echo "TS18 SAF v0.8.0 Action diagnostics"
echo "Output root: $OUT"
if [ -x "$MODDIR/tools/ts18-saf-deepdiag.sh" ]; then
  sh "$MODDIR/tools/ts18-saf-deepdiag.sh" full
else
  echo "STOP: missing tools/ts18-saf-deepdiag.sh"
  exit 1
fi
