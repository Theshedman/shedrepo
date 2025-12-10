#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# Shared utilities for shedrepo
# -----------------------------------------------------------------------------

# Logging helpers
log() { printf "[%s] [INFO]  %s\n" "$(date -Iseconds)" "$*"; }
warn() { printf "[%s] [WARN]  %s\n" "$(date -Iseconds)" "$*" >&2; }
err() { printf "[%s] [ERROR] %s\n" "$(date -Iseconds)" "$*" >&2; }
die() {
  err "$*"
  exit 1
}

# Ensure a directory exists (create if missing)
ensure_dir() {
  local dir="$1"
  if [[ -z "$dir" ]]; then
    die "ensure_dir called with empty path"
  fi
  if [[ ! -d "$dir" ]]; then
    log "Creating directory: $dir"
    mkdir -p -- "$dir"
  fi
}

# Simple sanity checks (required binaries)
require_cmds() {
  local missing=()
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required commands: ${missing[*]}. Install them and try again."
  fi
}

# Sign a package (detached binary signature). Produces ${pkg}.sig
# Arguments: <pkgfile> <gpg_key>  (gpg_key optional when GPG default configured)
sign_package() {
  local pkgfile="$1"
  local key="${2:-}"
  [[ -f "$pkgfile" ]] || die "Package not found: $pkgfile"

  if [[ -n "$key" ]]; then
    gpg --batch --yes --detach-sign --local-user "$key" --output "${pkgfile}.sig" "$pkgfile"
  else
    gpg --batch --yes --detach-sign --output "${pkgfile}.sig" "$pkgfile"
  fi
  log "Signed package: $(basename "$pkgfile") -> $(basename "${pkgfile}.sig")"
}

# Sign repo DB (detached) - repo.db.tar.gz produced by repo-add
# Arguments: <repo-db-file> <gpg_key optional>
sign_repo_db() {
  local dbfile="$1"
  local key="${2:-}"
  [[ -f "$dbfile" ]] || die "Repo DB not found: $dbfile"

  if [[ -n "$key" ]]; then
    gpg --batch --yes --detach-sign --local-user "$key" --output "${dbfile}.sig" "$dbfile"
  else
    gpg --batch --yes --detach-sign --output "${dbfile}.sig" "$dbfile"
  fi
  log "Signed repo DB: $(basename "$dbfile") -> $(basename "${dbfile}.sig")"
}

# Print instructions for generating a GPG key non-interactively or interactively.
# This prints only — it does not auto-generate a key unless you call generate_gpg_key_batch().
gpg_generation_instructions() {
  cat <<'EOF'

GPG key setup for shedrepo (instructions):

1) Interactive (recommended for first-time manual use)
   $ gpg --full-generate-key
   ... (same instructions as before) ...

2) Non-interactive (CI-friendly)
   - You can generate a GPG key non-interactively using a batch file:
     Use the helper function generate_gpg_key_batch in utils.sh, e.g.:
       $ generate_gpg_key_batch "ShedOS Builder" "builder@shedos.dev" 4096 0 no-protection
     This will print the key fingerprint when complete.

   - Alternatively, create a batch file (gpg-batch.conf) manually and run:
       $ gpg --batch --generate-key gpg-batch.conf

Security notes:
 - Creating an unprotected private key (%no-protection) is insecure but sometimes used in CI.
 - Safer CI pattern: create the key locally, export the private key, store it in a secure secret store,
   and import it in CI runners at runtime (gpg --import <private.key>), then cleanup.
 - To suppress pinentry prompts in CI use the loopback pinentry mode (configure gpg-agent) or
   use an unprotected key with care.
EOF
}

