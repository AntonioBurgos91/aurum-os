#!/usr/bin/env bash
# ==============================================================================
# AurumOS Hyprland builder
# Clones the pinned upstream tag, applies any patches under
# distro/hyprland-fork/patches/, builds, installs to /usr/local, and drops the
# AurumOS compositor defaults into /etc/aurum/hypr/aurum.conf.
#
# Designed to be called inside the ISO chroot, but also runnable on a dev box.
# ==============================================================================

set -euo pipefail

UPSTREAM_REPO="https://github.com/hyprwm/Hyprland.git"
# Pinned tag — bumped deliberately, not automatically.
UPSTREAM_TAG="v0.46.2"

# Resolve FORK_DIR (location of aurum.conf + patches/).
# Standalone runs from the source tree → derive from script location.
# Chroot runs stage the fork next to the script, so honor FORK_DIR if set.
if [[ -n "${FORK_DIR:-}" ]]; then
    : # explicit override wins
else
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -d "${SCRIPT_DIR}/hyprland-fork" ]]; then
        # Chroot layout: /tmp/aurum/{build-hyprland.sh,hyprland-fork/}
        FORK_DIR="${SCRIPT_DIR}/hyprland-fork"
    else
        # Repo layout: distro/iso-builder/build-hyprland.sh
        FORK_DIR="${SCRIPT_DIR}/../hyprland-fork"
    fi
fi
FORK_DIR="$(cd "${FORK_DIR}" && pwd)"
BUILD_DIR="${BUILD_DIR:-/tmp/aurum-hyprland-build}"
PREFIX="${PREFIX:-/usr/local}"
JOBS="${JOBS:-$(nproc)}"

log_info()    { echo -e "\e[34m[hypr]\e[0m $*"; }
log_warn()    { echo -e "\e[33m[hypr]\e[0m $*"; }
log_error()   { echo -e "\e[31m[hypr]\e[0m $*" >&2; }
log_success() { echo -e "\e[32m[hypr]\e[0m $*"; }

require_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Must be run as root (writes to ${PREFIX} and /etc)."
        exit 1
    fi
}

install_build_deps() {
    log_info "Installing Hyprland build dependencies..."
    # Refresh apt cache: in docker layers the previous RUN typically purges
    # /var/lib/apt/lists/* to keep the image lean, leaving us with no
    # installation candidates here.
    apt-get update
    # The runtime libs (libwayland, libxkbcommon, libinput, wayland-protocols,
    # libvulkan) are already in distro/packages/system.list. Here we only add
    # the *-dev headers / meson / ninja that the build itself needs.
    apt-get install -y --no-install-recommends \
        meson ninja-build \
        cpio jq \
        libcairo2-dev libpango1.0-dev \
        libdrm-dev libegl-dev libgles2-mesa-dev libgbm-dev \
        libseat-dev libudev-dev \
        libpixman-1-dev libxcb-composite0-dev \
        libxcb-ewmh-dev libxcb-icccm4-dev libxcb-render-util0-dev \
        libxcb-res0-dev libxcb-xinput-dev libxcb-util-dev \
        libxkbcommon-x11-dev libxcursor-dev \
        libtomlplusplus-dev libzip-dev librsvg2-dev \
        hwdata
}

fetch_source() {
    log_info "Cloning Hyprland ${UPSTREAM_TAG}..."
    rm -rf "${BUILD_DIR}"
    mkdir -p "${BUILD_DIR}"
    # --recursive: Hyprland pulls hyprlang / hyprcursor / hyprutils / hyprwayland-scanner
    # as submodules; without recursive, the build fails at configure.
    git clone --depth 1 --branch "${UPSTREAM_TAG}" --recursive \
        "${UPSTREAM_REPO}" "${BUILD_DIR}/Hyprland"
}

apply_patches() {
    local patch_dir="${FORK_DIR}/patches"
    if [[ ! -d "${patch_dir}" ]]; then
        log_info "No patches directory; skipping."
        return 0
    fi
    shopt -s nullglob
    local patches=("${patch_dir}"/*.patch)
    if [[ ${#patches[@]} -eq 0 ]]; then
        log_info "Patch directory empty; building vanilla upstream."
        return 0
    fi
    log_info "Applying ${#patches[@]} AurumOS patch(es)..."
    (
        cd "${BUILD_DIR}/Hyprland"
        # We use `git apply` (not `git am`) so patches don't need to be
        # formatted with author/date metadata.
        for p in "${patches[@]}"; do
            log_info "  -> $(basename "$p")"
            git apply --whitespace=nowarn "$p"
        done
    )
}

build_and_install() {
    log_info "Building Hyprland (jobs=${JOBS}, prefix=${PREFIX})..."
    (
        cd "${BUILD_DIR}/Hyprland"
        make all -j"${JOBS}"
        make install PREFIX="${PREFIX}"
    )
    log_success "Hyprland installed to ${PREFIX}/bin/Hyprland"
}

install_aurum_defaults() {
    log_info "Staging AurumOS compositor defaults to /etc/aurum/hypr/..."
    install -d -m 0755 /etc/aurum/hypr
    install -m 0644 "${FORK_DIR}/aurum.conf" /etc/aurum/hypr/aurum.conf
}

main() {
    require_root
    install_build_deps
    fetch_source
    apply_patches
    build_and_install
    install_aurum_defaults
    log_success "Hyprland ${UPSTREAM_TAG} (AurumOS) ready."
}

main "$@"
