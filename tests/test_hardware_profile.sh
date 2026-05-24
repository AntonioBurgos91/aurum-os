#!/usr/bin/env bash
# ==============================================================================
# Wave 8/9 — Hardware profile detection test
#
# Asserts that distro/post-install/00-detect-profile.sh:
#   1. runs and exits 0 with --print
#   2. emits AURUM_PROFILE=<one of lite|standard|pro|workstation>
#   3. emits AURUM_VRAM_MB=<integer>
#   4. emits AURUM_RAM_GB=<integer>
#
# Exit codes:
#   0 — all asserts passed
#   1 — at least one assert failed
#   77 — SKIP (script not present on this filesystem)
# ==============================================================================

set -u  # No -e: we want to keep running after a failed assert.

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="${PROJECT_ROOT}/distro/post-install/00-detect-profile.sh"

# Colours.
if [[ -t 1 ]]; then
    GRN=$'\e[32m'; RED=$'\e[31m'; YEL=$'\e[33m'; BLD=$'\e[1m'; RST=$'\e[0m'
else
    GRN=; RED=; YEL=; BLD=; RST=
fi

PASS=0; FAIL=0
pass() { echo "  ${GRN}PASS${RST} $1"; PASS=$((PASS+1)); }
fail() { echo "  ${RED}FAIL${RST} $1${2:+ ($2)}"; FAIL=$((FAIL+1)); }

echo "${BLD}[test_hardware_profile.sh]${RST}"

if [[ ! -f "${SCRIPT}" ]]; then
    echo "  ${YEL}SKIP${RST} ${SCRIPT} missing (Agent G output not present)"
    exit 77
fi

# Run --print on a temp profile path so we don't need /etc write perms.
TMPCONF=$(mktemp -t aurum-profile.XXXXXX)
OUT=$(AURUM_PROFILE_CONF="${TMPCONF}" bash "${SCRIPT}" --print 2>&1)
RC=$?

if [[ ${RC} -eq 0 ]]; then
    pass "script exited 0 with --print"
else
    fail "script exited ${RC}" "$(echo "${OUT}" | head -3)"
fi

# 1. AURUM_PROFILE= present.
if echo "${OUT}" | grep -qE '^AURUM_PROFILE='; then
    pass "AURUM_PROFILE= line present"
else
    fail "AURUM_PROFILE= line missing"
fi

# 2. AURUM_PROFILE value is one of the four valid tiers.
TIER=$(echo "${OUT}" | grep -E '^AURUM_PROFILE=' | head -1 | cut -d= -f2 | tr -d '"')
case "${TIER}" in
    lite|standard|pro|workstation)
        pass "AURUM_PROFILE=${TIER} is valid"
        ;;
    *)
        fail "AURUM_PROFILE=${TIER} not one of lite|standard|pro|workstation"
        ;;
esac

# 3. AURUM_VRAM_MB is an integer.
VRAM=$(echo "${OUT}" | grep -E '^AURUM_VRAM_MB=' | head -1 | cut -d= -f2)
if [[ "${VRAM}" =~ ^[0-9]+$ ]]; then
    pass "AURUM_VRAM_MB=${VRAM} is integer"
else
    fail "AURUM_VRAM_MB=${VRAM:-<missing>} not integer"
fi

# 4. AURUM_RAM_GB is an integer.
RAM=$(echo "${OUT}" | grep -E '^AURUM_RAM_GB=' | head -1 | cut -d= -f2)
if [[ "${RAM}" =~ ^[0-9]+$ ]]; then
    pass "AURUM_RAM_GB=${RAM} is integer"
else
    fail "AURUM_RAM_GB=${RAM:-<missing>} not integer"
fi

# 5. AURUM_HAS_CUDA is 0 or 1.
HAS_CUDA=$(echo "${OUT}" | grep -E '^AURUM_HAS_CUDA=' | head -1 | cut -d= -f2)
if [[ "${HAS_CUDA}" == "0" || "${HAS_CUDA}" == "1" ]]; then
    pass "AURUM_HAS_CUDA=${HAS_CUDA} is boolean"
else
    fail "AURUM_HAS_CUDA=${HAS_CUDA:-<missing>} not 0|1"
fi

rm -f "${TMPCONF}"

echo
if [[ ${FAIL} -eq 0 ]]; then
    echo "  ${GRN}${BLD}OK${RST}  ${PASS} passed"
    exit 0
else
    echo "  ${RED}${BLD}FAIL${RST}  ${PASS} passed, ${FAIL} failed"
    exit 1
fi
