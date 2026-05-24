#!/usr/bin/env bash
# ==============================================================================
# AurumOS — LLM fine-tuning toolchain (Agent A / Wave 8)
#
# Profile-adaptive: reads /etc/aurum/profile.conf (written by Agent G) and
# installs only the subset of frameworks that the user's hardware can actually
# run. Goal: a fresh `lite` install isn't paying disk-space and pip-resolve
# time for DeepSpeed that it will never run.
#
#   lite         -> peft only (API-driven fine-tuning of remote models)
#   standard     -> + unsloth + torchtune   (7B QLoRA on 8 GB VRAM)
#   pro          -> + axolotl + deepspeed   (multi-GPU ZeRO-2)
#   workstation  -> same as pro             (recipes pick ZeRO-3 at runtime)
#
# Pins live in distro/packages/pip-requirements-finetune.txt; this script
# extracts the relevant lines per profile and feeds them to pip.
#
# Same install-target precedence as 05-install-quantization.sh.
#
# `set -uo pipefail` — NOT `-e` — consistent with the rest of post-install/*.
# ==============================================================================

set -uo pipefail

VENV_PATH="${VENV_PATH:-/opt/aurum-dl-venv}"
REQS="${REQS:-}"
PROFILE_CONF="${PROFILE_CONF:-/etc/aurum/profile.conf}"

log()  { echo -e "\e[34m[finetune]\e[0m $*"; }
warn() { echo -e "\e[33m[finetune]\e[0m $*" >&2; }
err()  { echo -e "\e[31m[finetune]\e[0m $*" >&2; }

# --- resolve profile ----------------------------------------------------------
# shellcheck source=/dev/null
AURUM_PROFILE="standard"
if [[ -f "${PROFILE_CONF}" ]]; then
    source "${PROFILE_CONF}" 2>/dev/null || true
    AURUM_PROFILE="${AURUM_PROFILE:-standard}"
else
    warn "${PROFILE_CONF} missing; assuming AURUM_PROFILE=standard"
fi
log "profile: ${AURUM_PROFILE}"

# --- locate requirements file -------------------------------------------------
if [[ -z "${REQS}" ]]; then
    for candidate in \
        /tmp/aurum/distro/packages/pip-requirements-finetune.txt \
        /tmp/packages/pip-requirements-finetune.txt \
        /etc/aurum/pip-requirements-finetune.txt \
        "$(dirname "$(readlink -f "$0")")/../packages/pip-requirements-finetune.txt" \
        ./distro/packages/pip-requirements-finetune.txt; do
        if [[ -f "${candidate}" ]]; then REQS="${candidate}"; break; fi
    done
fi
if [[ ! -f "${REQS}" ]]; then
    err "pip-requirements-finetune.txt not found"
    exit 2
fi
log "requirements file: ${REQS}"

# --- detect CUDA runtime (gates axolotl on lower tiers) -----------------------
# `nvidia-smi` is the cheapest reliable probe; ldconfig hits in chroots without
# the runtime tools installed.
HAS_CUDA=0
if command -v nvidia-smi >/dev/null 2>&1; then
    if nvidia-smi -L >/dev/null 2>&1; then
        HAS_CUDA=1
    fi
elif ldconfig -p 2>/dev/null | grep -q libcuda.so; then
    HAS_CUDA=1
fi
log "cuda runtime detected: ${HAS_CUDA}"

# --- build per-profile package set --------------------------------------------
# Names here are the SAME strings used in pip-requirements-finetune.txt.
# We pip-install by name rather than -r the whole file so a `lite` install
# isn't dragged into resolving axolotl's tree just to discard it.
PKGS=()
SKIPPED=()

# All profiles get peft + trl.
PKGS+=("peft>=0.14,<1")
PKGS+=("trl>=0.12,<1")
PKGS+=("datasets>=3.0" "sentencepiece>=0.2.0" "tiktoken>=0.8")

case "${AURUM_PROFILE}" in
    lite)
        log "lite profile: skipping Unsloth / TorchTune / Axolotl / DeepSpeed"
        SKIPPED+=("unsloth" "torchtune" "axolotl" "deepspeed")
        ;;

    standard)
        PKGS+=("unsloth[colab-new]==2025.10.7")
        PKGS+=("torchtune>=0.5,<1")
        log "standard profile: skipping Axolotl + DeepSpeed (workstation-grade only)"
        SKIPPED+=("axolotl" "deepspeed")
        ;;

    pro|workstation)
        PKGS+=("unsloth[colab-new]==2025.10.7")
        PKGS+=("torchtune>=0.5,<1")
        if [[ "${HAS_CUDA}" -eq 1 ]]; then
            PKGS+=("axolotl==0.5.2")
        else
            warn "axolotl skipped: requires CUDA at runtime AND has fragile install"
            warn "  without nvcc. Re-run this script after installing CUDA to add it."
            SKIPPED+=("axolotl")
        fi
        PKGS+=("deepspeed==0.15.4")   # CUDA-less install OK; runtime needs CUDA
        ;;

    *)
        warn "unknown profile '${AURUM_PROFILE}'; treating as standard"
        PKGS+=("unsloth[colab-new]==2025.10.7")
        PKGS+=("torchtune>=0.5,<1")
        SKIPPED+=("axolotl" "deepspeed")
        ;;
esac

# --- pick a pip (same logic as 05) --------------------------------------------
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
        PIP="python3 -m pip"
        PIP_FLAGS+=("--break-system-packages")
        warn "no /opt/aurum-dl-venv; falling back to system python with --break-system-packages"
    fi
else
    err "no python3 on PATH; cannot install"
    exit 3
fi

# --- install ------------------------------------------------------------------
log "installing: ${PKGS[*]}"
[[ ${#SKIPPED[@]} -gt 0 ]] && log "skipped for this profile: ${SKIPPED[*]}"

# shellcheck disable=SC2086
${PIP} install "${PIP_FLAGS[@]}" "${PKGS[@]}"
rc=$?
if [[ $rc -ne 0 ]]; then
    err "pip install returned ${rc}"
    exit "${rc}"
fi

# --- smoke-import (CUDA-less host: warnings OK, ImportError not) --------------
log "import smoke test..."
PYBIN="${VENV_PATH}/bin/python"
[[ -x "${PYBIN}" ]] || PYBIN="python3"

# Build the per-profile module list to test
case "${AURUM_PROFILE}" in
    lite)        TEST_MODS="peft trl" ;;
    standard)    TEST_MODS="peft trl unsloth torchtune" ;;
    pro|workstation)
                 TEST_MODS="peft trl unsloth torchtune deepspeed" ;;
    *)           TEST_MODS="peft trl" ;;
esac

"${PYBIN}" - "${TEST_MODS}" <<'PY' || warn "import smoke test produced errors (see above)"
import importlib, sys
mods = sys.argv[1].split()
fail = []
for m in mods:
    try:
        importlib.import_module(m)
        print(f"  {m:20s} ok")
    except ImportError as e:
        print(f"  {m:20s} MISSING: {e}")
        fail.append(m)
    except Exception as e:
        # CUDA-less runtime warnings (RuntimeError, OSError, etc.) are expected.
        print(f"  {m:20s} warn ({e.__class__.__name__}: {str(e)[:80]})")
if fail:
    sys.exit(f"required modules failed to install: {fail}")
PY

log "fine-tuning stack ready (profile=${AURUM_PROFILE})"
