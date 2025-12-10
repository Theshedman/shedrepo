#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# usage: build-aur.sh <aur-package-or-local-dir> <artifact-output-dir>

PKG_ARG="${1:-}"
ART_OUT="${2:-}"

if [[ -z "$PKG_ARG" || -z "$ART_OUT" ]]; then
  cat <<EOF >&2
Usage: $0 <aur-package-name | path-to-pkgdir> <artifact-output-dir>
EOF
  exit 2
fi

mkdir -p "$ART_OUT"

# Do not force root builds here. If run as root we won't attempt to change behavior;
# The workflow ensures we run as non-root builder or set MAKEPKG_ALLOW_ROOT when intended.
if [[ "$(id -u)" -eq 0 ]]; then
  echo "[WARN] Running as root; MAKEPKG_ALLOW_ROOT must be set if you intend to allow root builds."
fi

BUILD_ROOT="$(mktemp -d --tmpdir build-aur.XXXXXX)"
trap 'rc=$?; rm -rf -- "$BUILD_ROOT"; exit $rc' EXIT

if [[ -d "$PKG_ARG" && -f "$PKG_ARG/PKGBUILD" ]]; then
  echo "[INFO] Using local PKGBUILD directory: $PKG_ARG"
  cp -a -- "$PKG_ARG/"* "$BUILD_ROOT/"
else
  PKG_NAME="$PKG_ARG"
  echo "[INFO] Cloning AUR package: $PKG_NAME"
  git clone --depth 1 "https://aur.archlinux.org/packages/${PKG_NAME}.git" "$BUILD_ROOT" || {
    git clone --depth 1 "https://aur.archlinux.org/${PKG_NAME}.git" "$BUILD_ROOT" || {
      echo "[ERROR] Failed to clone AUR package: ${PKG_NAME}" >&2
      exit 3
    }
  }
fi

cd "$BUILD_ROOT"

if [[ ! -f PKGBUILD ]]; then
  echo "[ERROR] No PKGBUILD found in build dir: $BUILD_ROOT" >&2
  exit 4
fi

if ! command -v makepkg >/dev/null 2>&1; then
  echo "[ERROR] makepkg not found; ensure base-devel is installed in the container." >&2
  exit 5
fi

echo "[INFO] Running makepkg in $BUILD_ROOT"

# IMPORTANT: remove --syncdeps so makepkg won't attempt to auto-install makedepends.
# Those must be pre-installed by the container step (root).
# Use non-interactive flags but do not let makepkg manage deps.
makepkg --noconfirm --clean --noprogressbar || {
  echo "[ERROR] makepkg failed for package in $(pwd)" >&2
  exit 6
}

pkgfile="$(ls -1t -- *.pkg.* 2>/dev/null | head -n1 || true)"
if [[ -z "$pkgfile" ]]; then
  echo "[ERROR] No package file produced by makepkg in $(pwd)" >&2
  exit 7
fi

echo "[INFO] Copying package to artifacts: $pkgfile -> $ART_OUT"
cp --preserve=mode,ownership,timestamps -- "$pkgfile" "$ART_OUT/"
if [[ -f "${pkgfile}.sig" ]]; then
  cp --preserve=mode,ownership,timestamps -- "${pkgfile}.sig" "$ART_OUT/"
fi

echo "[INFO] Artifacts in $ART_OUT:"
ls -la "$ART_OUT" || true

exit 0
