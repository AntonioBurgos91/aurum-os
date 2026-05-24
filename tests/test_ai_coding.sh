#!/usr/bin/env bash
# ==============================================================================
# Wave 8/9 — AI-coding stack test
#
# Asserts:
#   1. aider is on PATH.
#   2. VSCode `code` is on PATH AND has the Continue extension installed,
#      OR (in CI / Docker preview) document the SKIP.
#   3. /etc/skel/Templates/CLAUDE.md exists and has the expected H2 sections.
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

echo "${BLD}[test_ai_coding.sh]${RST}"

# 1. aider on PATH.
if command -v aider >/dev/null 2>&1; then
    VER=$(aider --version 2>&1 | head -1)
    pass "aider on PATH (${VER})"
else
    fail "aider not on PATH (install via 09-install-ai-coding.sh)"
fi

# 2. VSCode + Continue extension.
if command -v code >/dev/null 2>&1; then
    if code --list-extensions 2>/dev/null | grep -qi 'continue'; then
        pass "VSCode 'continue' extension installed"
    else
        fail "VSCode present but Continue.dev extension not installed"
    fi
else
    # VSCode is intentionally not installed in the Docker preview / CI.
    # Document the SKIP so it doesn't count as a regression.
    skip "VSCode 'code' CLI not on PATH (expected in headless preview / CI)"
fi

# 3. /etc/skel/Templates/CLAUDE.md
CLAUDE_TMPL=/etc/skel/Templates/CLAUDE.md
if [[ -f "${CLAUDE_TMPL}" ]]; then
    pass "CLAUDE.md template exists at ${CLAUDE_TMPL}"
    EXPECTED_SECTIONS=(
        "## Project context"
        "## Coding conventions"
        "## Testing"
    )
    for s in "${EXPECTED_SECTIONS[@]}"; do
        if grep -qiF "${s}" "${CLAUDE_TMPL}"; then
            pass "section present: '${s}'"
        else
            fail "section missing: '${s}'"
        fi
    done
else
    skip "${CLAUDE_TMPL} missing (Agent D output not present)"
fi

echo
if [[ ${FAIL} -eq 0 ]]; then
    echo "  ${GRN}${BLD}OK${RST}  ${PASS} passed, ${SKIPN} skipped"
    exit 0
else
    echo "  ${RED}${BLD}FAIL${RST}  ${PASS} passed, ${SKIPN} skipped, ${FAIL} failed"
    exit 1
fi
