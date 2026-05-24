#!/usr/bin/env bash
# ==============================================================================
# AurumOS — LLM observability + eval stack installer (Wave 8, Agent E)
#
# Two-track install:
#   1. Pip libs (Langfuse SDK, Phoenix, TruLens, Ragas, DeepEval, OpenInference
#      instrumentors) — installed on EVERY profile. They are small and the
#      recipes in recipes/observability/ + recipes/eval/ are usable even on
#      `lite` boxes (they can target cloud.langfuse.com instead of a local
#      Langfuse server).
#
#   2. Self-hosted Langfuse via docker-compose — installed on standard|pro|
#      workstation only. Lite users get pointed at cloud.langfuse.com.
#
# DinD note: the Docker preview chroot runs Docker-inside-Docker. `docker
# compose pull` may fail there because nested daemons aren't always wired up.
# We log a warning and continue — the compose file is written either way so
# the user gets a working setup when they install AurumOS on bare metal.
# ==============================================================================
set -euo pipefail

# --- Paths -------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PIP_REQS="${PIP_REQS:-${REPO_ROOT}/distro/packages/pip-requirements-observability.txt}"
COMPOSE_SRC="${COMPOSE_SRC:-${REPO_ROOT}/distro/assets/langfuse-docker-compose.yml}"
LANGFUSE_DIR="${LANGFUSE_DIR:-/opt/aurum-langfuse}"
LANGFUSE_STATE_DIR="${LANGFUSE_STATE_DIR:-/var/lib/aurum-langfuse}"

# --- Logging -----------------------------------------------------------------
log()  { echo -e "\e[34m[observability]\e[0m $*"; }
warn() { echo -e "\e[33m[observability]\e[0m $*" >&2; }
die()  { echo -e "\e[31m[observability]\e[0m $*" >&2; exit 1; }

# --- Profile -----------------------------------------------------------------
# /etc/aurum/profile.conf is bash-sourceable; we tolerate its absence so this
# script also runs on minimal CI containers and on developer laptops that
# haven't yet rebooted with the profile detection service active.
load_profile() {
    if [[ -r /etc/aurum/profile.conf ]]; then
        # shellcheck disable=SC1091
        source /etc/aurum/profile.conf
    fi
    AURUM_PROFILE="${AURUM_PROFILE:-lite}"
    log "profile: ${AURUM_PROFILE}"
}

# --- Pip install -------------------------------------------------------------
# We prefer the AurumOS system venv at /opt/aurum-dl-venv (Wave 6) if it
# exists — that's where Jupyter and the other DL tools live, and users running
# `aurum-eval` from a vanilla shell pick up that venv via /etc/profile.d.
# Fall back to system python3 with --break-system-packages so this also works
# in CI containers and on stock Debian/Ubuntu boxes without the DL venv.
install_pip_libs() {
    [[ -f "${PIP_REQS}" ]] || die "pip requirements not found: ${PIP_REQS}"

    local pip_cmd=()
    if [[ -x /opt/aurum-dl-venv/bin/pip ]]; then
        log "installing into /opt/aurum-dl-venv (system DL venv)..."
        pip_cmd=(/opt/aurum-dl-venv/bin/pip install --prefer-binary -r "${PIP_REQS}")
    else
        log "installing system-wide (no /opt/aurum-dl-venv detected)..."
        pip_cmd=(python3 -m pip install --break-system-packages --prefer-binary -r "${PIP_REQS}")
    fi

    if ! "${pip_cmd[@]}"; then
        die "pip install failed — see output above"
    fi

    verify_imports
}

# Sanity-check that the libs we just installed actually import. This catches
# wheel/abi mismatches (Phoenix has historically shipped wheels with strict
# numpy floors that conflict with /opt/aurum-dl-venv's existing torch wheel).
verify_imports() {
    local py
    if [[ -x /opt/aurum-dl-venv/bin/python ]]; then
        py=/opt/aurum-dl-venv/bin/python
    else
        py=python3
    fi
    log "verifying imports with ${py}..."
    "${py}" - <<'PY' || die "post-install import check failed"
import importlib, sys
# The pip distribution name vs top-level Python module name can diverge:
#   * trulens 1.x ships as `trulens` distribution but the importable
#     surface is `trulens.core` (the bare `trulens` namespace package
#     re-exports nothing on its own in some builds).
#   * arize-phoenix imports as `phoenix`.
# We probe a representative top-level import for each package and tolerate
# trulens being importable via either `trulens` or `trulens.core`.
probes = {
    "langfuse": ["langfuse"],
    "phoenix":  ["phoenix"],
    "trulens":  ["trulens.core", "trulens"],
    "ragas":    ["ragas"],
    "deepeval": ["deepeval"],
}
missing = []
for label, candidates in probes.items():
    last_err = None
    for mod in candidates:
        try:
            importlib.import_module(mod)
            last_err = None
            break
        except Exception as e:
            last_err = f"{mod}: {type(e).__name__}: {e}"
    if last_err is not None:
        missing.append(f"{label} → {last_err}")
if missing:
    print("MISSING:\n  " + "\n  ".join(missing), file=sys.stderr)
    sys.exit(1)
print(f"import OK: {', '.join(probes.keys())}")
PY
}

