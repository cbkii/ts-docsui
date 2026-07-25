#!/system/bin/sh
# Root filesystem helper for the TS18 DocumentsProvider.
# Arguments after the action are base64-encoded UTF-8 strings.

BB=/data/adb/magisk/busybox
[ -x "$BB" ] || BB="$(command -v busybox 2>/dev/null)"
[ -x "$BB" ] || {
  echo "Magisk BusyBox is unavailable" >&2
  exit 127
}

ACTION=${1:-}
shift 2>/dev/null || true

b64_decode() {
  printf '%s' "$1" | "$BB" base64 -d 2>/dev/null
}

b64_encode() {
  printf '%s' "$1" | "$BB" base64 2>/dev/null | "$BB" tr -d '\n\r'
}

fail() {
  echo "$*" >&2
  exit 1
}

path_from_arg() {
  value=$(b64_decode "${1:-}") || return 1
  [ -n "$value" ] || [ "${1:-}" = "Lw==" ] || return 1
  printf '%s' "$value"
}

safe_name() {
  case "$1" in
    ''|.|..|*/*) return 1 ;;
    *) return 0 ;;
  esac
}

shared_stage_path() {
  case "$1" in /storage/emulated/0/*) return 0 ;; *) return 1 ;; esac
}

emit_record() {
  p=$1
  [ -e "$p" ] || [ -L "$p" ] || return 1
  if [ -d "$p" ]; then
    kind=d
  elif [ -f "$p" ]; then
    kind=f
  elif [ -L "$p" ]; then
    kind=l
  else
    kind=o
  fi
  size=$($BB stat -c '%s' "$p" 2>/dev/null || echo 0)
  mtime=$($BB stat -c '%Y' "$p" 2>/dev/null || echo 0)
  mode=$($BB stat -c '%a' "$p" 2>/dev/null || echo 0)
  if [ "$p" = / ]; then
    name=/
  else
    name=${p##*/}
  fi
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$kind" "$size" "$mtime" "$mode" "$(b64_encode "$name")" "$(b64_encode "$p")"
}

protected_anchor() {
  case "$1" in
    /|/data|/system|/vendor|/product|/system_ext|/odm|/proc|/sys|/dev|/storage|/mnt) return 0 ;;
    *) return 1 ;;
  esac
}

