#!/system/bin/sh
# Launch the bundled system picker explicitly for manual TS18 testing.
# Usage: ts18-saf-launch.sh [internal|root|plain|files|open|get]
MODE=${1:-internal}
LOG=/storage/emulated/0/Download/TS18-SAF-launch.log
PICKER=com.android.documentsui/.picker.PickActivity
mkdir -p /storage/emulated/0/Download 2>/dev/null || true

launch_tree() {
  initial=$1
  am force-stop com.android.documentsui >/dev/null 2>&1 || true
  if [ -n "$initial" ]; then
    am start -n "$PICKER" -a android.intent.action.OPEN_DOCUMENT_TREE \
      --eu android.provider.extra.INITIAL_URI "$initial" \
      --ez android.provider.extra.SHOW_ADVANCED true \
      --ez android.content.extra.SHOW_ADVANCED true \
      --ez android.provider.extra.SHOW_FILESIZE true
  else
    am start -n "$PICKER" -a android.intent.action.OPEN_DOCUMENT_TREE \
      --ez android.provider.extra.SHOW_ADVANCED true \
      --ez android.content.extra.SHOW_ADVANCED true \
      --ez android.provider.extra.SHOW_FILESIZE true
  fi
}

launch_picker_action() {
  action=$1
  shift
  am force-stop com.android.documentsui >/dev/null 2>&1 || true
  am start -n "$PICKER" -a "$action" "$@"
}

{
  echo "===== TS18 picker launch $(date '+%F %T %z' 2>/dev/null || echo unknown) mode=$MODE ====="
  for action in android.intent.action.OPEN_DOCUMENT_TREE android.intent.action.OPEN_DOCUMENT android.intent.action.GET_CONTENT; do
    echo "--- resolver $action ---"
    cmd package resolve-activity --brief --user 0 -a "$action" 2>&1 || \
      cmd package resolve-activity --brief -a "$action" 2>&1 || true
  done
  echo "--- explicit launch ---"
  case "$MODE" in
    internal)
      launch_tree 'content://com.android.externalstorage.documents/root/primary'
      ;;
    root)
      launch_tree 'content://com.cbkii.tsdocsui.root.documents/root/device'
      ;;
    plain)
      launch_tree ''
      ;;
    files)
      am force-stop com.android.documentsui >/dev/null 2>&1 || true
      am start -n com.android.documentsui/.files.FilesActivity \
        --ez android.provider.extra.SHOW_ADVANCED true \
        --ez android.content.extra.SHOW_ADVANCED true
      ;;
    open)
      launch_picker_action android.intent.action.OPEN_DOCUMENT \
        -c android.intent.category.OPENABLE -t '*/*'
      ;;
    get)
      launch_picker_action android.intent.action.GET_CONTENT -t '*/*'
      ;;
    *)
      echo "Unknown mode: $MODE"
      exit 2
      ;;
  esac
} >> "$LOG" 2>&1
exit 0
