#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# remove.sh - remove all files for a package name
# Usage: REPO_ROOT=/abs/path ARCH=x86_64 ./remove.sh <pkgname> [--regen] [--dry-run]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/utils.sh"
source "$ROOT_DIR/config.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <pkgname> [--regen] [--dry-run]"
  exit 1
fi

PKGNAME="$1"
shift
REGEN=false
DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
  --regen)
    REGEN=true
    shift
    ;;
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  --help)
    echo "Usage: $(basename "$0") <pkgname> [--regen] [--dry-run]"
    exit 0
    ;;
  *) die "Unknown option: $1" ;;
  esac
done

REPO_DIR="${REPO_ROOT%/}/${ARCH}"
ensure_dir "$REPO_DIR"
require_cmds pacman

removed=false
shopt -s nullglob
for f in "$REPO_DIR"/*.pkg.*; do
  info="$(pacman -Qp "$f" 2>/dev/null || true)"
  [[ -z "$info" ]] && continue
  name="$(printf '%s' "$info" | awk '{print $1}')"
  if [[ "$name" == "$PKGNAME" ]]; then
    if $DRY_RUN; then
      log "[DRY-RUN] Would remove: $f"
      [[ -f "${f}.sig" ]] && log "[DRY-RUN] Would remove: ${f}.sig"
    else
      rm -f -- "$f"
      [[ -f "${f}.sig" ]] && rm -f -- "${f}.sig"
      log "Removed: $f"
      removed=true
    fi
  fi
done
shopt -u nullglob

if ! $removed; then
  warn "No files removed for package: $PKGNAME"
fi

if $REGEN; then
  if $DRY_RUN; then
    log "[DRY-RUN] Would run gen_db.sh"
  else
    "$SCRIPT_DIR/gen_db.sh"
  fi
fi
