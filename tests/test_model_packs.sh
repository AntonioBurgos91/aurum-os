#!/usr/bin/env bash
# ==============================================================================
# Wave 8/9 — Model packs test
#
# Asserts:
#   1. distro/assets/model-packs/ (or /etc/aurum/model-packs/) contains the
#      six canonical pack YAMLs: coding, vision, chat, imagegen, speech,
#      workstation.
#   2. Each YAML parses cleanly with python yaml.safe_load.
#   3. `aurum-model-pack list` (if installed) outputs all six packs.
#   4. `aurum-model-pack --json list` (if installed) is valid JSON.
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

echo "${BLD}[test_model_packs.sh]${RST}"

# Prefer installed location (production ISO); fall back to repo asset dir.
PACK_DIRS=(
    /etc/aurum/model-packs
    "${PROJECT_ROOT}/distro/assets/model-packs"
)
PACK_DIR=""
for d in "${PACK_DIRS[@]}"; do
    if [[ -d "${d}" ]]; then PACK_DIR="${d}"; break; fi
done

if [[ -z "${PACK_DIR}" ]]; then
    echo "  ${YEL}SKIP${RST} no model-packs/ dir found (looked in ${PACK_DIRS[*]})"
    exit 77
fi
pass "located pack dir: ${PACK_DIR}"

# 1. Six canonical packs.
EXPECTED=(coding vision chat imagegen speech workstation)
MISSING=()
for p in "${EXPECTED[@]}"; do
    if [[ ! -f "${PACK_DIR}/${p}.yaml" ]]; then
        MISSING+=("${p}")
    fi
done
if [[ ${#MISSING[@]} -eq 0 ]]; then
    pass "all 6 canonical packs present"
else
    fail "${#MISSING[@]} pack(s) missing" "${MISSING[*]}"
fi

# Count yaml files (in case any extras exist).
TOTAL=$(ls -1 "${PACK_DIR}"/*.yaml 2>/dev/null | wc -l)
if [[ "${TOTAL}" -ge 6 ]]; then
    pass "pack dir contains ${TOTAL} yaml files (>=6)"
else
    fail "pack dir only has ${TOTAL} yaml files (<6)"
fi

# 2. Each parses cleanly with PyYAML.
if command -v python3 >/dev/null 2>&1; then
    for y in "${PACK_DIR}"/*.yaml; do
        if python3 -c "import sys, yaml; yaml.safe_load(open('${y}'))" 2>/dev/null; then
            pass "yaml parses: $(basename "${y}")"
        else
            err=$(python3 -c "import yaml; yaml.safe_load(open('${y}'))" 2>&1 | tail -1)
            fail "yaml parse failed: $(basename "${y}")" "${err}"
        fi
    done
else
    skip "python3 not on PATH — cannot validate yaml syntax"
fi

# 3. `aurum-model-pack list` outputs all six packs.
if command -v aurum-model-pack >/dev/null 2>&1; then
    LIST=$(aurum-model-pack list 2>&1 || true)
    MISSING_CLI=()
    for p in "${EXPECTED[@]}"; do
        if ! echo "${LIST}" | grep -qiE "(^|[^a-z])${p}([^a-z]|$)"; then
            MISSING_CLI+=("${p}")
        fi
    done
    if [[ ${#MISSING_CLI[@]} -eq 0 ]]; then
        pass "aurum-model-pack list shows all 6 packs"
    else
        fail "aurum-model-pack list missing packs" "${MISSING_CLI[*]}"
    fi

    # 4. --json list parses.
    JSON=$(aurum-model-pack --json list 2>/dev/null || true)
    if echo "${JSON}" | python3 -c 'import json,sys; json.loads(sys.stdin.read())' 2>/dev/null; then
        pass "aurum-model-pack --json list is valid JSON"
    else
        fail "aurum-model-pack --json list is not valid JSON" "$(echo "${JSON}" | head -c 80)"
    fi
else
    skip "aurum-model-pack CLI not on PATH (Agent I output not installed)"
fi

echo
if [[ ${FAIL} -eq 0 ]]; then
    echo "  ${GRN}${BLD}OK${RST}  ${PASS} passed, ${SKIPN} skipped"
    exit 0
else
    echo "  ${RED}${BLD}FAIL${RST}  ${PASS} passed, ${SKIPN} skipped, ${FAIL} failed"
    exit 1
fi
