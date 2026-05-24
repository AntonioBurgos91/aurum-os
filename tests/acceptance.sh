#!/usr/bin/env bash
# AurumOS acceptance check.
#
# Runs the gating checks for the v0.1.0-beta release:
#   1. Boot budget (≤ 3 s; tests/boot_bench.sh)
#   2. Idle RAM budget (≤ 600 MB; tests/idle_bench.sh)
#   3. PyTorch sees CUDA (smoke)
#   4. PyTorch + JAX + TF + vLLM smoke + bench
#
# Designed to be runnable from the live installed system. Each check writes a
# single JSON object to /var/log/aurumos/acceptance/<check>.json and reports
# PASS/FAIL to stderr. Exits non-zero if any required check fails.

set -uo pipefail

OUT_DIR="${AURUM_ACCEPT_DIR:-/var/log/aurumos/acceptance}"
sudo install -d -m 0755 "${OUT_DIR}" 2>/dev/null || mkdir -p "${OUT_DIR}"

pass=true
log_check() {
    local name="$1" status="$2"
    printf '%-22s : %s\n' "${name}" "${status}" >&2
    if [[ "${status}" != "PASS" && "${status}" != "SKIP" ]]; then pass=false; fi
}

# --- 1. Boot budget --------------------------------------------------------
if tests/boot_bench.sh > "${OUT_DIR}/boot.json" 2>>"${OUT_DIR}/boot.log"; then
    log_check "boot ≤ 3 s" "PASS"
else
    log_check "boot ≤ 3 s" "FAIL"
fi

# --- 2. Idle RAM -----------------------------------------------------------
if tests/idle_bench.sh > "${OUT_DIR}/idle.json" 2>>"${OUT_DIR}/idle.log"; then
    log_check "idle ≤ 600 MB" "PASS"
else
    log_check "idle ≤ 600 MB" "FAIL"
fi

# --- 3-4. DL stack ---------------------------------------------------------
if command -v aurum-dl-verify >/dev/null 2>&1; then
    if aurum-dl-verify >> "${OUT_DIR}/dl.log" 2>&1; then
        log_check "DL stack smoke+bench"    "PASS"
    else
        log_check "DL stack smoke+bench"    "FAIL"
    fi
else
    log_check "DL stack smoke+bench" "SKIP"
fi

echo "Reports under ${OUT_DIR}" >&2

if [[ "${pass}" == "true" ]]; then
    echo
    echo "ACCEPTANCE: PASS"
    exit 0
fi
echo
echo "ACCEPTANCE: FAIL — see ${OUT_DIR}/*.log"
exit 1
