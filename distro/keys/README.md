# AurumOS release signing — public key

The updater (`aurum-update` / `aurum-update-apply`) verifies release manifests
against a **dedicated keyring** shipped in the OS at
`/usr/share/aurum-os/aurum-release-keyring.gpg`. That keyring is built at ISO
time from the file:

    distro/keys/aurum-release-pubkey.asc   (ASCII-armored public key)

## How to produce it (one-time, by the repo owner)

The private key lives only in the GitHub Actions secret `AURUM_GPG_PRIVATE_KEY`.
Export the matching PUBLIC key from wherever you generated that keypair:

    gpg --armor --export <KEY_ID> > distro/keys/aurum-release-pubkey.asc
    git add distro/keys/aurum-release-pubkey.asc && git commit -m "chore: ship release public key"

Cross-check: every signed release also publishes `aurum-release-pubkey.asc` as
a release asset (exported in CI from the actual signing key). The committed
file and the released asset must be identical.

## Fail-closed behaviour

If this file is absent at build time, the ISO ships WITHOUT the keyring and the
updater refuses to apply updates (clear error), rather than falling back to
the user's default keyring — an empty or attacker-populated default keyring
must never satisfy release verification.
