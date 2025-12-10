#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# clean.sh - keep last N versions of each package
# Usage: REPO_ROOT=/abs/path ARCH=x86_64 ./clean.sh [--keep N] [--dry-run]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/utils.sh"
source "$ROOT_DIR/config.sh"

KEEP="${KEEP_VERSIONS:-3}"
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
  --keep)
    shift
    KEEP="$1"
    shift
    ;;
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  --help)
    cat <<EOF
Usage: $(basename "$0") [--keep N] [--dry-run]
Keeps the N most recent package files per package name.
EOF
    exit 0
    ;;
  *) die "Unknown option: $1" ;;
  esac
done

REPO_DIR="${REPO_ROOT%/}/${ARCH}"
ensure_dir "$REPO_DIR"
require_cmds pacman

log "Cleaning repo: keep last $KEEP versions per package in $REPO_DIR"

declare -A lists
shopt -s nullglob
for f in "$REPO_DIR"/*.pkg.*; do
  info="$(pacman -Qp "$f" 2>/dev/null || true)"
  [[ -z "$info" ]] && continue
  name="$(printf '%s' "$info" | awk '{print $1}')"
  lists["$name"]+="$f|"
done
shopt -u nullglob

for pkg in "${!lists[@]}"; do
  IFS='|' read -r -a arr <<<"${lists[$pkg]}"
  # filter empty
  tmp=()
  for e in "${arr[@]}"; do [[ -n "$e" ]] && tmp+=("$e"); done
  arr=("${tmp[@]}")
  # sort newest first by mtime
  IFS=$'\n' sorted=($(ls -1t "${arr[@]}" 2>/dev/null || true))
  unset IFS
  total=${#sorted[@]}
  if ((total <= KEEP)); then
    log "Package $pkg has $total versions — nothing to remove."
    continue
  fi
  for ((i = KEEP; i < total; i++)); do
    f="${sorted[$i]}"
    if $DRY_RUN; then
      log "[DRY-RUN] Would remove: $f"
      [[ -f "${f}.sig" ]] && log "[DRY-RUN] Would remove: ${f}.sig"
    else
      log "Removing old package: $f"
      rm -f -- "$f"
      [[ -f "${f}.sig" ]] && rm -f -- "${f}.sig"
    fi
  done
done

log "Cleaning complete."
