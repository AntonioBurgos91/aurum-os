#!/usr/bin/env bash
# AurumOS — AMD/CPU-lite bootstrap para Linux Mint 22.2 + Ryzen 7000 CPU-only
set -euo pipefail

log()  { echo -e "\e[34m[bootstrap]\e[0m $*"; }
warn() { echo -e "\e[33m[bootstrap]\e[0m $*" >&2; }
die()  { echo -e "\e[31m[bootstrap]\e[0m $*" >&2; exit 1; }

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${REPO_ROOT}"

[[ $EUID -ne 0 ]] || die "ejecutar como usuario normal (te pedirá sudo cuando haga falta)"

if ! grep -qE 'Mint|Ubuntu' /etc/os-release; then
    warn "SO no es Mint/Ubuntu — los paquetes APT pueden no estar disponibles"
fi

UBUNTU_CODENAME="$(grep -oP '(?<=^UBUNTU_CODENAME=).+' /etc/os-release || \
                   grep -oP '(?<=^VERSION_CODENAME=).+' /etc/os-release)"
log "codename detectado: ${UBUNTU_CODENAME}"

# --- 1. APT mínimos ---------------------------------------------------------
APT_PKGS=(
    build-essential pkg-config
    cmake meson ninja-build
    git curl wget ca-certificates
    shellcheck
    python3-dev python3-venv
    libssl-dev libudev-dev
)
log "instalando paquetes APT mínimos..."
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends "${APT_PKGS[@]}"

# --- 2. Rust ≥1.85 vía rustup ----------------------------------------------
if command -v rustc >/dev/null 2>&1 && rustc --version | grep -qE '1\.(8[5-9]|9[0-9])'; then
    log "rustc $(rustc --version) ya cumple ≥1.85"
else
    if ! command -v rustup >/dev/null 2>&1; then
        log "instalando rustup..."
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | \
            sh -s -- -y --default-toolchain stable --profile minimal
        # shellcheck disable=SC1091
        source "${HOME}/.cargo/env"
    fi
    rustup default stable
    rustup component add rustfmt clippy
fi

# --- 3. uv (ya lo tienes en 0.10.6) ----------------------------------------
if ! command -v uv >/dev/null 2>&1; then
    log "instalando uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH="${HOME}/.local/bin:${PATH}"
else
    log "uv ya instalado: $(uv --version)"
fi

# --- 4. Detector → /etc/aurum/profile.conf ---------------------------------
log "ejecutando detector de hardware..."
sudo install -d -m 0755 /etc/aurum
sudo bash "${REPO_ROOT}/distro/post-install/00-detect-profile.sh"

if [[ -r /etc/aurum/profile.conf ]]; then
    log "perfil generado:"
    grep -E '^AURUM_(PROFILE|VRAM_MB|RAM_GB|GPU_NAME|HAS_CUDA)=' /etc/aurum/profile.conf | sed 's/^/    /'
    # shellcheck source=/dev/null
    source /etc/aurum/profile.conf
else
    die "no se generó /etc/aurum/profile.conf"
fi

# --- 5. Venv Python con stack CPU-only ------------------------------------
log "creando venv /opt/aurum-dl-venv con pip-requirements-base.txt..."
sudo install -d -m 0755 /tmp/aurum
sudo cp "${REPO_ROOT}/distro/packages/pip-requirements-base.txt" /tmp/aurum/

sudo env AURUM_HAS_CUDA=0 PIP_REQS=/tmp/aurum/pip-requirements-base.txt \
    PATH="${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin" \
    bash "${REPO_ROOT}/distro/post-install/02-install-dl-stack.sh"

# --- 6. Ollama (CPU) -------------------------------------------------------
if ! command -v ollama >/dev/null 2>&1; then
    log "instalando Ollama (CPU mode)..."
    curl -fsSL https://ollama.com/install.sh | sh
else
    log "Ollama ya instalado: $(ollama --version 2>&1 | head -1)"
fi

# --- 7. Smoke ---------------------------------------------------------------
log "smoke tests..."
echo ""
log "  → Rust: $(rustc --version 2>/dev/null || echo NO)"
log "  → Cargo: $(cargo --version 2>/dev/null || echo NO)"
log "  → uv: $(uv --version 2>/dev/null || echo NO)"
log "  → cmake: $(cmake --version 2>/dev/null | head -1 || echo NO)"
log "  → ollama: $(ollama --version 2>&1 | head -1 || echo NO)"
log "  → perfil AurumOS: ${AURUM_PROFILE} (VRAM=${AURUM_VRAM_MB}MB, RAM=${AURUM_RAM_GB}GB)"

echo ""
log "✅ Bootstrap completado."
log ""
log "Siguientes pasos sugeridos:"
log "  1. ollama serve &"
log "  2. ollama pull qwen2.5:1.5b"
log "  3. source /opt/aurum-dl-venv/bin/activate"
log "  4. python -c 'import torch; print(torch.__version__, torch.cuda.is_available())'"
