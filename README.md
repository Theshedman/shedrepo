
## GPG: Key generation & publishing (for signing packages and repo DB)

### Interactive key generation (developer machine)
1. `gpg --full-generate-key`
   - RSA and RSA, 4096 bits, no expiry (or choose one), enter name/email/passphrase.

2. Export public key:
   `gpg --armor --export "Your Name <you@example.com>" > shedrepo-pubkey.asc`

3. Publish shedrepo-pubkey.asc to:
   - ShedOS website (GitHub Pages)
   - GitHub releases (for the repo version)
   - Provide instruction for `pacman-key` import (see below).

### CI / automation
- Use a batch key generation file (see utils.sh instructions). Import private key in CI runner via:
  `gpg --import private.key`
- Configure GPG agent for loopback pinentry if you want to use passphrase securely.

### Adding key to pacman keyring (client machines)
1. Copy `shedrepo-pubkey.asc` to the machine
2. Import and locally sign:
   ```bash
   sudo pacman-key --add shedrepo-pubkey.asc
   sudo pacman-key --lsign-key <KEYID or email>
