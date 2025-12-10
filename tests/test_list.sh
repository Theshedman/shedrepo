#!/usr/bin/env bash
set -euo pipefail

ROOT="$(pwd)"
TESTDIR="$(mktemp -d)"
export REPO_ROOT="$TESTDIR/repo"
export ARCH="x86_64"

mkdir -p "$REPO_ROOT/$ARCH"

touch "$REPO_ROOT/$ARCH/aaa.pkg.tar.zst"
touch "$REPO_ROOT/$ARCH/bbb.pkg.tar.zst"

OUT=$("$ROOT/shedrepo/commands/list.sh")

echo "$OUT" | grep -q "aaa" || {
  echo "aaa missing"
  exit 1
}
echo "$OUT" | grep -q "bbb" || {
  echo "bbb missing"
  exit 1
}

echo "[PASS] list.sh"
