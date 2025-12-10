#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# scripts/build-aur.sh <pkgname> <artifacts_dir>
# This script is intended to run INSIDE an archlinux:latest container as root,
# and will build as a non-root 'builder' user to run makepkg safely.
pkgname="$1"
artifacts_dir="$2"

if [[ -z "$pkgname" || -z "$artifacts_dir" ]]; then
  echo "Usage: $0 <pkgname> <artifacts_dir>"
  exit 2
fi

# Prepare builder user and environment
useradd -m -G users,wheel builder || true
passwd -l builder >/dev/null 2>&1 || true
export HOME_BUILDER="/home/builder"
mkdir -p "$HOME_BUILDER"
chown -R builder:builder "$HOME_BUILDER"

# ensure GNUPG home exists for builder (CI should have imported key into runner gpg)
sudo -u builder mkdir -p "$HOME_BUILDER/.gnupg"
sudo -u builder chmod 700 "$HOME_BUILDER/.gnupg"

# Update and install required packages (non-interactive)
pacman -Sy --noconfirm --needed
pacman -S --noconfirm --needed git base-devel makepkg pacman-contrib gnupg curl

# Clone AUR repo
cd "$HOME_BUILDER"
if ! sudo -u builder git clone "https://aur.archlinux.org/${pkgname}.git"; then
  echo "ERROR: failed to clone AUR repo for ${pkgname}"
  exit 3
fi

cd "${pkgname}"

# If user provided a prebuild hook inside repo (not expected), run it:
if [[ -x ./prebuild.sh ]]; then
  echo "Running prebuild hook for ${pkgname}"
  sudo -u builder ./prebuild.sh
fi

# Build package as builder
sudo -u builder bash -lc 'makepkg --syncdeps --noconfirm --clean --noprogressbar' || {
  echo "makepkg failed for ${pkgname}"
  exit 4
}

# Collect produced package files (.pkg.*) and signatures
mkdir -p -- "$artifacts_dir/$pkgname"
for f in ./*.pkg.*; do
  [ -f "$f" ] || continue
  cp -av -- "$f" "$artifacts_dir/$pkgname/"
done

# Copy signature files produced beside pkgs (if any)
for s in ./*.pkg.*.sig; do
  [ -f "$s" ] || continue
  cp -av -- "$s" "$artifacts_dir/$pkgname/"
done

# optional postbuild hook
if [[ -x ./postbuild.sh ]]; then
  echo "Running postbuild hook for ${pkgname}"
  sudo -u builder ./postbuild.sh "$artifacts_dir/$pkgname"
fi

# Fix ownership so runner can read artifacts
chown -R "$(id -u):$(id -g)" "$artifacts_dir/$pkgname" || true

echo "Built ${pkgname} -> ${artifacts_dir}/${pkgname}"
