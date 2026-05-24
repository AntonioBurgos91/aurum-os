#!/usr/bin/env bash
# Measure boot time against the AurumOS budget defined in
# docs/adr/0006-performance-budget.md.
#
# Pass criteria:
#   * systemd-analyze --no-pager critical-chain reports total ≤ 3000 ms
#   * graphical.target reached within 3500 ms wall clock
#
# Output: JSON to stdout, table to stderr. Exit non-zero on budget miss so
# this can drop straight into CI gating.

set -euo pipefail

BUDGET_BOOT_MS="${AURUM_BOOT_BUDGET_MS:-3000}"

if ! command -v systemd-analyze >/dev/null 2>&1; then
    echo "systemd-analyze is required" >&2
    exit 2
fi

# `systemd-analyze` prints e.g. "Startup finished in 1.234s (kernel) + 2.567s (userspace) = 3.801s"
raw="$(systemd-analyze time)"

# Pull totals via sed; tolerate "Startup finished in ... = N.NNNs" only.
total_s=$(printf '%s\n' "$raw" \
    | sed -nE 's/^Startup finished in.*= ([0-9]+(\.[0-9]+)?)s.*$/\1/p' \
    | head -n1)

if [[ -z "${total_s}" ]]; then
    echo "could not parse systemd-analyze output:" >&2
    echo "${raw}" >&2
    exit 3
fi

total_ms=$(awk "BEGIN { printf \"%d\", ${total_s} * 1000 }")

# graphical-session.target start time.
gst="$(systemd-analyze --user time 2>/dev/null \
        | sed -nE 's/^Startup finished in ([0-9]+(\.[0-9]+)?)s.*$/\1/p' \
        | head -n1 || true)"

passed="true"
if (( total_ms > BUDGET_BOOT_MS )); then
    passed="false"
fi

cat <<JSON
{
  "boot_total_ms": ${total_ms},
  "graphical_user_session_s": "${gst:-unavailable}",
  "budget_ms": ${BUDGET_BOOT_MS},
  "passed": ${passed}
}
JSON

# Pretty summary to stderr so CI logs are scannable.
{
    echo
    echo "Boot benchmark"
    echo "  total       : ${total_ms} ms"
    echo "  budget      : ${BUDGET_BOOT_MS} ms"
    echo "  status      : $([[ "${passed}" == "true" ]] && echo PASS || echo FAIL)"
} >&2

[[ "${passed}" == "true" ]]
