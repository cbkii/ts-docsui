#!/system/bin/sh
MODDIR=${0%/*}
OUT=/storage/emulated/0/Download/ts-docsui/diagnostics
mkdir -p "$OUT" 2>/dev/null || {
  echo "STOP: cannot create $OUT"
  exit 1
}
printf '%s\n' 'ts-docsui debug diagnostics'
printf 'Output: %s\n' "$OUT"
[ -x "$MODDIR/tools/ts18-saf-deepdiag.sh" ] || {
  echo 'STOP: diagnostic collector is missing'
  exit 1
}
exec sh "$MODDIR/tools/ts18-saf-deepdiag.sh" full
