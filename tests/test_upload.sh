#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
TESTDIR="$(mktemp -d)"
export REPO_ROOT="$TESTDIR/repo"
export ARCH="x86_64"

mkdir -p "$REPO_ROOT/$ARCH"
touch "$REPO_ROOT/$ARCH/test.pkg.tar.zst"

"$ROOT/shedrepo/commands/upload.sh" --dry-run || {
  echo "Upload dry-run failed"
  exit 1
}

echo "[PASS] upload.sh"
