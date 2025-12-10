#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
TESTDIR="$(mktemp -d)"
export REPO_ROOT="$TESTDIR/repo"
export ARCH="x86_64"

mkdir -p "$REPO_ROOT/$ARCH"

touch "$REPO_ROOT/$ARCH/foo-1-1.pkg.tar.zst"

"$ROOT/shedrepo/commands/remove.sh" foo

[[ ! -f "$REPO_ROOT/$ARCH/foo-1-1.pkg.tar.zst" ]] || {
  echo "Package not removed"
  exit 1
}

echo "[PASS] remove.sh"
