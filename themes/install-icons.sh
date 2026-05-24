#!/usr/bin/env bash
# ==============================================================================
# AurumOS Icon Theme Installer (Aurum-Sequoia)
#
# Deposits the in-tree icon assets (file-types/, applets/, cursors/) under
# the system-wide XDG icon root, registers the cursor theme alternative, and
# refreshes the GTK icon cache so newly added MIME-type SVGs become visible
# to Finder, Menubar and any GTK file picker immediately.
#
# Run AFTER install_themes.sh (which provides the upstream WhiteSur cursor
# binaries that Aurum-Sequoia inherits from). Idempotent.
# ==============================================================================
set -euo pipefail

DRY_RUN=0
for arg in "$@"; do
    case "$arg" in
        --dry-run|-n) DRY_RUN=1 ;;
        -h|--help)
            cat <<USAGE
Usage: install-icons.sh [--dry-run]
  --dry-run, -n   Print the actions that would be taken without touching disk.
USAGE
            exit 0 ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SRC_ROOT="${SCRIPT_DIR}/icons"
THEME_NAME="Aurum-Sequoia"
ICON_DIR="/usr/share/icons"
DEST_ROOT="${ICON_DIR}/${THEME_NAME}"

log()  { echo -e "\e[34m[icons]\e[0m $*"; }
ok()   { echo -e "\e[32m[icons]\e[0m $*"; }
warn() { echo -e "\e[33m[icons]\e[0m $*"; }
err()  { echo -e "\e[31m[icons]\e[0m $*" >&2; }

run() {
    if (( DRY_RUN )); then
        echo "  + $*"
    else
        eval "$@"
    fi
}

require_root() {
    if (( DRY_RUN )); then return; fi
    if [[ $EUID -ne 0 ]]; then
        err "install-icons.sh must run as root (sudo). Use --dry-run to preview."
        exit 1
    fi
}

ensure_sources() {
    for sub in file-types applets cursors/Aurum-Sequoia; do
        if [[ ! -d "${SRC_ROOT}/${sub}" ]]; then
            err "missing source directory: ${SRC_ROOT}/${sub}"
            exit 1
        fi
    done
}

regenerate_file_types() {
    # If the SVGs haven't been materialised from the templates yet, do it now.
    local gen="${SRC_ROOT}/file-types/_generate.py"
    if [[ -x "${gen}" || -f "${gen}" ]]; then
        if command -v python3 >/dev/null 2>&1; then
            log "regenerating file-type icons from manifest"
            run "python3 '${gen}'"
        else
            warn "python3 not found; using pre-committed SVGs as-is"
        fi
    fi
}

write_theme_index() {
    local index="${DEST_ROOT}/index.theme"
    log "writing ${index}"
    if (( DRY_RUN )); then
        echo "  + cat > ${index} <<INDEX ... INDEX"
        return
    fi
    mkdir -p "${DEST_ROOT}"
    cat > "${index}" <<INDEX
[Icon Theme]
Name=Aurum-Sequoia
Comment=AurumOS macOS-Sequoia icon theme (file-types, applets, cursors)
Inherits=WhiteSur-dark,WhiteSur,Adwaita,hicolor
Directories=file-types,applets,scalable/apps

[file-types]
Size=64
MinSize=16
MaxSize=512
Type=Scalable
Context=MimeTypes

[applets]
Size=16
MinSize=14
MaxSize=64
Type=Scalable
Context=Status

[scalable/apps]
Size=128
MinSize=16
MaxSize=512
Type=Scalable
Context=Applications
INDEX
}

deposit_assets() {
    log "depositing assets under ${DEST_ROOT}"
    run "mkdir -p '${DEST_ROOT}/file-types' '${DEST_ROOT}/applets'"
    # Only ship the rendered SVGs to the system tree — templates, manifest and
    # generator script stay in-source.
    run "find '${SRC_ROOT}/file-types' -maxdepth 1 -name '*.svg' -exec cp -t '${DEST_ROOT}/file-types' {} +"
    run "cp '${SRC_ROOT}/file-types/README.md' '${DEST_ROOT}/file-types/' 2>/dev/null || true"
    run "find '${SRC_ROOT}/applets' -maxdepth 1 -name '*.svg' -exec cp -t '${DEST_ROOT}/applets' {} +"
}

deposit_cursors() {
    local cursor_src="${SRC_ROOT}/cursors/Aurum-Sequoia"
    log "depositing cursor theme inheritance shim"
    run "mkdir -p '${DEST_ROOT}/cursors'"
    run "cp '${cursor_src}/index.theme' '${DEST_ROOT}/index.theme.cursors' 2>/dev/null || true"
    run "cp '${cursor_src}/cursor.theme' '${DEST_ROOT}/cursor.theme'"
    # Keep an aliased copy at the canonical cursor location so XCursor's
    # default lookup path finds it without help from gtk-3.0/settings.ini.
    run "cp -r '${cursor_src}' '${ICON_DIR}/Aurum-Sequoia-cursors' 2>/dev/null || true"
    # Register as a system cursor alternative.
    run "update-alternatives --install /usr/share/icons/default/index.theme \
            x-cursor-theme '${DEST_ROOT}/cursor.theme' 110 || true"
}

refresh_cache() {
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        log "refreshing gtk-icon-cache"
        run "gtk-update-icon-cache --quiet --force '${DEST_ROOT}' || true"
    else
        warn "gtk-update-icon-cache not installed; cache refresh skipped"
    fi
}

main() {
    require_root
    ensure_sources
    regenerate_file_types
    deposit_assets
    write_theme_index
    deposit_cursors
    refresh_cache
    ok "Aurum-Sequoia icon theme installed at ${DEST_ROOT}"
}

main