case "$ACTION" in
  ping)
    echo "OK uid=$(id -u 2>/dev/null || echo unknown)"
    ;;

  stat)
    path=$(path_from_arg "${1:-}") || fail "Invalid path"
    emit_record "$path" || fail "Path not found: $path"
    ;;

  _stat_raw)
    # Internal action used only by the NUL-safe xargs loop below.
    emit_record "${1:-}" || exit 0
    ;;

  list)
    path=$(path_from_arg "${1:-}") || fail "Invalid path"
    [ -d "$path" ] || fail "Not a directory: $path"
    # NUL-delimited traversal preserves spaces, tabs and newlines in names.
    "$BB" find "$path" -mindepth 1 -maxdepth 1 -print0 2>/dev/null |
      "$BB" xargs -0 -r -n 1 "$BB" sh "$0" _stat_raw
    ;;

  df)
    path=$(path_from_arg "${1:-}") || fail "Invalid path"
    blocks=$($BB df -Pk "$path" 2>/dev/null | $BB awk 'NR==2 {print $4}')
    case "$blocks" in ''|*[!0-9]*) echo -1 ;; *) echo $((blocks * 1024)) ;; esac
    ;;

  create)
    parent=$(path_from_arg "${1:-}") || fail "Invalid parent"
    name=$(path_from_arg "${2:-}") || fail "Invalid name"
    kind=$(path_from_arg "${3:-}") || fail "Invalid type"
    safe_name "$name" || fail "Unsafe name"
    [ -d "$parent" ] || fail "Parent is not a directory"
    target=${parent%/}/$name
    [ ! -e "$target" ] && [ ! -L "$target" ] || fail "Target already exists"
    if [ "$kind" = dir ]; then
      "$BB" mkdir -p "$target" || fail "mkdir failed"
    else
      : > "$target" || fail "create failed"
    fi
    b64_encode "$target"
    echo
    ;;

  rename)
    path=$(path_from_arg "${1:-}") || fail "Invalid path"
    name=$(path_from_arg "${2:-}") || fail "Invalid name"
    safe_name "$name" || fail "Unsafe name"
    protected_anchor "$path" && fail "Refusing to rename protected root"
    parent=${path%/*}
    [ -n "$parent" ] || parent=/
    target=${parent%/}/$name
    [ ! -e "$target" ] && [ ! -L "$target" ] || fail "Target already exists"
    "$BB" mv "$path" "$target" || fail "rename failed"
    b64_encode "$target"
    echo
    ;;

  delete)
    path=$(path_from_arg "${1:-}") || fail "Invalid path"
    protected_anchor "$path" && fail "Refusing to delete protected root"
    [ -e "$path" ] || [ -L "$path" ] || exit 0
    "$BB" rm -rf "$path" || fail "delete failed"
    ;;

  copy)
    source=$(path_from_arg "${1:-}") || fail "Invalid source"
    target_parent=$(path_from_arg "${2:-}") || fail "Invalid target parent"
    [ -e "$source" ] || [ -L "$source" ] || fail "Source is missing"
    [ -d "$target_parent" ] || fail "Target parent is not a directory"
    name=${source##*/}
    target=${target_parent%/}/$name
    [ ! -e "$target" ] && [ ! -L "$target" ] || fail "Target already exists"
    "$BB" cp -a "$source" "$target" || fail "copy failed"
    ;;

  move)
    source=$(path_from_arg "${1:-}") || fail "Invalid source"
    target_parent=$(path_from_arg "${2:-}") || fail "Invalid target parent"
    protected_anchor "$source" && fail "Refusing to move protected root"
    [ -d "$target_parent" ] || fail "Target parent is not a directory"
    name=${source##*/}
    target=${target_parent%/}/$name
    [ ! -e "$target" ] && [ ! -L "$target" ] || fail "Target already exists"
    "$BB" mv "$source" "$target" || fail "move failed"
    b64_encode "$target"
    echo
    ;;

  copyout)
    source=$(path_from_arg "${1:-}") || fail "Invalid source"
    destination=$(path_from_arg "${2:-}") || fail "Invalid destination"
    owner=$(path_from_arg "${3:-}") || fail "Invalid owner"
    case "$owner" in ''|*[!0-9]*) fail "Owner UID is not numeric" ;; esac
    shared_stage_path "$destination" || fail "Staging destination must be under /storage/emulated/0"
    [ -e "$source" ] || [ -L "$source" ] || fail "Source is missing"
    parent=${destination%/*}
    [ -n "$parent" ] || parent=/
    "$BB" mkdir -p "$parent" || fail "Cannot create staging parent"
    "$BB" cp -f "$source" "$destination" || fail "copyout failed"
    # Shared storage may reject POSIX owner or mode changes; access is granted by sdcardfs/FUSE.
    "$BB" chown "$owner:$owner" "$destination" 2>/dev/null || true
    "$BB" chmod 0666 "$destination" 2>/dev/null || true
    ;;

  copyin)
    source=$(path_from_arg "${1:-}") || fail "Invalid source"
    destination=$(path_from_arg "${2:-}") || fail "Invalid destination"
    shared_stage_path "$source" || fail "Staged source must be under /storage/emulated/0"
    [ -f "$source" ] || fail "Staged source is missing"
    if [ -e "$destination" ] && [ ! -d "$destination" ]; then
      # Truncate and rewrite the existing inode to preserve owner and mode.
      : > "$destination" || fail "Cannot truncate destination"
      "$BB" cat "$source" > "$destination" || fail "copyin failed"
    else
      parent=${destination%/*}
      [ -n "$parent" ] || parent=/
      [ -d "$parent" ] || fail "Destination parent is missing"
      "$BB" cp -f "$source" "$destination" || fail "copyin failed"
      "$BB" chmod 0666 "$destination" 2>/dev/null || true
    fi
    ;;

  stream-read)
    path=$(path_from_arg "${1:-}") || fail "Invalid path"
    [ -e "$path" ] || [ -L "$path" ] || fail "Path is missing"
    "$BB" cat "$path"
    ;;

  *)
    fail "Unknown action: $ACTION"
    ;;
esac
