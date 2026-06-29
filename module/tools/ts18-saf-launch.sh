#!/system/bin/sh
# Launch known SAF picker variants for TS18 testing. Usage: ts18-saf-launch.sh [ts18|plain|files|get|open|all]
MODE=${1:-ts18}
LOG=/storage/emulated/0/Download/TS18-SAF-launch.log
mkdir -p /storage/emulated/0/Download 2>/dev/null || true
launch_ts18() {
  am force-stop com.android.documentsui >/dev/null 2>&1 || true
  am start -a android.intent.action.OPEN_DOCUMENT_TREE     --eu android.provider.extra.INITIAL_URI 'content://com.ts18.safprovider.documents/root/ts18_internal'     --ez android.provider.extra.SHOW_ADVANCED true     --ez android.content.extra.SHOW_ADVANCED true     --ez android.provider.extra.SHOW_FILESIZE true     --ez android.content.extra.SHOW_FILESIZE true
}
launch_plain() { am force-stop com.android.documentsui >/dev/null 2>&1 || true; am start -a android.intent.action.OPEN_DOCUMENT_TREE --ez android.provider.extra.SHOW_ADVANCED true --ez android.content.extra.SHOW_ADVANCED true; }
launch_files() { am force-stop com.android.documentsui >/dev/null 2>&1 || true; am start -n com.android.documentsui/.files.FilesActivity --ez android.provider.extra.SHOW_ADVANCED true --ez android.content.extra.SHOW_ADVANCED true; }
launch_get() { am start -a android.intent.action.GET_CONTENT -t '*/*'; }
launch_open() { am start -a android.intent.action.OPEN_DOCUMENT -c android.intent.category.OPENABLE -t '*/*'; }
{
  echo "===== TS18 SAF launch $(date '+%F %T %z' 2>/dev/null || echo unknown) mode=$MODE ====="
  cmd package resolve-activity --brief -a android.intent.action.OPEN_DOCUMENT_TREE 2>&1 || true
  case "$MODE" in
    ts18) launch_ts18 ;;
    plain) launch_plain ;;
    files) launch_files ;;
    get) launch_get ;;
    open) launch_open ;;
    all) launch_ts18; sleep 2; launch_plain; sleep 2; launch_files ;;
    *) echo "Unknown mode: $MODE"; exit 2 ;;
  esac
} >> "$LOG" 2>&1
exit 0
