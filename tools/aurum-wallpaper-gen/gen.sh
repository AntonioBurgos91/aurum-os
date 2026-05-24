#!/usr/bin/env bash
# gen.sh — build the AurumOS wallpaper generator and emit the six PNGs.
#
# This script is what release-engineering runs locally (or in CI) to refresh
# the committed wallpaper PNGs in distro/seed/wallpapers/. It is intentionally
# NOT invoked by the ISO build pipeline: shipping a Rust toolchain inside the
# build container just to render six static PNGs would be silly.
#
# Usage:
#     ./gen.sh                        # render at 3840x2400 (production)
#     ./gen.sh 1920 1200              # render a smaller preview set
#     AURUM_OUT=/tmp/wp ./gen.sh      # override output directory

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

W="${1:-3840}"
H="${2:-2400}"
OUT="${AURUM_OUT:-${REPO_ROOT}/distro/seed/wallpapers}"

mkdir -p "${OUT}"

echo "[gen.sh] building release binary..."
cargo build --release --manifest-path "${SCRIPT_DIR}/Cargo.toml"

echo "[gen.sh] rendering at ${W}x${H} -> ${OUT}"
"${SCRIPT_DIR}/target/release/aurum-wallpaper-gen" \
    --out    "${OUT}" \
    --width  "${W}" \
    --height "${H}"

echo "[gen.sh] done. Committed PNGs:"
ls -lh "${OUT}"/sequoia-aurum-*.png
