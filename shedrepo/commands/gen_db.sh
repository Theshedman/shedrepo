#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# gen_db.sh - regenerate shedos repo DB (robust: only real package files)
# Usage: REPO_ROOT=./output/repo ARCH=x86_64 ./gen_db.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=../utils.sh
source "$ROOT_DIR/utils.sh"
# shellcheck source=../config.sh
source "$ROOT_DIR/config.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0")

Regenerates repository database using repo-add and signs the DB with GPG.

Environment:
  REPO_ROOT - root directory of repo (default from config.sh)
  ARCH      - architecture (default from config.sh)
EOF
}

REPO_DIR="${REPO_ROOT%/}/${ARCH}"

require_cmds repo-add gpg pacman

ensure_dir "$REPO_DIR"
log "Generating DB for repo: $REPO_DIR"

# Collect candidate pkg files (may include .sig siblings)
shopt -s nullglob
candidates=("$REPO_DIR"/*.pkg.*)
shopt -u nullglob

if [[ ${#candidates[@]} -eq 0 ]]; then
  die "No package candidate files found in $REPO_DIR. Nothing to add to DB."
fi

# Filter candidates: keep only files that pacman -Qp recognizes as packages
pkg_basenames=()
for f in "${candidates[@]}"; do
  # Skip signature files explicitly
  if [[ "${f##*.}" == "sig" ]]; then
    log "Skipping signature file candidate: $(basename "$f")"
    continue
  fi

  # Verify it's a pacman package file (pacman -Qp prints name+version on success)
  if pacman -Qp "$f" >/dev/null 2>&1; then
    pkg_basenames+=("$(basename "$f")")
  else
    warn "Skipping non-package candidate: $(basename "$f")"
  fi
done

if [[ ${#pkg_basenames[@]} -eq 0 ]]; then
  die "No valid package files found in $REPO_DIR after filtering."
fi

# Work in the repo dir so repo-add writes DB here
pushd "$REPO_DIR" >/dev/null

# Remove old DB/files to force fresh rebuild (optional)
rm -f ./*.db.* ./*.files.* 2>/dev/null || true

# Run repo-add with explicit filenames
log "Running repo-add for files: ${pkg_basenames[*]}"
repo-add shedos.db.tar.gz "${pkg_basenames[@]}" || die "repo-add failed"

# Sign the DB
if [[ -f shedos.db.tar.gz ]]; then
  if [[ -n "${SIGN_KEY:-}" ]]; then
    sign_repo_db "shedos.db.tar.gz" "$SIGN_KEY"
  else
    sign_repo_db "shedos.db.tar.gz"
  fi
else
  die "Expected repo DB not found after repo-add."
fi

popd >/dev/null

log "Repository DB generated and signed. Files placed in: $REPO_DIR"
