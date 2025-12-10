#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Location: shedrepo/commands/add.sh
# Usage: add.sh <path-to-pkgdir-or-pkgfile>
#        add.sh --help

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)" # shedrepo/
# shellcheck source=../utils.sh
source "$ROOT_DIR/utils.sh"
# shellcheck source=../config.sh
source "$ROOT_DIR/config.sh"

usage() {
  cat <<EOF
Usage: $(basename "$0") [options] <path-to-PKGBUILD-dir | path-to-prebuilt.pkg.tar.zst>

Options:
  --help            Show this help
  --chroot          Use chroot builder (makechrootpkg) if available
  --no-sign         Do not sign the package (not recommended)
  --keep-temp       Do not remove temporary build dir (for debugging)
EOF
}

if [[ $# -lt 1 ]]; then
  usage
  exit 1
fi

# Parse simple flags
USE_CHROOT=false
NO_SIGN=false
KEEP_TEMP=false
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
  --help)
    usage
    exit 0
    ;;
  --chroot)
    USE_CHROOT=true
    shift
    ;;
  --no-sign)
    NO_SIGN=true
    shift
    ;;
  --keep-temp)
    KEEP_TEMP=true
    shift
    ;;
  --*) die "Unknown option: $1" ;;
  *)
    POSITIONAL+=("$1")
    shift
    ;;
  esac
done

TARGET="${POSITIONAL[0]:-}"

# Validate required commands
require_cmds bash makepkg repo-add gpg mkdir cp mv

# Create repo arch dir
TARGET_REPO_DIR="$REPO_ROOT/$ARCH"
ensure_dir "$TARGET_REPO_DIR"

# Create build dir
BUILD_DIR="$(mkbuilddir)"
log "Build dir: $BUILD_DIR"

trap 'if [[ "$KEEP_TEMP" == "false" ]]; then rm -rf -- "$BUILD_DIR"; fi' EXIT

# Helper to install built package into repo dir
install_pkg_into_repo() {
  local pkgfile="$1"
  [[ -f "$pkgfile" ]] || die "package file not found: $pkgfile"
  log "Installing package into repo: $pkgfile -> $TARGET_REPO_DIR/$(basename "$pkgfile")"
  # Ensure target exists
  ensure_dir "$TARGET_REPO_DIR"
  safe_copy "$pkgfile" "$TARGET_REPO_DIR/"
  # Also copy signature if present
  if [[ -f "${pkgfile}.sig" ]]; then
    safe_copy "${pkgfile}.sig" "$TARGET_REPO_DIR/"
  fi
  log "Package moved to repo: $TARGET_REPO_DIR/$(basename "$pkgfile")"
}

# Build from PKGBUILD directory
if [[ -d "$TARGET" ]]; then
  log "Detected directory input. Expecting PKGBUILD inside: $TARGET"
  # Copy build dir to isolated tmp build dir
  cp -a -- "$TARGET"/* "$BUILD_DIR/"
  cd "$BUILD_DIR"
  if [[ ! -f PKGBUILD ]]; then
    die "No PKGBUILD found in $TARGET"
  fi

  # Optionally build inside chroot if requested and makechrootpkg available
  if $USE_CHROOT && command -v makechrootpkg >/dev/null 2>&1; then
    log "Building package inside chroot using makechrootpkg"
    # makechrootpkg requires an existing chroot. We do a simple invocation; adjust for your chroot.
    makechrootpkg -r /var/lib/archbuild -c -v
  else
    log "Building package with makepkg (host build)."
    # Non-interactive build:
    # --syncdeps: install missing deps
    # --noconfirm: pacman auto answer
    # --clean: remove build dependencies and work
    # -C: remove src and pkg directories before building
    # You may need to run this as user (not root). If running in CI as root, you need to use --skipchecks or a proper chroot.
    makepkg --syncdeps --noconfirm --clean --noprogressbar || die "makepkg failed"
  fi

  # Find package file produced (newest)
  pkgfile="$(ls -1t -- *.pkg.* 2>/dev/null | head -n1 || true)"
  [[ -n "$pkgfile" ]] || die "No package produced by makepkg"
  pkgfile="$BUILD_DIR/$pkgfile"

  # Sign package
  if ! $NO_SIGN; then
    if [[ -n "${SIGN_KEY:-}" ]]; then
      sign_package "$pkgfile" "$SIGN_KEY"
    else
      sign_package "$pkgfile"
    fi
  else
    log "Skipping package signature (NO_SIGN set)"
  fi

  install_pkg_into_repo "$pkgfile"
  log "Build and installation complete."

# Prebuilt package file path
elif [[ -f "$TARGET" && "$TARGET" == *.pkg.* ]]; then
  log "Detected prebuilt package file: $TARGET"
  pkgfile="$TARGET"

  # Optionally sign if missing
  if ! $NO_SIGN; then
    if [[ -f "${pkgfile}.sig" ]]; then
      log "Signature found alongside package; using existing signature."
    else
      if [[ -n "${SIGN_KEY:-}" ]]; then
        sign_package "$pkgfile" "$SIGN_KEY"
      else
        sign_package "$pkgfile"
      fi
    fi
  else
    log "Skipping package signature (NO_SIGN set)"
  fi

  install_pkg_into_repo "$pkgfile"
  log "Prebuilt package installed."

else
  die "Unsupported target: $TARGET. Provide a PKGBUILD directory or a .pkg.tar.zst file."
fi

# Final note
log "NOTE: repo DB not regenerated. Run 'shedrepo gen-db' to update the repository database."
