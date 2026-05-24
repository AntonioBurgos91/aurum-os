#!/usr/bin/env bash
# ==============================================================================
# AurumOS — Deep Learning stack installer
#
# Single source of truth: distro/packages/pip-requirements.txt is the entire
# Python DL surface. This script:
#   1. Ensures `uv` exists.
#   2. Creates the system venv at $VENV_PATH.
#   3. Resolves and installs the requirements with uv (10-100× faster than pip).
#   4. Symlinks notebook CLIs (jupyter-lab, marimo) into /usr/local/bin so they
#      are reachable from the dock and from the menu without sourcing the venv.
#   5. Drops a /etc/profile.d snippet so interactive shells prepend the venv.
#
# Run as root inside the ISO chroot OR on a live system (idempotent).
# ==============================================================================

set -euo pipefail

VENV_PATH="${VENV_PATH:-/opt/aurum-dl-venv}"
PIP_REQS="${PIP_REQS:-/tmp/aurum/pip-requirements.txt}"
PYTHON_VER="${PYTHON_VER:-3.13}"

log()  { echo -e "\e[34m[dl-stack]\e[0m $*"; }
warn() { echo -e "\e[33m[dl-stack]\e[0m $*" >&2; }
die()  { echo -e "\e[31m[dl-stack]\e[0m $*" >&2; exit 1; }

require_root() {
    [[ $EUID -eq 0 ]] || die "must be run as root"
}

ensure_uv() {
    if command -v uv >/dev/null 2>&1; then
        log "uv already on PATH ($(command -v uv))"
        return 0
    fi
    log "installing uv..."
    # Install for root; the binary lands in /root/.local/bin/uv.
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Symlink system-wide so EVERY user (and aurum-settings's venv manager)
    # finds uv without sourcing /root/.local/bin into their PATH.
    if [[ -x /root/.local/bin/uv ]]; then
        ln -sf /root/.local/bin/uv  /usr/local/bin/uv
        ln -sf /root/.local/bin/uvx /usr/local/bin/uvx 2>/dev/null || true
    fi
    export PATH="/usr/local/bin:/root/.local/bin:${PATH}"
    command -v uv >/dev/null 2>&1 || die "uv installation failed"
}

resolve_requirements() {
    if [[ ! -f "${PIP_REQS}" ]]; then
        # Search common locations the ISO builder stages.
        for candidate in \
            /tmp/packages/pip-requirements.txt \
            /tmp/aurum/distro/packages/pip-requirements.txt \
            /etc/aurum/pip-requirements.txt \
            ./distro/packages/pip-requirements.txt; do
            if [[ -f "${candidate}" ]]; then PIP_REQS="${candidate}"; break; fi
        done
    fi
    [[ -f "${PIP_REQS}" ]] || die "pip-requirements.txt not found"
    log "requirements file: ${PIP_REQS}"
}

create_venv() {
    if [[ ! -d "${VENV_PATH}" ]]; then
        log "creating venv at ${VENV_PATH} (python ${PYTHON_VER})..."
        uv venv --python "${PYTHON_VER}" "${VENV_PATH}"
    else
        log "venv already exists at ${VENV_PATH}; reusing"
    fi
}

install_packages() {
    log "installing python DL stack..."
    # `uv pip install -r` mirrors pip's semantics but resolves the entire
    # dependency tree once.
    # `UV_NO_CACHE=1` (default) keeps the ISO image lean: production runs in
    # the chroot don't need 5-10 GB of cached wheels. CI runs override to 0
    # so iterating tests doesn't re-download wheels every pass.
    local cache_flag=""
    if [[ "${UV_NO_CACHE:-1}" == "1" ]]; then
        cache_flag="--no-cache"
        log "uv: cache disabled (UV_NO_CACHE=1; production default)"
    else
        log "uv: cache enabled (UV_NO_CACHE=0; CI/dev mode)"
    fi
    uv pip install --python "${VENV_PATH}/bin/python" \
                   ${cache_flag} \
                   -r "${PIP_REQS}"

    # Sanity-check the resulting venv. vllm / triton / bitsandbytes are
    # **optional**: they only build with nvcc present (the production chroot
    # gets it via 01-add-nvidia-repo.sh; CI / AMD boxes / sandboxes don't).
    "${VENV_PATH}/bin/python" - <<'PY'
import importlib, importlib.util, sys   # Python 3.13: util is not auto-imported
required = ["torch", "jax", "jaxlib", "tensorflow", "numpy",
            "polars", "marimo", "jupyterlab"]
optional = ["vllm", "triton", "bitsandbytes"]

missing = [m for m in required if importlib.util.find_spec(m) is None]
if missing:
    sys.exit("required modules missing after install: " + ", ".join(missing))

absent_opt = [m for m in optional if importlib.util.find_spec(m) is None]
if absent_opt:
    print("import sanity: ok (missing optional CUDA-build packages: "
          + ", ".join(absent_opt) + ")")
else:
    print("import sanity: ok (all required + optional packages present)")
PY
}

expose_clis() {
    log "symlinking notebook CLIs into /usr/local/bin..."
    # Targets must NOT exist as files already. Force replace, but only for the
    # specific tools we ship — avoid blanket symlinking.
    for tool in jupyter jupyter-lab marimo ipython; do
        src="${VENV_PATH}/bin/${tool}"
        if [[ -x "${src}" ]]; then
            ln -sf "${src}" "/usr/local/bin/${tool}"
        else
            warn "${tool} not in venv; skipping symlink"
        fi
    done
}

ensure_world_traversable() {
    # The venv is owned by root (installer runs as root). Without explicit
    # 0755 on the dir tree, users can't access /opt/aurum-dl-venv/bin/python
    # — the venv exists but is invisible to them. Make it world-readable +
    # executable for every directory, leave files alone (their wheel-set mode).
    log "ensuring ${VENV_PATH} is world-traversable..."
    chmod -R a+rX "${VENV_PATH}"
}

write_profile_drop_in() {
    log "writing /etc/profile.d/aurum-dl.sh..."
    cat > /etc/profile.d/aurum-dl.sh <<EOF
# Auto-generated by post-install/02-install-dl-stack.sh
# Prepend AurumOS DL venv so user shells get the same Python the dock launches.
case ":\${PATH}:" in
    *":${VENV_PATH}/bin:"*) ;;
    *) export PATH="${VENV_PATH}/bin:\${PATH}" ;;
esac
EOF
    chmod 0644 /etc/profile.d/aurum-dl.sh
}

main() {
    require_root
    ensure_uv
    resolve_requirements
    create_venv
    install_packages
    expose_clis
    write_profile_drop_in
    ensure_world_traversable
    log "DL stack ready at ${VENV_PATH}"
}

main "$@"
