#!/usr/bin/env bash
# ==============================================================================
# AurumOS — Modern LLM serving stack (Wave 8 / Agent B)
#
# Installs four OpenAI-compatible model servers:
#
#   1. LiteLLM proxy   — universal API gateway; fans out OpenAI-shape requests
#                        to OpenAI / Anthropic / Ollama / local servers. Tiny
#                        pure-python install, NO GPU needed → ships on every
#                        profile (including `lite`).
#
#   2. vLLM            — PagedAttention engine; the default high-throughput
#                        server for our RTX 5060 / 4060 / 3060 (8 GB VRAM)
#                        target. Wave 8 launchers prefer AWQ quantization
#                        (Qwen2.5-7B-AWQ fits in ~6 GB VRAM).
#
#   3. SGLang          — RadixAttention-based server with strong structured-
#                        output (JSON-schema) and multi-turn caching wins.
#                        Better than vLLM for agent loops; worse for raw
#                        single-prompt throughput.
#
#   4. TGI             — Hugging Face's Rust binary; the reference server for
#                        HF-hosted weights, ships first-class continuous-
#                        batching and is what most HF demo Spaces run behind
#                        the scenes. We fetch the GitHub release tarball (not
#                        a pip wheel — TGI is Rust, not Python).
#
# Profile gating (sourced from /etc/aurum/profile.conf):
#
#   lite                       -> only LiteLLM. vLLM / SGLang / TGI all need
#                                 a CUDA GPU at runtime and would fail to
#                                 launch on a CPU-only box, so we don't
#                                 even install them — saves ~3 GB of disk.
#   standard|pro|workstation   -> all four.
#
# Docker preview caveat: vLLM ships CUDA-only wheels in 2025. `pip install
# vllm` on a CPU-only chroot fails the wheel resolution. We catch that
# failure and continue — the rest of the install MUST still succeed so the
# ISO build doesn't abort on the preview environment.
#
# `set -uo pipefail` (NOT `-e`) follows the rest of post-install/* — every
# step has its own best-effort handling and a single missing CUDA wheel must
# not abort the whole script.
# ==============================================================================
set -uo pipefail

# --- Paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

VENV_PATH="${VENV_PATH:-/opt/aurum-dl-venv}"
PROFILE_CONF="${PROFILE_CONF:-/etc/aurum/profile.conf}"
PIP_REQS="${PIP_REQS:-}"
ASSETS_DIR="${ASSETS_DIR:-}"
TOOLS_DIR="${TOOLS_DIR:-}"
DESKTOP_DIR="${DESKTOP_DIR:-}"

# Where the LiteLLM YAML lives at runtime (the launcher reads it from here).
ETC_AURUM_DIR="${ETC_AURUM_DIR:-/etc/aurum}"
LITELLM_CONFIG_DST="${LITELLM_CONFIG_DST:-${ETC_AURUM_DIR}/litellm-config.yaml}"

# TGI release we ship. The HF text-generation-inference repo publishes
# pre-built Linux/amd64 binaries on every tagged release; 3.0.x is the
# current line (Dec 2024) and supports both Llama 3 and Qwen 2.5 OOTB.
TGI_VERSION="${TGI_VERSION:-3.0.1}"
TGI_INSTALL_DIR="${TGI_INSTALL_DIR:-/opt/aurum-tgi}"

# --- Logging -----------------------------------------------------------------
log()  { echo -e "\e[34m[serving]\e[0m $*"; }
warn() { echo -e "\e[33m[serving]\e[0m $*" >&2; }
skip() { echo -e "\e[36m[serving]\e[0m SKIP — $*"; }
err()  { echo -e "\e[31m[serving]\e[0m $*" >&2; }

# --- Path resolution ---------------------------------------------------------
resolve_paths() {
    if [[ -z "${PIP_REQS}" ]]; then
        for candidate in \
            /tmp/aurum/distro/packages/pip-requirements-serving.txt \
            /tmp/packages/pip-requirements-serving.txt \
            /etc/aurum/pip-requirements-serving.txt \
            "${REPO_ROOT}/distro/packages/pip-requirements-serving.txt" \
            "${SCRIPT_DIR}/../packages/pip-requirements-serving.txt"; do
            if [[ -f "${candidate}" ]]; then PIP_REQS="${candidate}"; break; fi
        done
    fi
    if [[ -z "${ASSETS_DIR}" ]]; then
        for candidate in \
            /tmp/aurum/distro/assets \
            /tmp/aurum-assets \
            "${REPO_ROOT}/distro/assets" \
            "${SCRIPT_DIR}/../assets"; do
            if [[ -f "${candidate}/litellm-config.yaml" ]]; then
                ASSETS_DIR="${candidate}"; break
            fi
        done
    fi
    if [[ -z "${TOOLS_DIR}" ]]; then
        for candidate in \
            /tmp/aurum/tools \
            "${REPO_ROOT}/tools" \
            "${SCRIPT_DIR}/../../tools"; do
            if [[ -f "${candidate}/aurum-launch-litellm" ]]; then
                TOOLS_DIR="${candidate}"; break
            fi
        done
    fi
    if [[ -z "${DESKTOP_DIR}" ]]; then
        for candidate in \
            /tmp/aurum/desktop/applications \
            "${REPO_ROOT}/desktop/applications" \
            "${SCRIPT_DIR}/../../desktop/applications"; do
            if [[ -f "${candidate}/aurum-litellm.desktop" ]]; then
                DESKTOP_DIR="${candidate}"; break
            fi
        done
    fi
}

