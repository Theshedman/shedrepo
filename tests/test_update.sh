#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# tests/test_update.sh
# Verify update.sh rebuilds/installs a package and optionally regenerates DB.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TESTDIR="$(mktemp -d)"
export REPO_ROOT="$TESTDIR/repo"
export ARCH="x86_64"

mkdir -p "$REPO_ROOT/$ARCH"

# copy example PKGBUILD package dir into temp testdir
cp -r "$ROOT/packages/helloworld" "$TESTDIR/helloworld"

# First, use add.sh to add the package (simulate initial publish)
"$ROOT/shedrepo/commands/add.sh" "$TESTDIR/helloworld"

# Ensure the package file exists in repo
pkg_count_before=$(find "$REPO_ROOT/$ARCH" -type f -name '*.pkg.tar.*' | wc -l)
if [[ "$pkg_count_before" -lt 1 ]]; then
  echo "FAIL: expected at least 1 package after add; found $pkg_count_before"
  exit 1
fi

# Now call update.sh on the same package and request regen of DB
"$ROOT/shedrepo/commands/update.sh" "$TESTDIR/helloworld" --regen

# After update+regen, ensure package file still exists (possibly a new copy/version)
pkg_count_after=$(find "$REPO_ROOT/$ARCH" -type f -name '*.pkg.tar.*' | wc -l)
if [[ "$pkg_count_after" -lt 1 ]]; then
  echo "FAIL: expected package to exist after update; found $pkg_count_after"
  exit 1
fi

# Ensure repo DB was generated
if [[ ! -f "$REPO_ROOT/$ARCH/shedos.db.tar.gz" ]]; then
  echo "FAIL: expected shedos.db.tar.gz to exist after regen"
  exit 1
fi

echo "[PASS] test_update.sh"
