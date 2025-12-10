#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# list.sh - list packages in repo arch dir
# Usage: REPO_ROOT=/abs/path/to/output/repo ARCH=x86_64 ./list.sh [--verbose]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$ROOT_DIR/utils.sh"
source "$ROOT_DIR/config.sh"

VERBOSE=false
while [[ $# -gt 0 ]]; do
  case "$1" in
  --verbose)
    VERBOSE=true
    shift
    ;;
  --help)
    cat <<EOF
Usage: $(basename "$0") [--verbose]
Lists files in the repository with package metadata.
EOF
    exit 0
    ;;
  *) die "Unknown option: $1" ;;
  esac
done

REPO_DIR="${REPO_ROOT%/}/${ARCH}"
ensure_dir "$REPO_DIR"
require_cmds pacman

printf "%-40s %-25s %-20s\n" "FILENAME" "PKGNAME" "VERSION"
printf "%-40s %-25s %-20s\n" "--------" "-------" "-------"

shopt -s nullglob
for f in "$REPO_DIR"/*.pkg.*; do
  info="$(pacman -Qp "$f" 2>/dev/null || true)"
  if [[ -z "$info" ]]; then
    printf "%-40s %-25s %-20s\n" "$(basename "$f")" "<invalid>" "-"
    continue
  fi
  pkgname="$(printf '%s' "$info" | awk '{print $1}')"
  pkgver="$(printf '%s' "$info" | awk '{print $2}')"
  printf "%-40s %-25s %-20s\n" "$(basename "$f")" "$pkgname" "$pkgver"
  if $VERBOSE; then
    size=$(stat -c%s "$f")
    echo "  size: $size bytes"
  fi
done
shopt -u nullglob