# -----------------------------------------------------------------------------
# Generate a GPG key non-interactively using a temporary batch file.
#
# Usage:
#   generate_gpg_key_batch "Name Real" "email@example.com" "4096" "0" "no-protection|protected"
#
# Arguments:
#   1) Name-Real (string)  - e.g. "ShedOS Builder"
#   2) Name-Email (string) - e.g. "builder@shedos.dev"
#   3) Key-Length (int)    - e.g. 4096
#   4) Expire-Date (int)   - days or 0 for never (pass "0")
#   5) Protection mode     - "no-protection" to create an unencrypted key (CI use) or "protected" to require passphrase
#
# Returns:
#   Prints generated key fingerprint/ID on stdout.
#
# Security note:
#   - Creating unprotected keys (%no-protection) is convenient for CI but is insecure.
#   - Prefer importing an already-created private key into CI via secure secrets (recommended).
# -----------------------------------------------------------------------------
generate_gpg_key_batch() {
  local name_real="${1:-}" name_email="${2:-}" key_length="${3:-4096}" expire_days="${4:-0}" protect_mode="${5:-protected}"
  if [[ -z "$name_real" || -z "$name_email" ]]; then
    die "generate_gpg_key_batch requires Name and Email arguments"
  fi

  # Create temp workspace
  local tmpdir
  tmpdir="$(mktemp -d --tmpdir "shedrepo_gpg.XXXXXX")"
  local batchfile="${tmpdir}/gpg-batch.conf"

  # Build batch content
  {
    printf "Key-Type: RSA\n"
    printf "Key-Length: %s\n" "$key_length"
    printf "Subkey-Type: RSA\n"
    printf "Subkey-Length: %s\n" "$key_length"
    printf "Name-Real: %s\n" "$name_real"
    printf "Name-Email: %s\n" "$name_email"
    if [[ "$expire_days" != "0" ]]; then
      printf "Expire-Date: %sd\n" "$expire_days"
    else
      printf "Expire-Date: 0\n"
    fi

    if [[ "$protect_mode" == "no-protection" ]]; then
      # WARNING: This creates an unprotected private key (no passphrase).
      printf "%%no-protection\n"
    fi
    printf "%%commit\n"
  } >"$batchfile"

  log "Generating GPG key non-interactively (batch file: $batchfile)"
  # Generate the key
  # Note: This command will create keys in the current GPG home (~/.gnupg) unless GNUPGHOME is set.
  if ! gpg --batch --generate-key "$batchfile"; then
    rm -rf -- "$tmpdir"
    die "gpg key generation failed"
  fi

  # Retrieve the generated key ID (fingerprint) by searching for the email
  # Wait a beat and then query keys by email
  # The --with-colons output is easier to parse
  local key_fpr
  key_fpr="$(gpg --with-colons --list-keys "$name_email" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"

  if [[ -z "$key_fpr" ]]; then
    rm -rf -- "$tmpdir"
    die "Unable to determine generated GPG key fingerprint for $name_email"
  fi

  # Cleanup
  rm -rf -- "$tmpdir"

  log "GPG key generated with fingerprint: $key_fpr"
  # Print the fingerprint (caller can capture it)
  printf '%s\n' "$key_fpr"
}

# Create a reproducible temporary build directory and echo it
mkbuilddir() {
  local dir
  dir="$(mktemp -d --tmpdir "shedrepo_build.XXXXXX")"
  printf '%s' "$dir"
}

# Safely copy a file to a destination directory (or dest file path)
# Arguments:
#   $1 = src file
#   $2 = dest path (directory OR full path)
safe_copy() {
  local src="$1" dest="$2"

  [[ -f "$src" ]] || die "safe_copy: src not found: $src"
  # If dest is a directory (ends with / or is an existing dir), write there with basename
  if [[ -d "$dest" || "${dest: -1}" == '/' ]]; then
    local dest_dir="$dest"
    mkdir -p -- "$dest_dir"
    local dest_file="$dest_dir/$(basename "$src")"
  else
    # ensure parent dir exists
    local dest_dir
    dest_dir="$(dirname "$dest")"
    mkdir -p -- "$dest_dir"
    local dest_file="$dest"
  fi

  # Use install to reliably create the file with controlled mode
  # Use 0644 for package files and 0644 for sigs
  install -m 0644 -- "$src" "$dest_file" || die "safe_copy: failed to copy $src -> $dest_file"
}

# Return the latest package file in a directory matching name/version pattern
# Args: <dir> <pkgname-prefix>
latest_pkgfile() {
  local dir="$1" prefix="$2"
  if [[ ! -d "$dir" ]]; then
    return 1
  fi
  # sort by mtime, newest first
  ls -1t -- "$dir"/${prefix}*.pkg.* 2>/dev/null | head -n1 || return 1
}

# -----------------------------------------------------------------------------
# End of utils.sh
# -----------------------------------------------------------------------------
