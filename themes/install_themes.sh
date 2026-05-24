#!/usr/bin/env bash
# ==============================================================================
# AurumOS Theme and Icon Installer
# Installs the macOS Sequoia visual layer: WhiteSur GTK, icons, cursors, fonts.
# Idempotent — safe to re-run.
# ==============================================================================

set -euo pipefail

# Pinned versions (date-stamped tags from upstream)
GTK_THEME_TAG="2024-05-01"
ICON_THEME_TAG="2024-04-20"
CURSORS_TAG="2024-02-22"

GTK_THEME_URL="https://github.com/vinceliuice/WhiteSur-gtk-theme/archive/refs/tags/${GTK_THEME_TAG}.tar.gz"
ICON_THEME_URL="https://github.com/vinceliuice/WhiteSur-icon-theme/archive/refs/tags/${ICON_THEME_TAG}.tar.gz"
CURSORS_URL="https://github.com/vinceliuice/WhiteSur-cursors/archive/refs/tags/${CURSORS_TAG}.tar.gz"

THEME_DIR="/usr/share/themes"
ICON_DIR="/usr/share/icons"

log_info()    { echo -e "\e[34m[INFO]\e[0m $*"; }
log_warn()    { echo -e "\e[33m[WARN]\e[0m $*"; }
log_success() { echo -e "\e[32m[SUCCESS]\e[0m $*"; }
log_error()   { echo -e "\e[31m[ERROR]\e[0m $*" >&2; }

if [[ $EUID -ne 0 ]]; then
   log_error "This script must be run as root (sudo)."
   exit 1
fi

# Single scratch dir for the whole run; cleaned on exit.
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "${TMP_ROOT}"' EXIT

# Generic fetch+extract: downloads a tarball, unpacks it, echoes the path of
# the first directory matching the given prefix. Fails loudly on a bad tarball.
fetch_archive() {
    local url="$1" prefix="$2"
    local tarball="${TMP_ROOT}/${prefix}.tar.gz"
    log_info "Downloading ${prefix}..."
    curl -fLsS "${url}" -o "${tarball}"
    tar -xf "${tarball}" -C "${TMP_ROOT}"
    local extracted
    extracted="$(find "${TMP_ROOT}" -maxdepth 1 -type d -name "${prefix}*" | head -n 1)"
    if [[ -z "${extracted}" ]]; then
        log_error "Tarball ${url} did not contain expected directory prefix ${prefix}*."
        return 1
    fi
    echo "${extracted}"
}

setup_directories() {
    log_info "Verifying theme directories..."
    mkdir -p "${THEME_DIR}" "${ICON_DIR}"
}

install_build_deps() {
    if ! command -v apt-get >/dev/null 2>&1; then
        return 0
    fi
    log_info "Installing GTK theme build dependencies..."
    # libglib2.0-dev-bin provides glib-compile-resources for the GTK theme
    # installer. inkscape + optipng accelerate the icon theme generator.
    apt-get update
    apt-get install -y --no-install-recommends \
        sassc libglib2.0-dev-bin \
        inkscape optipng \
        gnome-themes-extra
}

install_gtk_theme() {
    log_info "Building WhiteSur GTK theme..."
    local src
    src="$(fetch_archive "${GTK_THEME_URL}" "WhiteSur-gtk-theme-")"
    # -s solid:  no transparency (cheaper render, lower VRAM)
    # -c Dark:   single variant to keep the system image lean
    # -i apple:  apple logo as activities indicator
    # -N glassy: NavBar style closest to Sequoia's window controls
    bash "${src}/install.sh" -s solid -c Dark -i apple -N glassy -d "${THEME_DIR}"
    log_success "WhiteSur GTK theme installed."
}

install_icon_theme() {
    log_info "Building WhiteSur icon theme..."
    local src
    src="$(fetch_archive "${ICON_THEME_URL}" "WhiteSur-icon-theme-")"
    # -a installs all color variants; -b also drops a bootloader icon set
    bash "${src}/install.sh" -a -b -d "${ICON_DIR}"
    log_success "WhiteSur icon theme installed."
}

install_cursors() {
    log_info "Building WhiteSur cursor theme..."
    local src
    src="$(fetch_archive "${CURSORS_URL}" "WhiteSur-cursors-")"
    # The cursor repo's install.sh hardcodes ~/.icons; we relocate manually.
    if [[ -d "${src}/dist" ]]; then
        cp -r "${src}/dist" "${ICON_DIR}/WhiteSur-cursors"
    else
        # Some tags ship the built dir as `WhiteSur-cursors/`.
        cp -r "${src}/WhiteSur-cursors" "${ICON_DIR}/"
    fi
    # Set the system-wide default cursor to WhiteSur.
    update-alternatives --install /usr/share/icons/default/index.theme \
        x-cursor-theme "${ICON_DIR}/WhiteSur-cursors/cursor.theme" 100 || true
    log_success "WhiteSur cursors installed."
}

install_fonts() {
    log_info "Installing Inter and SF-style fonts..."
    apt-get install -y --no-install-recommends \
        fonts-inter fonts-firacode || \
        log_warn "Inter / FiraCode not in apt repo; will fall back to system defaults."
}

apply_global_settings() {
    log_info "Applying system-wide theme defaults..."

    mkdir -p /etc/gtk-3.0 /etc/gtk-4.0
    local settings_block
    settings_block=$(cat <<'CFG'
[Settings]
gtk-theme-name = WhiteSur-Dark-solid
gtk-icon-theme-name = WhiteSur-dark
gtk-font-name = Inter 10
gtk-cursor-theme-name = WhiteSur-cursors
gtk-cursor-theme-size = 24
gtk-application-prefer-dark-theme = true
gtk-decoration-layout = close,minimize,maximize:menu
CFG
)
    printf '%s\n' "${settings_block}" > /etc/gtk-3.0/settings.ini
    printf '%s\n' "${settings_block}" > /etc/gtk-4.0/settings.ini

    # Environment defaults consumed by Qt6 + xdg utilities at login time.
    install -d -m 0755 /etc/environment.d
    cat <<'CFG' > /etc/environment.d/50-aurum-theme.conf
XCURSOR_THEME=WhiteSur-cursors
XCURSOR_SIZE=24
GTK_THEME=WhiteSur-Dark-solid
QT_QPA_PLATFORMTHEME=qt6ct
CFG

    log_success "Global theme configuration written."
}

main() {
    setup_directories
    install_build_deps
    install_gtk_theme
    install_icon_theme
    install_cursors
    install_fonts
    apply_global_settings
    log_success "AurumOS macOS theme stack installed."
}

main "$@"
