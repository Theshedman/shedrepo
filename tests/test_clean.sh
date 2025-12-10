#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
TESTDIR="$(mktemp -d)"
export REPO_ROOT="$TESTDIR/repo"
export ARCH="x86_64"

mkdir -p "$REPO_ROOT/$ARCH"

# Create old versions
touch "$REPO_ROOT/$ARCH/pkg-1-1.pkg.tar.zst"
touch "$REPO_ROOT/$ARCH/pkg-2-1.pkg.tar.zst"
touch "$REPO_ROOT/$ARCH/pkg-3-1.pkg.tar.zst"

"$ROOT/shedrepo/commands/clean.sh"

# KEEP_VERSIONS=3 → nothing removed
COUNT=$(ls "$REPO_ROOT/$ARCH" | wc -l)
[[ "$COUNT" -eq 3 ]] || {
  echo "Unexpected cleanup result"
  exit 1
}

echo "[PASS] clean.sh"
