#!/usr/bin/env bash
# ==============================================================================
# Wave 8/9 — orchestrator that runs every Wave 8/9 test_*.sh and reports a
# pass / fail / skip summary.
#
# Exits 0 if every test PASS or SKIP, 1 if any FAIL.
#
# Usage:
#   bash tests/run-wave-8-9-smoke.sh
#   bash tests/run-wave-8-9-smoke.sh --json
# ==============================================================================

set -u

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${TESTS_DIR}/.." && pwd)"

JSON=0
for a in "${@:-}"; do
    case "${a}" in
        --json) JSON=1 ;;
        *) ;;
    esac
done

if [[ -t 1 && ${JSON} -eq 0 ]]; then
    GRN=$'\e[32m'; RED=$'\e[31m'; YEL=$'\e[33m'; CYA=$'\e[36m'; BLD=$'\e[1m'; RST=$'\e[0m'
else
    GRN=; RED=; YEL=; CYA=; BLD=; RST=
fi

# Test files in execution order.
TESTS=(
    test_hardware_profile.sh
    test_model_packs.sh
    test_llm_workflows.sh
    test_ai_coding.sh
    test_observability.sh
    test_cv_multimodal.sh
)

declare -a RESULTS  # "STATUS|NAME|DURATION_MS"

PASS_N=0; SKIP_N=0; FAIL_N=0

for t in "${TESTS[@]}"; do
    script="${TESTS_DIR}/${t}"
    if [[ ! -f "${script}" ]]; then
        RESULTS+=("MISSING|${t}|0")
        FAIL_N=$((FAIL_N+1))
        continue
    fi

    [[ ${JSON} -eq 0 ]] && echo "${BLD}${CYA}── running ${t} ──${RST}"

    start=$(date +%s%3N 2>/dev/null || date +%s)
    bash "${script}" </dev/null
    rc=$?
    end=$(date +%s%3N 2>/dev/null || date +%s)
    dur=$((end - start))

    case "${rc}" in
        0)  RESULTS+=("PASS|${t}|${dur}"); PASS_N=$((PASS_N+1)) ;;
        77) RESULTS+=("SKIP|${t}|${dur}"); SKIP_N=$((SKIP_N+1)) ;;
        *)  RESULTS+=("FAIL|${t}|${dur}"); FAIL_N=$((FAIL_N+1)) ;;
    esac
    [[ ${JSON} -eq 0 ]] && echo
done

# ── report ────────────────────────────────────────────────────────────────────
if [[ ${JSON} -eq 1 ]]; then
    echo "{"
    echo "  \"summary\": {\"pass\": ${PASS_N}, \"skip\": ${SKIP_N}, \"fail\": ${FAIL_N}, \"total\": $((PASS_N+SKIP_N+FAIL_N))},"
    echo "  \"results\": ["
    first=1
    for r in "${RESULTS[@]}"; do
        IFS='|' read -r s n d <<<"${r}"
        [[ ${first} -eq 0 ]] && echo ","
        first=0
        printf '    {"status":"%s","name":"%s","duration_ms":%s}' "${s}" "${n}" "${d}"
    done
    echo
    echo "  ]"
    echo "}"
else
    echo "${BLD}═══════════════ WAVE 8/9 SMOKE SUMMARY ═══════════════${RST}"
    for r in "${RESULTS[@]}"; do
        IFS='|' read -r s n d <<<"${r}"
        case "${s}" in
            PASS)    tag="${GRN}✓ PASS${RST}" ;;
            SKIP)    tag="${YEL}- SKIP${RST}" ;;
            FAIL)    tag="${RED}✗ FAIL${RST}" ;;
            MISSING) tag="${RED}? MISSING${RST}" ;;
        esac
        printf "  %s  %-35s  %sms\n" "${tag}" "${n}" "${d}"
    done
    echo
    printf "  ${GRN}%d PASS${RST}    ${YEL}%d SKIP${RST}    ${RED}%d FAIL${RST}    (%d total)\n" \
        "${PASS_N}" "${SKIP_N}" "${FAIL_N}" "$((PASS_N+SKIP_N+FAIL_N))"
    echo
    if [[ ${FAIL_N} -eq 0 ]]; then
        echo "${GRN}${BLD}✓ Wave 8/9 stack passes smoke tests.${RST}"
    else
        echo "${RED}${BLD}✗ ${FAIL_N} test(s) failed — see above.${RST}"
    fi
fi

[[ ${FAIL_N} -eq 0 ]] && exit 0 || exit 1
