#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# upload.sh - Upload repo arch dir to R2 via rclone or aws cli
# Usage: REPO_ROOT=/abs/path ARCH=x86_64 ./upload.sh [--dry-run] [--remote <rclone-remote>]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/utils.sh"
source "$ROOT_DIR/config.sh"

DRY_RUN=false
RCLONE_REMOTE="${RCLONE_REMOTE:-r2}"
while [[ $# -gt 0 ]]; do
  case "$1" in
  --dry-run)
    DRY_RUN=true
    shift
    ;;
  --remote)
    shift
    RCLONE_REMOTE="$1"
    shift
    ;;
  --help)
    cat <<EOF
Usage: $(basename "$0") [--dry-run] [--remote <rclone-remote>]
Uploads the repo arch dir to remote (rclone preferred), using R2_BUCKET and R2_ENDPOINT from config or env.
EOF
    exit 0
    ;;
  *) die "Unknown option: $1" ;;
  esac
done

REPO_DIR="${REPO_ROOT%/}/${ARCH}"
ensure_dir "$REPO_DIR"
require_cmds mkdir

log "Uploading $REPO_DIR (arch=$ARCH) to remote. rclone remote: $RCLONE_REMOTE"

if command -v rclone >/dev/null 2>&1; then
  TARGET="${RCLONE_REMOTE}:${R2_BUCKET}/${ARCH}/"
  if $DRY_RUN; then
    log "[DRY-RUN] rclone sync --dry-run --progress --create-empty-src-dirs --delete-after \"$REPO_DIR/\" \"$TARGET\""
  else
    rclone sync --progress --create-empty-src-dirs --delete-after "$REPO_DIR/" "$TARGET" || die "rclone sync failed"
  fi
  log "Upload via rclone complete."
  exit 0
fi

if command -v aws >/dev/null 2>&1; then
  if [[ -z "${R2_ENDPOINT:-}" ]]; then
    die "R2_ENDPOINT not set in config for aws fallback."
  fi
  TARGET="s3://${R2_BUCKET}/${ARCH}/"
  if $DRY_RUN; then
    log "[DRY-RUN] aws s3 sync --endpoint-url \"$R2_ENDPOINT\" \"$REPO_DIR/\" \"$TARGET\""
  else
    aws s3 sync "$REPO_DIR/" "$TARGET" --endpoint-url "$R2_ENDPOINT" || die "aws s3 sync failed"
  fi
  log "Upload via aws s3 complete."
  exit 0
fi

die "No upload tool found. Install rclone or aws CLI."
