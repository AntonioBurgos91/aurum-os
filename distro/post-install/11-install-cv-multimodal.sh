#!/usr/bin/env bash
# ==============================================================================
# AurumOS — Computer Vision & Multimodal stack (Agent F / Wave 8)
#
# Installs:
#   * pip libs from pip-requirements-cv.txt
#     (ultralytics + YOLOv11, segment-anything-2, open-clip, controlnet-aux,
#      diffusers, transformers floor)
#   * ComfyUI checkout at /opt/aurum-comfyui (standard/pro/workstation only)
#   * SAM2 git fallback if the pypi name resolves nothing
#   * DINOv2 git fallback (no pypi distribution as of 2025-11)
#
# Profile policy:
#   * lite        — pip libs only. Skip ComfyUI (no GPU = unusable). YOLOv11n
#                   and SAM2-tiny still run on CPU for testing.
#   * standard    — pip libs + ComfyUI. SDXL-Turbo int8 is the default checkpoint.
#   * pro / workstation — pip libs + ComfyUI + larger default checkpoints (set
#                   by aurum-cv-download-models from $AURUM_SD_MODEL).
#
# Model weights are NOT fetched at install time (would add 5-30 GB to the ISO
# and burn user bandwidth before they've decided what they want). The companion
# `aurum-cv-download-models` CLI does that on demand, post-install.
#
# `set -uo pipefail` — NOT `-e` — matches 05-install-quantization.sh: pip
# legitimately exits non-zero in cases we want to surface as WARN, not abort
# (most commonly the sam-2 / segment-anything-2 / git-fallback chain).
# ==============================================================================

set -uo pipefail

# --- Locate inputs ------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
VENV_PATH="${VENV_PATH:-/opt/aurum-dl-venv}"
COMFYUI_DIR="${COMFYUI_DIR:-/opt/aurum-comfyui}"
COMFYUI_REPO="${COMFYUI_REPO:-https://github.com/comfyanonymous/ComfyUI}"
PROFILE_CONF="${PROFILE_CONF:-/etc/aurum/profile.conf}"
REQS="${REQS:-}"

log()  { echo -e "\e[34m[cv]\e[0m $*"; }
warn() { echo -e "\e[33m[cv]\e[0m $*" >&2; }
err()  { echo -e "\e[31m[cv]\e[0m $*" >&2; }

# --- Load profile -------------------------------------------------------------
# `source` may fail in the Docker preview (no /etc/aurum/profile.conf); we
# default to `standard` because the 80% target is the RTX 5060 box. The lite
# fallback is reserved for the explicit no-GPU case.
# shellcheck disable=SC1090
if [[ -f "${PROFILE_CONF}" ]]; then
    # shellcheck disable=SC1091
    source "${PROFILE_CONF}"
fi
AURUM_PROFILE="${AURUM_PROFILE:-standard}"
log "profile: ${AURUM_PROFILE}"

# --- Locate requirements file -------------------------------------------------
if [[ -z "${REQS}" ]]; then
    for candidate in \
        /tmp/aurum/distro/packages/pip-requirements-cv.txt \
        /tmp/packages/pip-requirements-cv.txt \
        /etc/aurum/pip-requirements-cv.txt \
        "${SCRIPT_DIR}/../packages/pip-requirements-cv.txt" \
        ./distro/packages/pip-requirements-cv.txt; do
        if [[ -f "${candidate}" ]]; then REQS="${candidate}"; break; fi
    done
fi
if [[ ! -f "${REQS}" ]]; then
    err "pip-requirements-cv.txt not found (searched standard locations)"
    exit 2
fi
log "requirements file: ${REQS}"

# --- Pick a pip ---------------------------------------------------------------
PIP=""
PIP_FLAGS=("--upgrade" "--prefer-binary" "--no-input")

if [[ -x "${VENV_PATH}/bin/pip" ]]; then
    PIP="${VENV_PATH}/bin/pip"
    PYBIN="${VENV_PATH}/bin/python"
    log "using DL venv pip: ${PIP}"
elif command -v python3 >/dev/null 2>&1; then
    PIP="python3 -m pip"
    PYBIN="python3"
    PIP_FLAGS+=("--break-system-packages")
    warn "no /opt/aurum-dl-venv; falling back to system python with --break-system-packages"
else
    err "no python3 on PATH; cannot install"
    exit 3
fi

# --- Install pip requirements -------------------------------------------------
log "installing CV/multimodal pip stack (pinned in ${REQS})..."
# shellcheck disable=SC2086
${PIP} install "${PIP_FLAGS[@]}" -r "${REQS}"
rc=$?
if [[ $rc -ne 0 ]]; then
    warn "primary pip install returned ${rc} — trying sam-2 alternates"
    # Some mirrors resolve only one of the two SAM2 names. Try them in order
    # and fall back to a git install on the third miss.
    sam_ok=0
    for cand in "sam-2" "segment-anything-2" "git+https://github.com/facebookresearch/sam2.git"; do
        log "  sam2 candidate: ${cand}"
        # shellcheck disable=SC2086
        if ${PIP} install "${PIP_FLAGS[@]}" "${cand}"; then
            sam_ok=1
            log "  sam2 installed via: ${cand}"
            break
        fi
    done
    if [[ $sam_ok -eq 0 ]]; then
        warn "sam2 install failed via all routes — recipes/cv/03_sam2_segment.py will be unusable until fixed"
    fi
    # Retry the rest of the requirements file with sam-2 lines stripped so we
    # don't keep failing on it forever. This is the only entry that needs
    # special-casing; everything else is a normal pypi package.
    log "re-running pip install on requirements minus sam-2 line..."
    tmp_req="$(mktemp)"
    grep -v -E '^(sam-2|segment-anything-2)' "${REQS}" > "${tmp_req}"
    # shellcheck disable=SC2086
    ${PIP} install "${PIP_FLAGS[@]}" -r "${tmp_req}" || warn "secondary pass also had errors (see above)"
    rm -f "${tmp_req}"