# --- Self-hosted Langfuse (standard+) ----------------------------------------
install_langfuse_stack() {
    install -d -m 0755 "${LANGFUSE_DIR}"
    install -d -m 0755 "${LANGFUSE_STATE_DIR}/db"
    cp "${COMPOSE_SRC}" "${LANGFUSE_DIR}/docker-compose.yml"

    # Generate .env with fresh random secrets if one doesn't already exist.
    # Preserving an existing .env on re-run is important — overwriting NEXTAUTH_
    # SECRET invalidates every login session, and overwriting SALT corrupts
    # API keys stored in the database.
    if [[ ! -f "${LANGFUSE_DIR}/.env" ]]; then
        log "generating ${LANGFUSE_DIR}/.env with fresh secrets..."
        local nextauth_secret salt
        nextauth_secret="$(openssl rand -hex 32)"
        salt="$(openssl rand -hex 32)"
        cat > "${LANGFUSE_DIR}/.env" <<EOF
# Auto-generated by 10-install-observability.sh — see langfuse-env.template
# for documentation of each key.
NEXTAUTH_SECRET=${nextauth_secret}
SALT=${salt}
NEXTAUTH_URL=http://localhost:3030
LANGFUSE_INIT_ORG_ID=aurum
LANGFUSE_INIT_USER_EMAIL=admin@aurum.local
LANGFUSE_INIT_USER_PASSWORD=aurum-default-changeme
EOF
        chmod 600 "${LANGFUSE_DIR}/.env"
    else
        log "${LANGFUSE_DIR}/.env already exists; preserving"
    fi

    # Pre-pull images so the first user-facing launch is fast (no 600 MB
    # download blocking the splash screen). Best-effort — if Docker isn't
    # available (DinD preview chroot, CI sandbox), warn and continue.
    if ! command -v docker >/dev/null 2>&1; then
        warn "docker not on PATH — skipping image pull (compose file still written)"
        return 0
    fi

    log "pulling Langfuse + postgres images..."
    if ! docker compose -f "${LANGFUSE_DIR}/docker-compose.yml" --env-file "${LANGFUSE_DIR}/.env" pull 2>&1; then
        warn "docker compose pull failed — likely a DinD or daemon-not-running"
        warn "issue. The compose file is in place; on bare metal the first"
        warn "  cd ${LANGFUSE_DIR} && docker compose up -d"
        warn "will fetch the images."
    fi
}

# --- Main --------------------------------------------------------------------
main() {
    load_profile

    # Always install pip libs — they're small (~150 MB total) and the recipes
    # they unlock are profile-agnostic.
    install_pip_libs

    case "${AURUM_PROFILE}" in
        lite)
            log "lite profile: skipping self-hosted Langfuse Docker stack."
            log "  → use cloud Langfuse: https://cloud.langfuse.com (free tier"
            log "    covers most personal projects). Set these env vars in"
            log "    ~/.profile to route the Python SDK there:"
            log "      export LANGFUSE_PUBLIC_KEY=pk-..."
            log "      export LANGFUSE_SECRET_KEY=sk-..."
            log "      export LANGFUSE_HOST=https://cloud.langfuse.com"
            ;;
        standard|pro|workstation)
            log "${AURUM_PROFILE} profile: installing self-hosted Langfuse..."
            install_langfuse_stack
            log "Langfuse stack ready at ${LANGFUSE_DIR}"
            log "  → launch:  aurum-launch-langfuse"
            log "  → web UI:  http://localhost:3030"
            ;;
        *)
            warn "unknown profile '${AURUM_PROFILE}' — treating as lite (no Docker stack)"
            ;;
    esac

    log "done"
}

main "$@"