# --- Profile sourcing --------------------------------------------------------
# In the Docker preview /etc/aurum/profile.conf is absent; fall through to
# `lite` so the script behaves like the GPU-less default it represents.
#
# Note: set -a and set +a are split onto separate lines so the linter
# honours the source directive below (it ignores it when source is preceded
# by another command on the same line).
source_profile() {
    AURUM_PROFILE="lite"
    if [[ -r "${PROFILE_CONF}" ]]; then
        set -a
        # shellcheck source=/dev/null
        source "${PROFILE_CONF}"
        set +a
        AURUM_PROFILE="${AURUM_PROFILE:-lite}"
    else
        warn "${PROFILE_CONF} missing; assuming AURUM_PROFILE=lite"
    fi
    log "profile: ${AURUM_PROFILE}"
}

# --- Pick a pip --------------------------------------------------------------
# Same resolution order as 06-install-finetuning.sh: prefer the DL venv pip,
# fall back to system python with --break-system-packages.
PIP=""
PIP_FLAGS=("--upgrade" "--prefer-binary" "--no-input")

pick_pip() {
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
        return 3
    fi
}

# --- 1. LiteLLM (always) -----------------------------------------------------
install_litellm() {
    log "installing LiteLLM[proxy] (universal, runs on every profile)..."
    # shellcheck disable=SC2086
    if ${PIP} install "${PIP_FLAGS[@]}" "litellm[proxy]==1.55.3"; then
        log "✓ litellm installed"
    else
        err "litellm install failed — proxy will be unavailable"
        return 1
    fi
}

# --- 2. vLLM (GPU profiles only) ---------------------------------------------
# vLLM ships CUDA-only wheels in 2025. On a CPU-only host the wheel resolution
# fails with `No matching distribution found for vllm`. We tolerate that and
# print a clear message so the user knows why their `aurum-launch-vllm` won't
# work in the Docker preview.
install_vllm() {
    log "installing vLLM (PagedAttention server)..."
    local out
    # shellcheck disable=SC2086
    if out=$(${PIP} install "${PIP_FLAGS[@]}" "vllm==0.6.6.post1" 2>&1); then
        log "✓ vllm installed"
    else
        # Detect the canonical "needs CUDA" failure and downgrade to a warning.
        if echo "${out}" | grep -qiE "no matching distribution|could not find a version|cuda|nvcc"; then
            warn "vllm install skipped (no CUDA wheel for this host)."
            warn "  This is expected in CPU-only environments (Docker preview, CI)."
            warn "  On a real RTX-equipped install this step will succeed."
        else
            err  "vllm install failed for an unexpected reason; see output:"
            echo "${out}" | tail -20 >&2
        fi
    fi
}

# --- 3. SGLang (GPU profiles only) -------------------------------------------
install_sglang() {
    log "installing SGLang (RadixAttention server)..."
    local out
    # shellcheck disable=SC2086
    if out=$(${PIP} install "${PIP_FLAGS[@]}" "sglang==0.3.6" 2>&1); then
        log "✓ sglang installed"
    else
        if echo "${out}" | grep -qiE "no matching distribution|could not find a version|cuda|nvcc|flashinfer"; then
            warn "sglang install skipped (depends on CUDA-only flashinfer wheel)."
            warn "  Expected in CPU-only environments. Will install fine on RTX hardware."
        else
            err  "sglang install failed unexpectedly; see output:"
            echo "${out}" | tail -20 >&2
        fi
    fi
}

# --- 4. TGI (GPU profiles only, Rust binary fetched out-of-band) -------------
# We don't unpack the actual tarball here because the HF release archive is
# large (~300 MB) and the ISO chroot may have no network. Instead we drop a
# stub script that pulls the binary lazily on first launch. This pattern
# matches lms (03-install-llm-runtimes.sh).
install_tgi() {
    log "installing TGI fetcher stub at ${TGI_INSTALL_DIR}..."
    if [[ "$(uname -m)" != "x86_64" ]]; then
        warn "TGI prebuilt binaries are amd64-only; skipping fetcher stub"
        return 0
    fi
    install -d -m 0755 "${TGI_INSTALL_DIR}"
    cat > "${TGI_INSTALL_DIR}/fetch-tgi.sh" <<EOF
#!/usr/bin/env bash
# Lazy TGI binary fetcher (created by 07-install-llm-serving.sh).
# Run on first use of aurum-launch-tgi if /opt/aurum-tgi/text-generation-launcher
# is missing.
set -euo pipefail
TGI_VERSION="${TGI_VERSION}"
url="https://github.com/huggingface/text-generation-inference/releases/download/v\${TGI_VERSION}/text-generation-inference-\${TGI_VERSION}-x86_64-linux.tar.gz"
echo "[tgi] downloading TGI \${TGI_VERSION} from \${url}" >&2
tmp=\$(mktemp -d)
trap 'rm -rf "\${tmp}"' EXIT
curl -fL --retry 3 -o "\${tmp}/tgi.tar.gz" "\${url}"
tar -xzf "\${tmp}/tgi.tar.gz" -C "${TGI_INSTALL_DIR}" --strip-components=1
chmod +x "${TGI_INSTALL_DIR}/text-generation-launcher" 2>/dev/null || true
echo "[tgi] installed to ${TGI_INSTALL_DIR}" >&2
EOF
    chmod 0755 "${TGI_INSTALL_DIR}/fetch-tgi.sh"
    log "✓ TGI fetcher stub installed (binary downloads on first launch)"
}

