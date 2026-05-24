#!/usr/bin/env bash
# ==============================================================================
# Wave 8/9 — CV + multimodal stack test
#
# Asserts:
#   1. ultralytics, diffusers, open_clip import.
#   2. Every JSON file under recipes/comfyui/ (or recipes/cv/comfyui/) parses
#      as valid JSON (ComfyUI workflow files).
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

echo "${BLD}[test_cv_multimodal.sh]${RST}"

PYTHON_BIN=""
for cand in /opt/aurum-dl-venv/bin/python python3; do
    if command -v "${cand}" >/dev/null 2>&1; then PYTHON_BIN="${cand}"; break; fi
done

if [[ -z "${PYTHON_BIN}" ]]; then
    echo "  ${RED}FAIL${RST} no python3 on PATH"
    exit 1
fi

# 1. Imports.
OUT=$("${PYTHON_BIN}" - <<'PY' 2>&1
import importlib
mods = ["ultralytics", "diffusers", "open_clip"]
errors = []
for m in mods:
    try:
        importlib.import_module(m)
        print(f"OK   {m}")
    except Exception as e:
        errors.append((m, repr(e)))
        print(f"FAIL {m}: {e!r}")
exit(0 if not errors else 1)
PY
)
RC=$?
echo "${OUT}" | sed 's/^/    /'
if [[ ${RC} -eq 0 ]]; then
    pass "ultralytics, diffusers, open_clip importable"
else
    if [[ "${AURUM_PROFILE:-lite}" == "lite" ]]; then
        skip "imports missing on lite (acceptable in Docker preview)"
    else
        fail "one or more CV libs failed to import"
    fi
fi

# 2. ComfyUI workflow JSONs.
CANDIDATES=(
    "${PROJECT_ROOT}/recipes/comfyui/workflows"
    "${PROJECT_ROOT}/recipes/comfyui"
    "${PROJECT_ROOT}/recipes/cv/comfyui"
    "${PROJECT_ROOT}/distro/assets/comfyui-workflows"
)
WF_DIR=""
for d in "${CANDIDATES[@]}"; do
    if [[ -d "${d}" ]]; then WF_DIR="${d}"; break; fi
done

if [[ -z "${WF_DIR}" ]]; then
    skip "no ComfyUI workflow dir found (Agent F output may be elsewhere)"
else
    pass "located ComfyUI workflow dir: ${WF_DIR#${PROJECT_ROOT}/}"
    JSONS=( "${WF_DIR}"/*.json )
    if [[ "${JSONS[0]}" == "${WF_DIR}/*.json" ]]; then
        skip "no .json files in ${WF_DIR}"
    else
        for j in "${JSONS[@]}"; do
            if "${PYTHON_BIN}" -c "import json; json.load(open('${j}'))" 2>/dev/null; then
                pass "valid JSON: $(basename "${j}")"
            else
                err=$("${PYTHON_BIN}" -c "import json; json.load(open('${j}'))" 2>&1 | tail -1)
                fail "invalid JSON: $(basename "${j}")" "${err}"
            fi
        done
    fi
fi

echo
if [[ ${FAIL} -eq 0 ]]; then
    echo "  ${GRN}${BLD}OK${RST}  ${PASS} passed, ${SKIPN} skipped"
    exit 0
else
    echo "  ${RED}${BLD}FAIL${RST}  ${PASS} passed, ${SKIPN} skipped, ${FAIL} failed"
    exit 1
fi
