#!/system/bin/sh
# Run the same bounded collector used by the Magisk Action button.
DIR=${0%/*}
MODE=${1:-quick}
exec sh "$DIR/ts18-saf-deepdiag.sh" "$MODE"
