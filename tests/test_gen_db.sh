#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
TESTDIR="$(mktemp -d)"
export REPO_ROOT="$TESTDIR/repo"
export ARCH="x86_64"

mkdir -p "$REPO_ROOT/$ARCH"

# Build + place a dummy package
cp "$ROOT/tests/fixtures/helloworld-0.1-1-x86_64.pkg.tar.zst" "$REPO_ROOT/$ARCH/"

"$ROOT/shedrepo/commands/gen_db.sh"

[[ -f "$REPO_ROOT/$ARCH/shedos.db.tar.gz" ]] || {
  echo "DB missing"
  exit 1
}
[[ -f "$REPO_ROOT/$ARCH/shedos.db.tar.gz.sig" ]] || {
  echo "DB signature missing"
  exit 1
}

echo "[PASS] gen_db.sh"
