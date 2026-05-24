#!/usr/bin/env bash
# install-fonts.sh — install Inter / Inter Display / JetBrains Mono system-wide
# and register the AurumOS fontconfig snippet that maps sans-serif → Inter.
#
# Designed to be idempotent — re-running is safe.  Honors --dry-run.
#
# Wave 10, Agent C.
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=1 ;;
        -h|--help)
            cat <<EOF
Usage: install-fonts.sh [--dry-run]

Installs:
  - fonts-inter           (apt)        Inter UI family
  - fonts-jetbrains-mono  (apt)        JetBrains Mono code family
  - Inter Display         (GitHub OFL) Headline variant — only if missing in apt

Registers /etc/fonts/conf.d/99-aurum-fonts.conf so sans-serif → Inter.
EOF
            exit 0
            ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FONT_DIR="/usr/share/fonts/aurum-os"
CONF_SRC="${SCRIPT_DIR}/aurum-fonts.conf"
CONF_DST="/etc/fonts/conf.d/99-aurum-fonts.conf"
INTER_RELEASE_URL="https://github.com/rsms/inter/releases/latest"
INTER_DISPLAY_ARCHIVE="/tmp/Inter.zip"

run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        echo "[dry-run] $*"
    else
        echo "[run]     $*"
        eval "$@"
    fi
}

require_root() {
    if [[ $EUID -ne 0 && $DRY_RUN -eq 0 ]]; then
        echo "error: must be run as root (or use --dry-run)" >&2
        exit 1
    fi
}

require_root

echo "==> Installing apt font packages"
run "apt-get update -qq"
run "apt-get install -y --no-install-recommends fonts-inter fonts-jetbrains-mono unzip curl"

echo "==> Ensuring Aurum font dir exists: ${FONT_DIR}"
run "install -d -m 755 ${FONT_DIR}"

# Inter Display is shipped inside the standard Inter zip; some distros split it
# off and some do not.  Check fontconfig — if "Inter Display" is unknown, fetch.
echo "==> Checking for Inter Display"
if ! fc-list 2>/dev/null | grep -qi "Inter Display"; then
    echo "    Inter Display not found; downloading from upstream OFL release"
    run "curl -fsSL -o ${INTER_DISPLAY_ARCHIVE} \"\$(curl -fsSL ${INTER_RELEASE_URL} | grep -Eo 'https://[^\"]+Inter-[0-9.]+\\.zip' | head -1)\""
    run "unzip -o -j ${INTER_DISPLAY_ARCHIVE} 'Inter Desktop/Inter Display-*.ttf' -d ${FONT_DIR}"
    run "rm -f ${INTER_DISPLAY_ARCHIVE}"
else
    echo "    Inter Display already present — skipping download"
fi

echo "==> Installing fontconfig snippet to ${CONF_DST}"
if [[ ! -f "${CONF_SRC}" ]]; then
    echo "error: missing source ${CONF_SRC}" >&2
    exit 1
fi
run "install -m 644 ${CONF_SRC} ${CONF_DST}"

echo "==> Refreshing font cache"
run "fc-cache -fv"

echo "==> Verifying fontconfig resolves to Inter"
if [[ $DRY_RUN -eq 0 ]]; then
    fc-match Inter
    fc-match "Inter Display"
    fc-match "JetBrains Mono"
    fc-match sans-serif
fi

echo "==> Done."
