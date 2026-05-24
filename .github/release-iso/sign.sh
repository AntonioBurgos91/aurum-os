#!/usr/bin/env bash
# ==============================================================================
# AurumOS Release ISO GPG signing helper
#
# Usage:
#   sign.sh <path-to-iso>
#
# Environment:
#   AURUM_GPG_KEY_ID         GPG key id / uid to sign with. If unset, falls back
#                            to the first secret key in the keyring, then to the
#                            default user id "aurum-os@aurumos.dev".
#   AURUM_GPG_PASSPHRASE     Optional passphrase. When set, signing runs in
#                            fully non-interactive mode (suitable for CI).
#   GNUPGHOME                Honored normally; CI sets this to a tmp dir.
#
# Output:
#   <iso>.asc    — ASCII-armored detached signature next to the ISO.
# ==============================================================================
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <path-to-iso>" >&2
  exit 64
fi

ISO="$1"
if [ ! -f "${ISO}" ]; then
  echo "ISO not found: ${ISO}" >&2
  exit 66
fi

# Pick a key id with progressive fallback.
KEY_ID="${AURUM_GPG_KEY_ID:-}"
if [ -z "${KEY_ID}" ]; then
  KEY_ID="$(gpg --list-secret-keys --with-colons 2>/dev/null \
              | awk -F: '/^sec/ {print $5; exit}')"
fi
KEY_ID="${KEY_ID:-aurum-os@aurumos.dev}"

OUT="${ISO}.asc"
rm -f "${OUT}"

GPG_ARGS=(--batch --yes --armor --detach-sign --local-user "${KEY_ID}" -o "${OUT}")

if [ -n "${AURUM_GPG_PASSPHRASE:-}" ]; then
  # Pinentry-less signing for CI.
  GPG_ARGS=(--pinentry-mode loopback --passphrase "${AURUM_GPG_PASSPHRASE}" "${GPG_ARGS[@]}")
fi

echo "[sign.sh] signing ${ISO} with key ${KEY_ID}"
gpg "${GPG_ARGS[@]}" "${ISO}"

# Sanity-check the produced signature.
gpg --verify "${OUT}" "${ISO}"
echo "[sign.sh] signed: ${OUT}"
