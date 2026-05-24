#!/usr/bin/env bash
# ==============================================================================
# Wave 8/9 — LLM workflows test
#
# Asserts:
#   1. `python3 -c 'import dspy, instructor, outlines, pydantic_ai'` succeeds.
#   2. The MCP server template lives at recipes/mcp/templates/python-server/.
#
# Exit codes: 0 ok, 1 failed, 77 skip
# ==============================================================================

set -u

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -t 1 ]]; then
    GRN=$'\e[32m'; RED=$'\e[31m'; YEL=$'\e[33m'; BLD=$'\e[1m'; RST=$'\e[0m'
else
    GRN=; RED=; YEL=; BLD=; RST=
fi

PASS=0; FAIL=0; SKIPN=0
pass() { echo "  ${GRN}PASS${RST} $1"; PASS=$((PASS+1)); }
fail() { echo "  ${RED}FAIL${RST} $1${2:+ ($2)}"; FAIL=$((FAIL+1)); }
skip() { echo "  ${YEL}SKIP${RST} $1"; SKIPN=$((SKIPN+1)); }

echo "${BLD}[test_llm_workflows.sh]${RST}"

# Prefer the DL venv if it exists (production ISO), otherwise system python3.
PYTHON_BIN=""
for cand in /opt/aurum-dl-venv/bin/python python3; do
    if command -v "${cand}" >/dev/null 2>&1; then PYTHON_BIN="${cand}"; break; fi
done

if [[ -z "${PYTHON_BIN}" ]]; then
    echo "  ${RED}FAIL${RST} no python3 on PATH"
    exit 1
fi
pass "using python: ${PYTHON_BIN}"

# 1. Imports.
IMPORT_OUT=$("${PYTHON_BIN}" - <<'PY' 2>&1
import importlib, sys
mods = ["dspy", "instructor", "outlines", "pydantic_ai"]
errors = {}
for m in mods:
    try:
        importlib.import_module(m)
        print(f"OK {m}")
    except Exception as e:
        errors[m] = repr(e)
        print(f"FAIL {m}: {e!r}")
sys.exit(0 if not errors else 1)
PY
)
IMPORT_RC=$?
echo "${IMPORT_OUT}" | sed 's/^/    /'
if [[ ${IMPORT_RC} -eq 0 ]]; then
    pass "dspy, instructor, outlines, pydantic_ai all importable"
else
    # On lite docker preview these may legitimately be missing.
    if [[ "${AURUM_PROFILE:-}" == "lite" ]]; then
        skip "workflow libs missing on lite (expected in CPU preview)"
    else
        fail "one or more workflow libs failed to import"
    fi
fi

# 2. MCP server template.
MCP_PATH="${PROJECT_ROOT}/recipes/mcp/templates/python-server"
if [[ -d "${MCP_PATH}" ]]; then
    pass "MCP python-server template exists at ${MCP_PATH#${PROJECT_ROOT}/}"
    # Bonus: directory should contain at least one .py file.
    if ls "${MCP_PATH}"/*.py >/dev/null 2>&1; then
        pass "MCP template has at least one .py file"
    else
        fail "MCP template directory empty (no .py files)"
    fi
else
    fail "MCP python-server template missing" "expected at recipes/mcp/templates/python-server/"
fi

echo
if [[ ${FAIL} -eq 0 ]]; then
    echo "  ${GRN}${BLD}OK${RST}  ${PASS} passed, ${SKIPN} skipped"
    exit 0
else
    echo "  ${RED}${BLD}FAIL${RST}  ${PASS} passed, ${SKIPN} skipped, ${FAIL} failed"
    exit 1
fi
