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
# AMD-LITE PATCH: choose requirements file based on hardware profile.
PROFILE_CONF="${AURUM_PROFILE_CONF:-/etc/aurum/profile.conf}"
if [[ -r "${PROFILE_CONF}" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "${PROFILE_CONF}"
    set +a
fi
AURUM_HAS_CUDA="${AURUM_HAS_CUDA:-0}"

if [[ "${AURUM_HAS_CUDA}" == "0" && -z "${PIP_REQS:-}" ]]; then
    PIP_REQS="/tmp/aurum/pip-requirements-base.txt"
fi
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
    # AMD-LITE PATCH: on CPU-only hosts prefer -base.txt (CUDA-safe).
    local req_basename="pip-requirements.txt"
    if [[ "${AURUM_HAS_CUDA:-0}" == "0" ]]; then
        req_basename="pip-requirements-base.txt"
        log "CPU-only host detected (AURUM_HAS_CUDA=0) → using ${req_basename}"
    fi
    if [[ ! -f "${PIP_REQS}" ]]; then
        for candidate in \
            "/tmp/packages/${req_basename}" \
            "/tmp/aurum/distro/packages/${req_basename}" \
            "/etc/aurum/${req_basename}" \
            "./distro/packages/${req_basename}"; do
            if [[ -f "${candidate}" ]]; then PIP_REQS="${candidate}"; break; fi
        done
    fi
    [[ -f "${PIP_REQS}" ]] || die "${req_basename} not found"
    log "requirements file: ${PIP_REQS}"
}

create_venv() {
    if [[ ! -d "${VENV_PATH}" ]]; then
        log "creating venv at ${VENV_PATH} (python ${PYTHON_VER})..."
        uv venv --relocatable --link-mode copy --python "${AURUM_PYTHON_BIN:-${PYTHON_VER}}" "${VENV_PATH}"  # AMD-LITE: relocatable+copy → venv autocontenido, accesible por todos los usuarios
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

    # --- Blackwell / CUDA wheel selection ------------------------------------
    # The default PyPI torch wheel does NOT carry sm_120 kernels, so on a
    # Blackwell card (RTX 50-series) it fails at runtime with "no kernel image
    # available for execution on the device". On a CUDA host we make PyTorch's
    # cu128 index the PRIMARY index (it carries sm_120 wheels for torch/
    # torchvision/torchaudio) and PyPI the EXTRA index for everything else. uv's
    # default first-match strategy takes the torch family from cu128 and every
    # other package from PyPI in a single, conflict-free resolution. Override
    # the channel with AURUM_TORCH_CHANNEL (e.g. cu129) for a newer CUDA.
    local index_flags=""
    if [[ "${AURUM_HAS_CUDA:-0}" == "1" ]]; then
        local torch_channel="${AURUM_TORCH_CHANNEL:-cu128}"
        # Build any source CUDA extensions for Blackwell (sm_120) + common prior
        # arches so a mixed GPU fleet still works.
        export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-8.9;9.0;12.0}"
        index_flags="--index-url https://download.pytorch.org/whl/${torch_channel} --extra-index-url https://pypi.org/simple"
        log "CUDA host → torch wheels from ${torch_channel} (Blackwell sm_120); arch=${TORCH_CUDA_ARCH_LIST}"
    fi

    uv pip install --python "${VENV_PATH}/bin/python" \
                   ${cache_flag} \
                   ${index_flags} \
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
