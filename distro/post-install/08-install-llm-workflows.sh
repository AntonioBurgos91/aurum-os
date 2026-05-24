#!/usr/bin/env bash
# ==============================================================================
# AurumOS - LLM workflow libraries (Wave 8)
#
# Installs the declarative-prompt + structured-output + MCP libraries that the
# 2025-2026 AI-engineering paradigm assumes: DSPy, Instructor, Outlines,
# Guidance, Pydantic-AI, and Anthropic's MCP SDK.
#
# Unlike the DL stack (02-install-dl-stack.sh) these libraries do NOT run
# models - they orchestrate them. The combined wheel set is < 50 MB and they
# work on every profile (lite -> workstation), because inference still happens
# in Ollama / LiteLLM / a remote API. That means we install them ONCE,
# unconditionally, regardless of /etc/aurum/profile.conf.
#
# Install strategy:
#   1. If /opt/aurum-dl-venv exists (production ISO path), install INTO it so
#      `python3 -c 'import dspy'` works from any login shell that has the
#      aurum-dl.sh profile snippet sourced.
#   2. Otherwise (CI / dev containers / minimal Docker images) fall back to
#      `pip install --break-system-packages` on the system python3, matching
#      the Wave 7 LiteLLM proxy installer pattern. The resulting site-packages
#      lives under /usr/lib/python3.*/dist-packages and is import-resolvable
#      from any python3 invocation.
#
# Idempotent: a re-run hits pip's wheel cache and is a no-op if every floor is
# already satisfied.
# ==============================================================================

set -euo pipefail

VENV_PATH="${VENV_PATH:-/opt/aurum-dl-venv}"
REQS="${REQS:-}"

log()  { echo -e "\e[34m[workflows]\e[0m $*"; }
warn() { echo -e "\e[33m[workflows]\e[0m $*" >&2; }
die()  { echo -e "\e[31m[workflows]\e[0m $*" >&2; exit 1; }

resolve_requirements() {
    if [[ -n "${REQS}" && -f "${REQS}" ]]; then return 0; fi
    for candidate in \
        /tmp/aurum/distro/packages/pip-requirements-workflows.txt \
        /tmp/packages/pip-requirements-workflows.txt \
        /etc/aurum/pip-requirements-workflows.txt \
        ./distro/packages/pip-requirements-workflows.txt \
        "$(dirname "${BASH_SOURCE[0]}")/../packages/pip-requirements-workflows.txt"; do
        if [[ -f "${candidate}" ]]; then
            REQS="${candidate}"
            return 0
        fi
    done
    die "pip-requirements-workflows.txt not found in any known location"
}

install_into_venv() {
    log "installing into existing venv at ${VENV_PATH}..."
    if command -v uv >/dev/null 2>&1; then
        uv pip install --python "${VENV_PATH}/bin/python" \
                       ${UV_NO_CACHE:+--no-cache} \
                       -r "${REQS}"
    else
        # uv missing — fall back to the venv's own pip. Slower but functional.
        "${VENV_PATH}/bin/python" -m pip install --upgrade pip
        "${VENV_PATH}/bin/python" -m pip install -r "${REQS}"
    fi
}

install_system() {
    log "no venv at ${VENV_PATH}; installing to system python3 with --break-system-packages"
    # Matches Wave 7 pattern. PEP 668 marks Ubuntu 24.04 / Pop!_OS 24.04 as
    # externally-managed; --break-system-packages is the documented opt-out for
    # distro-level installers like this one.
    python3 -m pip install --break-system-packages --upgrade pip
    python3 -m pip install --break-system-packages -r "${REQS}"
}

verify_imports() {
    log "verifying imports..."
    local python_bin
    if [[ -x "${VENV_PATH}/bin/python" ]]; then
        python_bin="${VENV_PATH}/bin/python"
    else
        python_bin="$(command -v python3)"
    fi
    "${python_bin}" - <<'PY'
import importlib, sys
modules = [
    ("dspy",        "DSPy"),
    ("instructor",  "Instructor"),
    ("outlines",    "Outlines"),
    ("guidance",    "Guidance"),
    ("pydantic_ai", "Pydantic-AI"),
    ("litellm",     "LiteLLM"),
    ("mcp",         "MCP"),
]
missing = []
for mod, label in modules:
    try:
        importlib.import_module(mod)
        print(f"  ok  {label:14s} ({mod})")
    except Exception as e:
        missing.append(f"{label} ({mod}): {e!r}")
        print(f"  FAIL {label:14s} ({mod}): {e!r}")
if missing:
    sys.exit("import failures: " + "; ".join(missing))
PY
}

main() {
    resolve_requirements
    log "requirements file: ${REQS}"
    if [[ -x "${VENV_PATH}/bin/python" ]]; then
        install_into_venv
    else
        install_system
    fi
    verify_imports
    log "LLM workflow libraries ready"
}

main "$@"
