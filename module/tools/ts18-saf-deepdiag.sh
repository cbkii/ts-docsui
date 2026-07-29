#!/system/bin/sh
# Compatibility entry point retained for older instructions and installed shortcuts.
# The v2 collector is the single maintained diagnostic implementation.

SCRIPT_DIR=${0%/*}
COLLECTOR=$SCRIPT_DIR/ts18-saf-evidence-v2.sh
MODE=${1:-full}

if [ ! -x "$COLLECTOR" ]; then
  printf 'STOP: v2 evidence collector is missing: %s\n' "$COLLECTOR" >&2
  exit 1
fi

exec sh "$COLLECTOR" "$MODE"
