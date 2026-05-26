#!/usr/bin/env bash
# install_fonts.sh — AurumOS Wave 10C font installer
# Downloads + installs Inter (SF Pro substitute, OFL-1.1) and JetBrains Mono
# (SF Mono substitute, OFL-1.1) into /usr/share/fonts/aurum/, then refreshes
# the fontconfig cache.
#
# Companion to themes/install-fonts.sh (apt-based, kept for distros where the
# apt packages are current).  This script is used by the iso-builder where we
# want fully reproducible, version-pinned font binaries fetched from GitHub
# release assets — independent of distro repos.
#
# Idempotent: safe to re-run; cached downloads are reused.
#
#   sudo bash themes/install_fonts.sh            # full install
#   bash themes/install_fonts.sh --dry-run       # print actions only
#
set -uo pipefail

# ───────────────────────── configurable pins ──────────────────────────────
INTER_VERSION="${INTER_VERSION:-4.1}"
JBM_VERSION="${JBM_VERSION:-2.304}"

INTER_URL="https://github.com/rsms/inter/releases/download/v${INTER_VERSION}/Inter-${INTER_VERSION}.zip"
JBM_URL="https://github.com/JetBrains/JetBrainsMono/releases/download/v${JBM_VERSION}/JetBrainsMono-${JBM_VERSION}.zip"

CACHE_DIR="${CACHE_DIR:-/var/cache/aurum-fonts}"
INSTALL_ROOT="${INSTALL_ROOT:-/usr/share/fonts/aurum}"
INTER_DIR="${INSTALL_ROOT}/inter"
JBM_DIR="${INSTALL_ROOT}/jetbrains-mono"

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=1 ;;
        -h|--help)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

run() {
    if [[ $DRY_RUN -eq 1 ]]; then
        printf '[dry-run] %s\n' "$*"
    else
        printf '[run]     %s\n' "$*"
        # Pass args directly without eval — preserves quoting + arrays (SC2294 fix)
        "$@"
    fi
}

require_root() {
    if [[ $EUID -ne 0 && $DRY_RUN -eq 0 ]]; then
        echo "error: install_fonts.sh must run as root (or use --dry-run)" >&2
        exit 1
    fi
}

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: missing required tool: $1" >&2
        exit 1
    fi
}

require_root
need_tool curl
need_tool unzip
need_tool fc-cache

run install -d -m 755 "${CACHE_DIR}" "${INSTALL_ROOT}" "${INTER_DIR}" "${JBM_DIR}"

# ───────────────────────── Inter ──────────────────────────────────────────
INTER_ZIP="${CACHE_DIR}/Inter-${INTER_VERSION}.zip"
if [[ -s "${INTER_ZIP}" ]]; then
    echo "==> Inter ${INTER_VERSION} already cached at ${INTER_ZIP}"
else
    echo "==> Fetching Inter ${INTER_VERSION}"
    run curl -fsSL --retry 3 -o "${INTER_ZIP}" "${INTER_URL}"
fi

if find "${INTER_DIR}" -maxdepth 2 -name '*.ttf' -print -quit | grep -q .; then
    echo "    Inter already extracted in ${INTER_DIR} — skipping"
else
    echo "==> Extracting Inter to ${INTER_DIR}"
    # The zip layout shifts slightly across releases — match both modern
    # ("Inter Desktop/") and legacy ("Inter Desktop/Inter-roman.var.ttf") layouts.
    run unzip -o -j -q "${INTER_ZIP}" 'Inter Desktop/*.ttf' 'Inter Desktop/*.otf' -d "${INTER_DIR}" || true
    # Variable fonts (newer releases) live at the zip root in some builds:
    run unzip -o -j -q "${INTER_ZIP}" 'Inter*.var.ttf' -d "${INTER_DIR}" || true
fi

# ───────────────────────── JetBrains Mono ─────────────────────────────────
JBM_ZIP="${CACHE_DIR}/JetBrainsMono-${JBM_VERSION}.zip"
if [[ -s "${JBM_ZIP}" ]]; then
    echo "==> JetBrains Mono ${JBM_VERSION} already cached at ${JBM_ZIP}"
else
    echo "==> Fetching JetBrains Mono ${JBM_VERSION}"
    run curl -fsSL --retry 3 -o "${JBM_ZIP}" "${JBM_URL}"
fi

if find "${JBM_DIR}" -maxdepth 2 -name '*.ttf' -print -quit | grep -q .; then
    echo "    JetBrains Mono already extracted in ${JBM_DIR} — skipping"
else
    echo "==> Extracting JetBrains Mono to ${JBM_DIR}"
    run unzip -o -j -q "${JBM_ZIP}" 'fonts/ttf/*.ttf' -d "${JBM_DIR}"
    run unzip -o -j -q "${JBM_ZIP}" 'fonts/variable/*.ttf' -d "${JBM_DIR}" || true
fi

# ───────────────────────── refresh cache ──────────────────────────────────
echo "==> Refreshing fontconfig cache"
run fc-cache -f "${INSTALL_ROOT}"

if [[ $DRY_RUN -eq 0 ]]; then
    echo "==> Verifying installation"
    for fam in Inter "Inter Display" "JetBrains Mono"; do
        printf '    %-18s → ' "${fam}"
        fc-match "${fam}" 2>/dev/null || echo "(not found)"
    done
fi

echo "==> Done."
