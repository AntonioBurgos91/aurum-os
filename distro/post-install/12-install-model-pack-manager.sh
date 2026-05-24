#!/usr/bin/env bash
# ==============================================================================
# AurumOS — install the aurum-model-pack CLI + bundled manifests (Wave 9)
#
# What this does (idempotent):
#   1. Installs the bash shim                -> /usr/local/bin/aurum-model-pack
#   2. Installs the Python helpers           -> /usr/local/lib/aurum/aurum-model-pack-helpers.py
#   3. Copies the six bundled manifests      -> /etc/aurum/model-packs/
#   4. Creates the per-user cache directory  -> /etc/skel/.cache/aurum/models/{,.installed}
#      so every new account on the system inherits an empty, write-ready cache.
#      Existing users are migrated lazily — first run of `aurum-model-pack`
#      auto-creates $HOME/.cache/aurum/models when the directory is missing.
#   5. Optional: writes a desktop entry so Agent H's Spotlight surface can
#      discover the CLI as a launchable.
#
# Designed to be invoked by the AurumOS post-install runner (which iterates
# distro/post-install/*.sh in lexical order). Safe to run standalone for
# manual installs / dev iteration.
# ==============================================================================

set -euo pipefail

log()  { echo -e "\e[34m[model-pack-mgr]\e[0m $*"; }
warn() { echo -e "\e[33m[model-pack-mgr]\e[0m $*" >&2; }
die()  { echo -e "\e[31m[model-pack-mgr]\e[0m $*" >&2; exit 1; }

require_root_or_writable() {
    # We need to write to /usr/local and /etc; if not root, the user must have
    # passwordless sudo or the dirs must already be world-writable (uncommon).
    if [[ $EUID -ne 0 ]]; then
        if ! [[ -w /usr/local/bin && -w /etc ]]; then
            die "must be run as root (try: sudo bash $0)"
        fi
    fi
}

# Resolve where this script lives so we can find the sibling tools/ and
# distro/assets/ trees regardless of pwd at invocation time.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CLI_SRC="${REPO_ROOT}/tools/aurum-model-pack"
HELPERS_SRC="${REPO_ROOT}/tools/aurum-model-pack-helpers.py"
MANIFESTS_SRC="${REPO_ROOT}/distro/assets/model-packs"

CLI_DEST="/usr/local/bin/aurum-model-pack"
HELPERS_DIR="/usr/local/lib/aurum"
HELPERS_DEST="${HELPERS_DIR}/aurum-model-pack-helpers.py"
MANIFESTS_DEST="/etc/aurum/model-packs"
SKEL_CACHE="/etc/skel/.cache/aurum/models"
DESKTOP_DEST="/usr/share/applications/aurum-model-pack.desktop"

verify_sources() {
    [[ -f "${CLI_SRC}" ]]      || die "missing source: ${CLI_SRC}"
    [[ -f "${HELPERS_SRC}" ]]  || die "missing source: ${HELPERS_SRC}"
    [[ -d "${MANIFESTS_SRC}" ]]|| die "missing source: ${MANIFESTS_SRC}"
    local n
    n=$(find "${MANIFESTS_SRC}" -maxdepth 1 -name '*.yaml' | wc -l)
    if (( n < 6 )); then
        warn "expected 6 manifests in ${MANIFESTS_SRC}, found ${n}"
    fi
}

install_cli() {
    log "installing CLI shim    -> ${CLI_DEST}"
    install -d -m 0755 "$(dirname "${CLI_DEST}")"
    install -m 0755 "${CLI_SRC}" "${CLI_DEST}"

    log "installing helpers     -> ${HELPERS_DEST}"
    install -d -m 0755 "${HELPERS_DIR}"
    install -m 0644 "${HELPERS_SRC}" "${HELPERS_DEST}"
}

install_manifests() {
    log "installing manifests   -> ${MANIFESTS_DEST}/"
    install -d -m 0755 "${MANIFESTS_DEST}"
    local count=0
    while IFS= read -r -d '' yaml; do
        install -m 0644 "${yaml}" "${MANIFESTS_DEST}/$(basename "${yaml}")"
        count=$((count + 1))
    done < <(find "${MANIFESTS_SRC}" -maxdepth 1 -name '*.yaml' -print0)
    log "installed ${count} manifest(s)"
}

seed_cache_skeleton() {
    log "seeding cache skeleton -> ${SKEL_CACHE}/"
    install -d -m 0755 "${SKEL_CACHE}"
    install -d -m 0755 "${SKEL_CACHE}/.installed"
    install -d -m 0755 "${SKEL_CACHE}/hf"
    install -d -m 0755 "${SKEL_CACHE}/gguf"
    install -d -m 0755 "${SKEL_CACHE}/ollama"
    install -d -m 0755 "${SKEL_CACHE}/comfyui-mirror"

    # Also seed the current invoking user's cache if SUDO_USER is set —
    # otherwise `aurum-model-pack list` on the install machine fails with a
    # "no such directory" once they try `install`.
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        local user_home
        user_home=$(getent passwd "${SUDO_USER}" | cut -d: -f6 || true)
        if [[ -n "${user_home}" && -d "${user_home}" ]]; then
            local user_cache="${user_home}/.cache/aurum/models"
            if [[ ! -d "${user_cache}" ]]; then
                log "seeding cache for user ${SUDO_USER} -> ${user_cache}"
                install -d -m 0755 -o "${SUDO_USER}" -g "${SUDO_USER}" "${user_cache}"
                install -d -m 0755 -o "${SUDO_USER}" -g "${SUDO_USER}" "${user_cache}/.installed"
            fi
        fi
    fi
}

install_desktop_entry() {
    log "writing desktop entry  -> ${DESKTOP_DEST}"
    install -d -m 0755 "$(dirname "${DESKTOP_DEST}")"
    cat > "${DESKTOP_DEST}" <<'EOF'
[Desktop Entry]
Type=Application
Name=AurumOS Model Packs
GenericName=ML model pack manager
Comment=Browse and install AurumOS ML model packs (Ollama / HF / ComfyUI)
Exec=aurum-model-pack list
Terminal=true
Categories=Development;Science;ArtificialIntelligence;
Keywords=ai;ml;llm;ollama;huggingface;comfyui;models;
NoDisplay=false
EOF
    chmod 0644 "${DESKTOP_DEST}"
}

post_check() {
    log "post-install sanity:"
    log "  CLI       : $(ls -l "${CLI_DEST}" 2>/dev/null || echo MISSING)"
    log "  helpers   : $(ls -l "${HELPERS_DEST}" 2>/dev/null || echo MISSING)"
    log "  manifests : $(ls "${MANIFESTS_DEST}" 2>/dev/null | tr '\n' ' ' || echo MISSING)"
    log "  skel cache: $(ls -d "${SKEL_CACHE}" 2>/dev/null || echo MISSING)"

    # Best-effort runtime smoke: list packs. This must not fail the post-install
    # even in stripped-down Docker (e.g. no python3-yaml installed) because the
    # helpers ship a minimal-yaml fallback.
    if "${CLI_DEST}" list >/dev/null 2>&1; then
        log "  smoke list: OK"
    else
        warn "  smoke list: failed (non-fatal — packs still installed for first-boot)"
    fi
}

main() {
    require_root_or_writable
    verify_sources
    install_cli
    install_manifests
    seed_cache_skeleton
    install_desktop_entry
    post_check
    log "done. Try: aurum-model-pack list"
}

main "$@"
