#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# update.sh - convenience wrapper to call add.sh and optionally regen DB
# Usage: REPO_ROOT=/abs/path ARCH=x86_64 ./update.sh <pkgdir or pkgfile> [--regen] [--no-sign]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/utils.sh"
source "$ROOT_DIR/config.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: $(basename "$0") <target> [--regen] [--no-sign]"
  exit 1
fi

TARGET="$1"
shift
REGEN=false
NO_SIGN_FLAG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --regen)
    REGEN=true
    shift
    ;;
  --no-sign)
    NO_SIGN_FLAG="--no-sign"
    shift
    ;;
  --help)
    echo "Usage: $(basename "$0") <target> [--regen] [--no-sign]"
    exit 0
    ;;
  *) die "Unknown arg: $1" ;;
  esac
done

log "Updating target: $TARGET"
"$SCRIPT_DIR/add.sh" $NO_SIGN_FLAG "$TARGET"

if $REGEN; then
  log "Regenerating DB..."
  "$SCRIPT_DIR/gen_db.sh"
fi

log "update.sh finished."
