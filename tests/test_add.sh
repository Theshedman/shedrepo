#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
TESTDIR="$(mktemp -d)"
export REPO_ROOT="$TESTDIR/repo"
export ARCH="x86_64"

mkdir -p "$REPO_ROOT"

# Copy example package
cp -r "$ROOT/packages/helloworld" "$TESTDIR/"

# Run add
"$ROOT/shedrepo/commands/add.sh" "$TESTDIR/helloworld"

# Assert package exists
PKGCOUNT=$(find "$REPO_ROOT/$ARCH" -type f -name '*.pkg.tar.zst' | wc -l)
[[ "$PKGCOUNT" -eq 1 ]] || {
  echo "Expected 1 package, found $PKGCOUNT"
  exit 1
}

echo "[PASS] add.sh"
