#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# usage: build-aur.sh <aur-package-or-local-dir> <artifact-output-dir>
# - If first arg is a directory containing a PKGBUILD, that directory is used.
# - Otherwise it's treated as an AUR package name and cloned from https://aur.archlinux.org/<pkg>.git

PKG_ARG="${1:-}"
ART_OUT="${2:-}"

if [[ -z "$PKG_ARG" || -z "$ART_OUT" ]]; then
  cat <<EOF >&2
Usage: $0 <aur-package-name | path-to-pkgdir> <artifact-output-dir>
Example:
  $0 yay-bin /workspace/output/artifacts
EOF
  exit 2
fi

# Prepare artifact dir (host-mounted path; expand if relative)
mkdir -p "$ART_OUT"

# Detect root and enable makepkg root mode in CI
if [[ "$(id -u)" -eq 0 ]]; then
  export MAKEPKG_ALLOW_ROOT=1
  CI_ROOT_BUILD=true
else
  CI_ROOT_BUILD=false
fi

# Create isolated build dir
BUILD_ROOT="$(mktemp -d --tmpdir build-aur.XXXXXX)"
trap 'rc=$?; rm -rf -- "$BUILD_ROOT"; exit $rc' EXIT

# Determine the package source
if [[ -d "$PKG_ARG" && -f "$PKG_ARG/PKGBUILD" ]]; then
  echo "[INFO] Using local PKGBUILD directory: $PKG_ARG"
  cp -a -- "$PKG_ARG/"* "$BUILD_ROOT/"
else
  # Treat as AUR package name: clone
  PKG_NAME="$PKG_ARG"
  echo "[INFO] Cloning AUR package: $PKG_NAME"
  # Attempt to clone via HTTPS; fallback if needed
  git clone --depth 1 "https://aur.archlinux.org/${PKG_NAME}.git" "$BUILD_ROOT" || {
    echo "[ERROR] Failed to clone AUR package: ${PKG_NAME}" >&2
    exit 3
  }
fi

cd "$BUILD_ROOT"

# sanity: PKGBUILD must exist
if [[ ! -f PKGBUILD ]]; then
  echo "[ERROR] No PKGBUILD found in build dir: $BUILD_ROOT" >&2
  exit 4
fi

# Ensure pacman keyring and base-devel should be installed by container bootstrap step.
# We still check for makepkg and fail early with helpful message if missing.
if ! command -v makepkg >/dev/null 2>&1; then
  echo "[ERROR] makepkg not found; ensure base-devel is installed in the container." >&2
  exit 5
fi

# Run makepkg (noninteractive)
# Note: in CI we allow root builds via MAKEPKG_ALLOW_ROOT; makepkg will still use fakeroot to build .BUILDINFO
# We will not skip signing here — signing is handled separately if you import GPG key in the job.
echo "[INFO] Running makepkg for: $(pwd)"
# Use --syncdeps to fetch deps in container; container step should have pacman prepared, but keep this for safety.
# Use --noconfirm and --clean to avoid prompts and cleanup.
makepkg --syncdeps --noconfirm --clean --noprogressbar || {
  echo "[ERROR] makepkg failed for package in $(pwd)" >&2
  exit 6
}

# Find produced package file(s)
pkgfile="$(ls -1t -- *.pkg.* 2>/dev/null | head -n1 || true)"
if [[ -z "$pkgfile" ]]; then
  echo "[ERROR] No package file produced by makepkg in $(pwd)" >&2
  exit 7
fi

# Copy package and signature (if any) to artifact dir
echo "[INFO] Copying package to artifacts: $pkgfile -> $ART_OUT"
cp --preserve=mode,ownership,timestamps -- "$pkgfile" "$ART_OUT/"

if [[ -f "${pkgfile}.sig" ]]; then
  cp --preserve=mode,ownership,timestamps -- "${pkgfile}.sig" "$ART_OUT/"
fi

# Optional: print final listing for visibility
echo "[INFO] Artifacts in $ART_OUT:"
ls -la "$ART_OUT" || true

# Exit success
exit 0
