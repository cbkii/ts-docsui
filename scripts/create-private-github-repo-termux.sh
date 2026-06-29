#!/usr/bin/env bash
# Create or update a private GitHub repository from the TS18 SAF Magisk module scaffold.
# Designed for native Android Termux, but also works on normal Linux shells.
# No blanket set -euo pipefail: each command has an explicit failure policy.

SCRIPT_NAME=${0##*/}
SCRIPT_DIR=$(
  cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 &&
  pwd -P
) || {
  printf '[ERROR] Cannot determine script directory.\n' >&2
  exit 1
}

# ---- Editable constants -------------------------------------------------
# Put the repo scaffold ZIP beside this script, or edit this path directly.
# Environment override is supported, for example:
#   SCAFFOLD_ZIP_PATH=/sdcard/Download/ts18-saf-magisk-module-repo-v0.8.0.zip ./ts18-saf-create-private-github-repo-termux.sh cbkii/ts18-saf-magisk-module
SCAFFOLD_ZIP_PATH=${SCAFFOLD_ZIP_PATH:-"${SCRIPT_DIR}/ts18-saf-magisk-module-repo-v0.8.0.zip"}

# Where the scaffold is unpacked when the current directory is not already a scaffold repo.
WORK_PARENT=${WORK_PARENT:-"${HOME}/repos"}

# Default branch for a freshly initialised repo.
DEFAULT_BRANCH=${DEFAULT_BRANCH:-main}
# ------------------------------------------------------------------------

TMP_ROOT="${HOME}/tmp/${SCRIPT_NAME}.$$"
WARNINGS=0
ERRORS=0
PUSH_ATTEMPTED=0
PUSH_SUCCEEDED=0
REPO_SLUG=${1:-}
WORK_DIR=${WORK_DIR:-}
ACTIVE_WORK_DIR=''

log() { printf '[INFO] %s\n' "$*" >&2; }
warn() { WARNINGS=$((WARNINGS + 1)); printf '[WARN] %s\n' "$*" >&2; }
error() { ERRORS=$((ERRORS + 1)); printf '[ERROR] %s\n' "$*" >&2; }

print_summary() {
  local result=$1
  local branch='unknown'
  local head='unknown'
  branch=$(git branch --show-current 2>/dev/null || printf 'unknown')
  head=$(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')
  printf '\n========================================\n' >&2
  printf 'RESULT: %s\n' "$result" >&2
  printf 'Repository: %s\n' "${REPO_SLUG:-unknown}" >&2
  printf 'Scaffold ZIP: %s\n' "$SCAFFOLD_ZIP_PATH" >&2
  printf 'Work dir: %s\n' "${ACTIVE_WORK_DIR:-unknown}" >&2
  printf 'Branch: %s\n' "$branch" >&2
  printf 'HEAD:   %s\n' "$head" >&2
  printf 'Warnings: %d\n' "$WARNINGS" >&2
  printf 'Errors:   %d\n' "$ERRORS" >&2
  printf 'Push attempted: %d\n' "$PUSH_ATTEMPTED" >&2
  printf 'Push succeeded: %d\n' "$PUSH_SUCCEEDED" >&2
  printf '========================================\n' >&2
}

fail() { error "$*"; print_summary FAILED; exit 1; }

cleanup() {
  local rc=$?
  trap - EXIT INT TERM
  if [[ -n ${TMP_ROOT:-} && -d ${TMP_ROOT:-} ]]; then
    rm -rf -- "$TMP_ROOT" 2>/dev/null || :
  fi
  exit "$rc"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

run_required() {
  local seconds=$1
  shift
  log "RUN(required, ${seconds}): $*"
  if command -v timeout >/dev/null 2>&1; then
    timeout --foreground "$seconds" "$@"
  else
    warn "timeout unavailable; running required command without outer timeout: $*"
    "$@"
  fi
  local rc=$?
  if ((rc != 0)); then
    error "Required command failed with status ${rc}: $*"
    return "$rc"
  fi
  return 0
}

run_optional() {
  local seconds=$1
  shift
  log "RUN(optional, ${seconds}): $*"
  if command -v timeout >/dev/null 2>&1; then
    timeout --foreground "$seconds" "$@" || {
      warn "Optional command failed or timed out: $*"
      return 0
    }
  else
    warn "timeout unavailable; skipping optional command: $*"
    return 0
  fi
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || fail "Required command missing: $1"; }

find_python() {
  if command -v python3 >/dev/null 2>&1; then printf 'python3\n'; return 0; fi
  if command -v python >/dev/null 2>&1; then printf 'python\n'; return 0; fi
  return 1
}

normalise_slug() {
  local raw=$1
  local owner repo
  if [[ $raw == */* ]]; then
    owner=${raw%%/*}
    repo=${raw#*/}
  else
    owner=$(gh api user --jq .login 2>/dev/null) || return 1
    repo=$raw
  fi
  [[ -n $owner && -n $repo ]] || return 1
  case "$owner/$repo" in
    *' '*|*'..'*|/*|*/|*//*) return 1 ;;
  esac
  printf '%s/%s\n' "$owner" "$repo"
}

repo_name_from_slug() {
  local slug=$1
  printf '%s\n' "${slug##*/}"
}

safe_extract_zip_with_python() {
  local python_bin=$1
  local zip_path=$2
  local out_dir=$3

  log "RUN(required, 120s): $python_bin safe_extract_zip $zip_path $out_dir"

  if command -v timeout >/dev/null 2>&1; then
    timeout --foreground 120s "$python_bin" - "$zip_path" "$out_dir" <<'PY'
from __future__ import annotations

import sys
import zipfile
from pathlib import PurePosixPath

zip_path = sys.argv[1]
out_dir = sys.argv[2]

with zipfile.ZipFile(zip_path) as zf:
    names = [name for name in zf.namelist() if name and not name.endswith('/')]
    if not names:
        raise SystemExit('STOP: scaffold zip has no files')

    for name in names:
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts:
            raise SystemExit(f'STOP: unsafe path in scaffold zip: {name}')

    zf.extractall(out_dir)
PY
  else
    warn "timeout unavailable; running scaffold extraction without outer timeout"
    "$python_bin" - "$zip_path" "$out_dir" <<'PY'
from __future__ import annotations

import sys
import zipfile
from pathlib import PurePosixPath

zip_path = sys.argv[1]
out_dir = sys.argv[2]

with zipfile.ZipFile(zip_path) as zf:
    names = [name for name in zf.namelist() if name and not name.endswith('/')]
    if not names:
        raise SystemExit('STOP: scaffold zip has no files')

    for name in names:
        path = PurePosixPath(name)
        if path.is_absolute() or '..' in path.parts:
            raise SystemExit(f'STOP: unsafe path in scaffold zip: {name}')

    zf.extractall(out_dir)
PY
  fi
}

resolve_extracted_scaffold_root() {
  local extract_dir=$1
  local found=''

  if [[ -f "$extract_dir/module/module.prop" ]]; then
    printf '%s\n' "$extract_dir"
    return 0
  fi

  while IFS= read -r -d '' candidate; do
    if [[ -f "$candidate/module/module.prop" ]]; then
      if [[ -n $found ]]; then
        error "More than one scaffold root found under: $extract_dir"
        return 1
      fi
      found=$candidate
    fi
  done < <(find "$extract_dir" -mindepth 1 -maxdepth 2 -type d -print0)

  [[ -n $found ]] || return 1
  printf '%s\n' "$found"
}

prepare_scaffold_worktree() {
  local repo_name=$1
  local extract_dir scaffold_root target_dir python_bin

  if [[ -f module/module.prop ]]; then
    ACTIVE_WORK_DIR=$(pwd -P)
    log "Using current directory as scaffold repo: $ACTIVE_WORK_DIR"
    return 0
  fi

  [[ -n $repo_name ]] || fail 'Cannot prepare scaffold: repo name is empty'
  [[ -f $SCAFFOLD_ZIP_PATH ]] || fail "Scaffold ZIP not found: $SCAFFOLD_ZIP_PATH"
  [[ -s $SCAFFOLD_ZIP_PATH ]] || fail "Scaffold ZIP is empty: $SCAFFOLD_ZIP_PATH"

  target_dir=${WORK_DIR:-"${WORK_PARENT}/${repo_name}"}
  case "$target_dir" in
    ''|/|.|..) fail "Unsafe WORK_DIR: ${target_dir:-<empty>}" ;;
  esac

  if [[ -e $target_dir && ! -d $target_dir ]]; then
    fail "Target work path exists but is not a directory: $target_dir"
  fi

  if [[ -d $target_dir && -f "$target_dir/module/module.prop" ]]; then
    cd "$target_dir" || fail "Cannot cd to existing work dir: $target_dir"
    ACTIVE_WORK_DIR=$(pwd -P)
    log "Using existing scaffold work dir: $ACTIVE_WORK_DIR"
    return 0
  fi

  if [[ -d $target_dir ]]; then
    if find "$target_dir" -mindepth 1 -maxdepth 1 | grep -q .; then
      fail "Target work dir is not empty and is not a scaffold repo: $target_dir"
    fi
  fi

  mkdir -p -- "$target_dir" || fail "Cannot create target work dir: $target_dir"
  extract_dir="${TMP_ROOT}/scaffold-extract"
  mkdir -p -- "$extract_dir" || fail "Cannot create extraction dir: $extract_dir"

  python_bin=$(find_python || true)
  if [[ -n $python_bin ]]; then
    safe_extract_zip_with_python "$python_bin" "$SCAFFOLD_ZIP_PATH" "$extract_dir" || fail 'Scaffold ZIP extraction failed'
  else
    need_cmd unzip
    run_required 120s unzip -q "$SCAFFOLD_ZIP_PATH" -d "$extract_dir" || fail 'Scaffold ZIP extraction failed'
  fi

  scaffold_root=$(resolve_extracted_scaffold_root "$extract_dir") || fail 'Extracted scaffold did not contain module/module.prop'
  run_required 120s cp -a "$scaffold_root"/. "$target_dir"/ || fail "Could not copy scaffold into: $target_dir"

  cd "$target_dir" || fail "Cannot cd to scaffold work dir: $target_dir"
  ACTIVE_WORK_DIR=$(pwd -P)
  log "Unpacked scaffold into: $ACTIVE_WORK_DIR"
}

main() {
  mkdir -p -- "$TMP_ROOT" || fail "Could not create temp root: $TMP_ROOT"

  export GIT_TERMINAL_PROMPT=0
  export GCM_INTERACTIVE=never
  export GIT_PAGER=cat
  export PAGER=cat

  log '[1/9] Preflight'
  need_cmd git
  need_cmd gh
  run_required 45s gh auth status || fail 'GitHub CLI is not authenticated. Run: gh auth login'

  if [[ -z $REPO_SLUG ]]; then
    REPO_SLUG=$(basename -- "$(pwd)")
    warn "No repo slug supplied; using current directory name: $REPO_SLUG"
  fi
  REPO_SLUG=$(normalise_slug "$REPO_SLUG") || fail "Invalid repo name/slug: ${1:-$REPO_SLUG}"
  repo_name=$(repo_name_from_slug "$REPO_SLUG")
  log "Target private repo: $REPO_SLUG"

  log '[2/9] Preparing scaffold worktree'
  prepare_scaffold_worktree "$repo_name"

  log '[3/9] Inspecting local Git state'
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || fail 'Cannot resolve Git repo root'
    cd "$repo_root" || fail "Cannot cd to repo root: $repo_root"
    ACTIVE_WORK_DIR=$(pwd -P)
  else
    run_required 30s git init -b "$DEFAULT_BRANCH" || fail 'git init failed'
  fi
  run_optional 20s git status --short

  log '[4/9] Validating scaffold locally where possible'
  if [[ ! -d module || ! -f module/module.prop ]]; then
    fail 'Expected module/module.prop after scaffold preparation.'
  fi
  PYTHON_BIN=$(find_python || true)
  if [[ -n ${PYTHON_BIN:-} ]]; then
    run_required 120s "$PYTHON_BIN" scripts/validate-module.py --module-dir module --expected-version v0.8.0 --expected-version-code 080 || fail 'Module validation failed'
    run_required 180s "$PYTHON_BIN" scripts/build-magisk-zip.py --module-dir module --out-dir dist || fail 'Local Magisk ZIP build failed'
  else
    warn 'python/python3 unavailable; skipping local module validation/build. GitHub Actions will validate.'
  fi

  log '[5/9] Creating private GitHub repo if needed'
  if gh repo view "$REPO_SLUG" >/dev/null 2>&1; then
    warn "GitHub repo already exists: $REPO_SLUG"
  else
    run_required 120s gh repo create "$REPO_SLUG" --private --description 'Private TS18 SAF DocumentsUI Magisk module development repo' || fail 'gh repo create failed'
  fi

  log '[6/9] Configuring origin remote'
  target_url="https://github.com/${REPO_SLUG}.git"
  origin_url=$(git remote get-url origin 2>/dev/null || true)
  if [[ -n $origin_url ]]; then
    case "$origin_url" in
      *"github.com/${REPO_SLUG}.git"|*"github.com:${REPO_SLUG}.git"|*"github.com/${REPO_SLUG}"|*"github.com:${REPO_SLUG}")
        log "origin already points at $REPO_SLUG"
        ;;
      *)
        fail "origin points elsewhere: $origin_url"
        ;;
    esac
  else
    run_required 30s git remote add origin "$target_url" || fail 'Could not add origin remote'
  fi

  current_branch=$(git branch --show-current 2>/dev/null || true)
  if [[ -z $current_branch ]]; then
    run_required 30s git checkout -B "$DEFAULT_BRANCH" || fail 'Could not create default branch'
    current_branch=$DEFAULT_BRANCH
  fi

  log '[7/9] Staging and committing scaffold'
  run_required 60s git add . || fail 'git add failed'
  if git diff --cached --quiet; then
    warn 'No staged changes to commit'
  else
    run_required 120s git commit -m 'Initial TS18 SAF Magisk module repo v0.8.0' || fail 'git commit failed'
  fi

  log '[8/9] Pushing current branch'
  PUSH_ATTEMPTED=1
  run_required 180s git push -u origin "HEAD:${current_branch}" || fail 'git push failed'
  PUSH_SUCCEEDED=1

  log '[9/9] Next manual release command'
  printf '\nRun a release after GitHub has indexed the workflow:\n' >&2
  printf '  gh workflow run release-magisk-module.yml --repo %s -f create_release=true -f expected_version=v0.8.0 -f expected_version_code=080\n' "$REPO_SLUG" >&2

  print_summary SUCCESS
}

main "$@"
