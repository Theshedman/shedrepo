#!/usr/bin/env bash

# Base repo directory
# allow override from env, then normalize to absolute path
_REPO_ROOT_RAW="${REPO_ROOT:-/srv/shedrepo}"
# ensure realpath exists; fallback to original if not
if command -v realpath >/dev/null 2>&1; then
  REPO_ROOT="${REPO_ROOT:-$(_REPO_ROOT_RAW)}"
  REPO_ROOT="$(realpath "$REPO_ROOT")"
else
  REPO_ROOT="${REPO_ROOT:-$_REPO_ROOT_RAW}"
fi

# Temporary build workspace
readonly TMP_BUILD_DIR="${TMP_BUILD_DIR:-/tmp/shedrepo_build}"

# GPG key used for signing packages and repo DB
readonly SIGN_KEY="${SIGN_KEY:-DBED0DF554FF1DA0510FD98ACB197C4EC7302732}"

# Architecture
readonly ARCH="${ARCH:-$(uname -m)}"

# Cloudflare R2 bucket name
readonly R2_BUCKET="${R2_BUCKET:-shedos-repo}"

# R2 https endpoint path
readonly R2_PATH="${R2_PATH:-https://repo.shedos.org/$ARCH}"

# Number of old package versions to keep
readonly KEEP_VERSIONS="${KEEP_VERSIONS:-3}"
