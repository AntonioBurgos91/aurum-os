#!/usr/bin/env bash
# ==============================================================================
# Wave 8/9 — LLM observability + eval test
#
# Asserts:
#   `python3 -c 'import langfuse, phoenix, trulens, ragas, deepeval'` succeeds.
#
# Some imports legitimately fail on lite (the Docker preview installs the pure
# pip libs but Langfuse self-host needs Docker-in-Docker which isn't available).
# Gate the assertion on /etc/aurum/profile.conf:AURUM_PROFILE.
#
# Exit codes: 0 ok, 1 failed, 77 skip
# ==============================================================================

set -u

if [[ -t 1 ]]; then
    GRN=$'\e[32m'; RED=$'\e[31m'; YEL=$'\e[33m'; BLD=$'\e[1m'; RST=$'\e[0m'
else
    GRN=; RED=; YEL=; BLD=; RST=
fi

PASS=0; FAIL=0; SKIPN=0
pass() { echo "  ${GRN}PASS${RST} $1"; PASS=$((PASS+1)); }
fail() { echo "  ${RED}FAIL${RST} $1${2:+ ($2)}"; FAIL=$((FAIL+1)); }
skip() { echo "  ${YEL}SKIP${RST} $1"; SKIPN=$((SKIPN+1)); }

echo "${BLD}[test_observability.sh]${RST}"

# Resolve profile (so we know whether to expect Langfuse to run).
PROFILE="${AURUM_PROFILE:-unknown}"
if [[ "${PROFILE}" == "unknown" && -r /etc/aurum/profile.conf ]]; then
    # shellcheck disable=SC1091
    PROFILE=$(grep -E '^AURUM_PROFILE=' /etc/aurum/profile.conf | cut -d= -f2 | tr -d '"')
fi
PROFILE="${PROFILE:-lite}"
echo "  profile: ${PROFILE}"

# Skip whole script on lite if explicitly requested.
if [[ "${PROFILE}" == "lite" && "${OBSERVABILITY_LITE_FORCE:-}" != "1" ]]; then
    skip "lite profile — observability test runs the pip imports only"
fi

# Pick python interpreter.
PYTHON_BIN=""
for cand in /opt/aurum-dl-venv/bin/python python3; do
    if command -v "${cand}" >/dev/null 2>&1; then PYTHON_BIN="${cand}"; break; fi
done

if [[ -z "${PYTHON_BIN}" ]]; then
    echo "  ${RED}FAIL${RST} no python3 on PATH"
    exit 1
fi

# Imports — names per pip-requirements-observability.txt.
#   langfuse, phoenix (from arize-phoenix), trulens, ragas, deepeval
OUT=$("${PYTHON_BIN}" - <<'PY' 2>&1
import importlib
modules = [
    ("langfuse",  "Langfuse"),
    ("phoenix",   "Arize Phoenix"),
    ("trulens",   "TruLens"),
    ("ragas",     "Ragas"),
    ("deepeval",  "DeepEval"),
]
errors = []
for mod, label in modules:
    try:
        importlib.import_module(mod)
        print(f"OK   {label:15s} ({mod})")
    except Exception as e:
        errors.append((mod, repr(e)))
        print(f"FAIL {label:15s} ({mod}): {e!r}")
exit(0 if not errors else 1)
PY
)
RC=$?
echo "${OUT}" | sed 's/^/    /'

if [[ ${RC} -eq 0 ]]; then
    pass "all 5 observability libs importable"
else
    # On lite, some libs are intentionally not installed.
    if [[ "${PROFILE}" == "lite" ]]; then
        skip "missing libs OK on lite (set OBSERVABILITY_LITE_FORCE=1 to fail strictly)"
    else
        fail "one or more observability libs failed to import"
    fi
fi

# Optional: langfuse docker-compose validates (if docker compose available).
COMPOSE_FILE_CANDIDATES=(
    /etc/aurum/langfuse-docker-compose.yml
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/distro/assets/langfuse-docker-compose.yml"
)
COMPOSE_FILE=""
for f in "${COMPOSE_FILE_CANDIDATES[@]}"; do
    if [[ -f "${f}" ]]; then COMPOSE_FILE="${f}"; break; fi
done
if [[ -n "${COMPOSE_FILE}" ]]; then
    if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        if docker compose -f "${COMPOSE_FILE}" config >/dev/null 2>&1; then
            pass "langfuse-docker-compose.yml validates"
        else
            fail "langfuse-docker-compose.yml failed to validate"
        fi
    else
        skip "docker compose unavailable — can't validate langfuse compose"
    fi
else
    skip "langfuse-docker-compose.yml not found"
fi

echo
if [[ ${FAIL} -eq 0 ]]; then
    echo "  ${GRN}${BLD}OK${RST}  ${PASS} passed, ${SKIPN} skipped"
    exit 0
else
    echo "  ${RED}${BLD}FAIL${RST}  ${PASS} passed, ${SKIPN} skipped, ${FAIL} failed"
    exit 1
fi
