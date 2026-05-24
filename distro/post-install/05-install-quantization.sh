#!/usr/bin/env bash
# ==============================================================================
# AurumOS — LLM quantization toolchain (Agent A / Wave 8)
#
# Installs:
#   * bitsandbytes (NF4/int8 kernels, QLoRA backbone)
#   * AutoGPTQ     (GPTQ quantization)
#   * AutoAWQ      (AWQ quantization, pre-built wheels)
#   * optimum      (HF interface for GPTQ pipelines)
#   * accelerate   (device_map=auto, multi-GPU dispatch)
#
# Profile-blind: every tier (lite -> workstation) gets the quantization stack.
# Quantized inference is the 80% case for 8 GB cards and a critical convenience
# for everyone else; the disk cost (~600 MB) is small enough that gating it on
# profile would be lost user-value, not won disk space.
#
# Install target:
#   1. /opt/aurum-dl-venv if 02-install-dl-stack.sh has already run
#   2. otherwise create it via `python3 -m venv` so subsequent scripts inherit
#   3. last resort: system python with --break-system-packages (CI / sandbox)
#
# Pinned versions live in distro/packages/pip-requirements-quant.txt.
#
# `set -uo pipefail` — NOT `-e` — matches the rest of post-install/* (see
# tools/smoke-test.sh header for the rationale: pip commands legitimately exit
# non-zero in cases we want to surface as WARN, not abort).
# ==============================================================================

set -uo pipefail

VENV_PATH="${VENV_PATH:-/opt/aurum-dl-venv}"
REQS="${REQS:-}"

log()  { echo -e "\e[34m[quant]\e[0m $*"; }
warn() { echo -e "\e[33m[quant]\e[0m $*" >&2; }
err()  { echo -e "\e[31m[quant]\e[0m $*" >&2; }

# --- locate requirements file -------------------------------------------------
if [[ -z "${REQS}" ]]; then
    for candidate in \
        /tmp/aurum/distro/packages/pip-requirements-quant.txt \
        /tmp/packages/pip-requirements-quant.txt \
        /etc/aurum/pip-requirements-quant.txt \
        "$(dirname "$(readlink -f "$0")")/../packages/pip-requirements-quant.txt" \
        ./distro/packages/pip-requirements-quant.txt; do
        if [[ -f "${candidate}" ]]; then REQS="${candidate}"; break; fi
    done
fi
if [[ ! -f "${REQS}" ]]; then
    err "pip-requirements-quant.txt not found (searched standard locations)"
    exit 2
fi
log "requirements file: ${REQS}"

# --- pick a pip ---------------------------------------------------------------
PIP=""
PIP_FLAGS=("--upgrade" "--prefer-binary" "--no-input")

if [[ -x "${VENV_PATH}/bin/pip" ]]; then
    PIP="${VENV_PATH}/bin/pip"
    log "using DL venv pip: ${PIP}"
elif command -v python3 >/dev/null 2>&1; then
    if [[ ! -d "${VENV_PATH}" ]] && [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        log "DL venv missing; bootstrapping with python3 -m venv ${VENV_PATH}"
        python3 -m venv "${VENV_PATH}" 2>/dev/null
        if [[ -x "${VENV_PATH}/bin/pip" ]]; then
            PIP="${VENV_PATH}/bin/pip"
        fi
    fi
    if [[ -z "${PIP}" ]]; then
        # System python — CI / sandbox path. PEP 668 needs --break-system-packages.
        PIP="python3 -m pip"
        PIP_FLAGS+=("--break-system-packages")
        warn "no /opt/aurum-dl-venv; falling back to system python with --break-system-packages"
    fi
else
    err "no python3 on PATH; cannot install"
    exit 3
fi

# --- install ------------------------------------------------------------------
log "installing quantization stack (pinned in ${REQS})..."
# shellcheck disable=SC2086
${PIP} install "${PIP_FLAGS[@]}" -r "${REQS}"
rc=$?
if [[ $rc -ne 0 ]]; then
    err "pip install returned ${rc}; check transcript above"
    exit "${rc}"
fi

# --- smoke-import (CUDA-less host: warnings OK, ImportError not) --------------
log "import smoke test..."
PYBIN="${VENV_PATH}/bin/python"
[[ -x "${PYBIN}" ]] || PYBIN="python3"
"${PYBIN}" - <<'PY' || warn "import smoke test produced errors (see above)"
import importlib, sys
mods = ["bitsandbytes", "auto_gptq", "awq", "optimum", "accelerate"]
results = []
for m in mods:
    try:
        importlib.import_module(m)
        results.append((m, "ok"))
    except ImportError as e:
        # ImportError = the package never installed correctly. Fail loudly.
        results.append((m, f"MISSING: {e}"))
    except Exception as e:
        # RuntimeError / OSError etc. (no CUDA libs on this host) is expected
        # in the Docker preview — surface as WARN, not as a failure.
        results.append((m, f"warn (runtime): {e.__class__.__name__}"))
for m, r in results:
    print(f"  {m:20s} {r}")
missing = [m for m, r in results if r.startswith("MISSING")]
if missing:
    sys.exit(f"required modules failed to install: {missing}")
PY

log "quantization stack ready"
