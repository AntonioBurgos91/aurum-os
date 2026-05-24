#!/usr/bin/env bash
# install-wallpapers.sh — copy the bundled wallpapers into
# /usr/share/backgrounds/aurumos/ and set aurum-sequoia-1.png as the
# distro-default GNOME wallpaper via a dconf override.
#
# Idempotent: re-running it is safe and only updates files that changed.
# Must be run as root (writes to /usr/share and /etc/dconf/db).
#
# Companion to tools/aurum-wallpaper-gen — that tool *produces* the PNGs
# committed under distro/seed/wallpapers/; this script *deploys* them on
# the running system. The ISO post-install hook calls this script during
# first-boot setup; on a live system the operator can re-run it after
# editing MANIFEST.json or dropping new PNGs into the seed directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Pre-flight ------------------------------------------------------------

if [[ $EUID -ne 0 ]]; then
    echo "install-wallpapers.sh: must be run as root (try: sudo $0)" >&2
    exit 1
fi

DEST_DIR="/usr/share/backgrounds/aurumos"
DCONF_DB_DIR="/etc/dconf/db/local.d"
DCONF_FILE="${DCONF_DB_DIR}/00-aurum-wallpaper"
DEFAULT_WALLPAPER="aurum-sequoia-1.png"   # Aurum Dawn

# --- Sanity-check the seed directory --------------------------------------

shopt -s nullglob
seed_pngs=( "${SCRIPT_DIR}"/aurum-sequoia-*.png )
shopt -u nullglob

if (( ${#seed_pngs[@]} == 0 )); then
    cat >&2 <<EOF
install-wallpapers.sh: no wallpaper PNGs found in ${SCRIPT_DIR}.

Run the generator first:

    ./tools/aurum-wallpaper-gen/target/release/aurum-wallpaper-gen \\
        --output-dir distro/seed/wallpapers/

…or, without a Rust toolchain:

    python3 tools/aurum-wallpaper-gen/_fallback_gen.py \\
        --output-dir distro/seed/wallpapers/

EOF
    exit 1
fi

if [[ ! -f "${SCRIPT_DIR}/${DEFAULT_WALLPAPER}" ]]; then
    echo "install-wallpapers.sh: default wallpaper ${DEFAULT_WALLPAPER} not present" >&2
    exit 1
fi

# --- Copy PNGs (and MANIFEST, if present) ---------------------------------

echo "[install-wallpapers] installing ${#seed_pngs[@]} PNG(s) -> ${DEST_DIR}"
install -d -m 0755 "${DEST_DIR}"
install -m 0644 "${SCRIPT_DIR}"/aurum-sequoia-*.png "${DEST_DIR}/"
if [[ -f "${SCRIPT_DIR}/MANIFEST.json" ]]; then
    install -m 0644 "${SCRIPT_DIR}/MANIFEST.json" "${DEST_DIR}/MANIFEST.json"
fi

# --- dconf override --------------------------------------------------------
#
# The override sets a system-wide default; per-user wallpaper choices are
# still honoured because the user dconf database overlays this one. We
# also set picture-uri-dark to the same file (Sequoia palettes work in
# both modes) and a sensible picture-options.

echo "[install-wallpapers] writing dconf override -> ${DCONF_FILE}"
install -d -m 0755 "${DCONF_DB_DIR}"
cat > "${DCONF_FILE}" <<EOF
# AurumOS default wallpaper — see tools/aurum-wallpaper-gen for the source.
[org/gnome/desktop/background]
picture-uri='file://${DEST_DIR}/${DEFAULT_WALLPAPER}'
picture-uri-dark='file://${DEST_DIR}/${DEFAULT_WALLPAPER}'
picture-options='zoom'
primary-color='#1a1a1a'
secondary-color='#1a1a1a'

[org/gnome/desktop/screensaver]
picture-uri='file://${DEST_DIR}/${DEFAULT_WALLPAPER}'
picture-options='zoom'
EOF
chmod 0644 "${DCONF_FILE}"

# Make sure the file is referenced from the local profile. If a profile
# doesn't exist yet, create a minimal one that includes our local db.
PROFILE_FILE="/etc/dconf/profile/user"
if [[ ! -f "${PROFILE_FILE}" ]]; then
    install -d -m 0755 /etc/dconf/profile
    cat > "${PROFILE_FILE}" <<EOF
user-db:user
system-db:local
EOF
    chmod 0644 "${PROFILE_FILE}"
fi

# --- Recompile dconf db ----------------------------------------------------

if command -v dconf >/dev/null 2>&1; then
    echo "[install-wallpapers] running dconf update"
    dconf update
else
    echo "[install-wallpapers] WARNING: dconf binary not found; override staged but not compiled" >&2
fi

echo "[install-wallpapers] done. Default wallpaper: ${DEST_DIR}/${DEFAULT_WALLPAPER}"