# --- LiteLLM config ----------------------------------------------------------
install_litellm_config() {
    if [[ -z "${ASSETS_DIR}" ]]; then
        warn "ASSETS_DIR not resolved; skipping litellm-config.yaml install"
        return 0
    fi
    local src="${ASSETS_DIR}/litellm-config.yaml"
    if [[ ! -f "${src}" ]]; then
        warn "${src} not found; skipping"
        return 0
    fi
    install -d -m 0755 "${ETC_AURUM_DIR}"
    if install -m 0644 "${src}" "${LITELLM_CONFIG_DST}" 2>/dev/null; then
        log "✓ wrote ${LITELLM_CONFIG_DST}"
    else
        warn "cannot write ${LITELLM_CONFIG_DST} (need root?); copy manually with:"
        warn "  sudo install -D -m 0644 ${src} ${LITELLM_CONFIG_DST}"
    fi
}

# --- Launchers + .desktop entries (best-effort copy) -------------------------
# In production these are installed by distro/assets/install-assets.sh; we
# replicate the install here so a chrooted `bash 07-install-llm-serving.sh`
# leaves a working system without depending on later script numbers.
install_launchers() {
    if [[ -z "${TOOLS_DIR}" ]]; then
        warn "TOOLS_DIR not resolved; skipping /usr/local/bin install"
        return 0
    fi
    install -d -m 0755 /usr/local/bin 2>/dev/null || true
    for launcher in aurum-launch-vllm aurum-launch-sglang aurum-launch-tgi aurum-launch-litellm; do
        local src="${TOOLS_DIR}/${launcher}"
        if [[ -f "${src}" ]]; then
            if install -m 0755 "${src}" "/usr/local/bin/${launcher}" 2>/dev/null; then
                log "✓ installed /usr/local/bin/${launcher}"
            else
                warn "could not install ${launcher} to /usr/local/bin (need root?)"
            fi
        fi
    done
}

install_desktop_entries() {
    if [[ -z "${DESKTOP_DIR}" ]]; then
        warn "DESKTOP_DIR not resolved; skipping .desktop install"
        return 0
    fi
    install -d -m 0755 /usr/share/applications 2>/dev/null || true
    for entry in aurum-vllm.desktop aurum-sglang.desktop aurum-tgi.desktop aurum-litellm.desktop; do
        local src="${DESKTOP_DIR}/${entry}"
        if [[ -f "${src}" ]]; then
            if install -m 0644 "${src}" "/usr/share/applications/${entry}" 2>/dev/null; then
                log "✓ installed /usr/share/applications/${entry}"
            else
                warn "could not install ${entry} to /usr/share/applications (need root?)"
            fi
        fi
    done
}

# --- Main --------------------------------------------------------------------
main() {
    resolve_paths
    source_profile
    pick_pip || exit $?

    # 1. LiteLLM — universal, always installed.
    install_litellm

    # 2/3/4. GPU servers — profile-gated.
    case "${AURUM_PROFILE}" in
        lite)
            skip "vLLM / SGLang / TGI on profile=lite (all require an NVIDIA GPU at runtime)."
            log  "  LiteLLM proxy alone is enough for cloud-routed inference + Ollama fan-out."
            ;;
        standard|pro|workstation)
            install_vllm
            install_sglang
            install_tgi
            ;;
        *)
            warn "unknown profile '${AURUM_PROFILE}'; treating as standard"
            install_vllm
            install_sglang
            install_tgi
            ;;
    esac

    install_litellm_config
    install_launchers
    install_desktop_entries

    log "LLM serving stack ready (profile=${AURUM_PROFILE})"
    log "  → litellm:  aurum-launch-litellm  (port 4000, OpenAI-shape fan-out)"
    case "${AURUM_PROFILE}" in
        standard|pro|workstation)
            log "  → vllm:     aurum-launch-vllm     (port 8000)"
            log "  → sglang:   aurum-launch-sglang   (port 30000)"
            log "  → tgi:      aurum-launch-tgi      (port 8080)"
            ;;
    esac
}

main "$@"
