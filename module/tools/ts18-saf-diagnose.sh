#!/system/bin/sh
# Quick wrapper around v0.8.0 deep diagnostics.
DIR=${0%/*}
MODE=${1:-quick}
exec sh "$DIR/ts18-saf-deepdiag.sh" "$MODE"