fi

# --- DINOv2 git fallback ------------------------------------------------------
# DINOv2 has no pypi distribution. Most recipes go through HuggingFace's
# AutoModel path which doesn't need the upstream repo at all — but a couple
# of advanced workflows (linear classifier heads, frozen-feature evaluation)
# do `from dinov2.models import vision_transformer`. Install when missing.
log "checking DINOv2 availability..."
if ! "${PYBIN}" -c "import dinov2" 2>/dev/null; then
    log "DINOv2 not importable via pypi — falling back to git install"
    # shellcheck disable=SC2086
    if ${PIP} install "${PIP_FLAGS[@]}" "git+https://github.com/facebookresearch/dinov2.git"; then
        log "DINOv2 installed from git"
    else
        warn "DINOv2 git install failed — recipes will use HF AutoModel path only (still works)"
    fi
else
    log "DINOv2 already importable"
fi

# --- Install ComfyUI (skip on lite) -------------------------------------------
case "${AURUM_PROFILE}" in
  lite)
    log "skipping ComfyUI on lite profile (no GPU — would be unusable)"
    log "  YOLOv11n / SAM2-tiny / OpenCLIP still work on CPU via recipes/cv/*"
    ;;
  standard|pro|workstation)
    if [[ -d "${COMFYUI_DIR}/.git" ]]; then
        log "ComfyUI already cloned at ${COMFYUI_DIR}; pulling latest"
        (cd "${COMFYUI_DIR}" && git pull --ff-only) || warn "git pull failed; keeping existing checkout"
    else
        log "cloning ComfyUI to ${COMFYUI_DIR}..."
        # --depth 1: we don't need full history; the user's workflow is to
        # `git pull` for updates, which works fine on shallow clones.
        if ! git clone --depth 1 "${COMFYUI_REPO}" "${COMFYUI_DIR}"; then
            err "git clone of ComfyUI failed"
            exit 4
        fi
    fi

    log "installing ComfyUI python requirements..."
    # shellcheck disable=SC2086
    ${PIP} install "${PIP_FLAGS[@]}" -r "${COMFYUI_DIR}/requirements.txt" \
        || warn "comfyui requirements had install errors (often torch ABI noise; check above)"

    # Standard model directory tree (ComfyUI creates these on first run, but
    # we materialise them now so the .desktop launcher and the download CLI
    # have a stable target without race conditions).
    log "preparing ComfyUI model directories..."
    install -d -m 0755 "${COMFYUI_DIR}/models/checkpoints"
    install -d -m 0755 "${COMFYUI_DIR}/models/controlnet"
    install -d -m 0755 "${COMFYUI_DIR}/models/vae"
    install -d -m 0755 "${COMFYUI_DIR}/models/loras"
    install -d -m 0755 "${COMFYUI_DIR}/models/clip"
    install -d -m 0755 "${COMFYUI_DIR}/models/clip_vision"

    # Drop our pre-made workflows into the default user folder so they show up
    # in the UI's "Workflows" sidebar without the user having to drag JSON in.
    install -d -m 0755 "${COMFYUI_DIR}/user/default/workflows"
    for wf in \
        "${SCRIPT_DIR}/../../recipes/comfyui/workflows" \
        "/tmp/aurum/recipes/comfyui/workflows" \
        "./recipes/comfyui/workflows"; do
        if [[ -d "${wf}" ]]; then
            log "  copying workflows from ${wf}"
            cp -f "${wf}"/*.json "${COMFYUI_DIR}/user/default/workflows/" 2>/dev/null || true
            break
        fi
    done

    # Make the install world-traversable for the same reason the DL venv is —
    # users need to read main.py and the models dir without sourcing root's env.
    chmod -R a+rX "${COMFYUI_DIR}" || true
    ;;
  *)
    warn "unknown profile '${AURUM_PROFILE}' — defaulting to ComfyUI install"
    ;;
esac

# --- Smoke test ---------------------------------------------------------------
log "import smoke test..."
"${PYBIN}" - <<'PY' || warn "import smoke test produced errors (see above)"
import importlib, sys
required = ["ultralytics", "diffusers", "open_clip", "controlnet_aux", "transformers"]
optional = ["sam2", "dinov2"]
results = []
for m in required:
    try:
        importlib.import_module(m)
        results.append((m, "ok"))
    except ImportError as e:
        results.append((m, f"MISSING: {e}"))
    except Exception as e:
        # RuntimeError / OSError on CUDA-less hosts is expected (warnings only).
        results.append((m, f"warn (runtime): {e.__class__.__name__}"))
for m in optional:
    try:
        importlib.import_module(m)
        results.append((m, "ok (optional)"))
    except ImportError:
        results.append((m, "absent (optional)"))
    except Exception as e:
        results.append((m, f"warn (optional, runtime): {e.__class__.__name__}"))
for m, r in results:
    print(f"  {m:18s} {r}")
missing = [m for m, r in results if r.startswith("MISSING")]
if missing:
    sys.exit(f"required CV modules failed to install: {missing}")
PY

log "CV/multimodal stack ready (profile=${AURUM_PROFILE})"
