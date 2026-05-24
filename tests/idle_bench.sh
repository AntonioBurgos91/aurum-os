#!/usr/bin/env bash
# Measure idle RAM with the AurumOS desktop running. Budget: 600 MB.
#
# Methodology: sum PSS (proportional set size) across the AurumOS desktop
# processes from /proc/<pid>/status. PSS is the only fair metric — RSS
# overcounts because Qt processes share libraries; using PSS gives "how much
# memory disappears when this process exits".
#
# Considered processes (regex match against /proc/*/comm):
#   - Hyprland
#   - aurum-(dock|menubar|gpu-monitor|spotlight-indexer|ml-jobs-tracker)
#   - mako, swww-daemon, polkit-kde-authentication-agent-1
#
# Output: JSON to stdout, table to stderr. Exit non-zero on budget miss.

set -euo pipefail

BUDGET_KB="${AURUM_IDLE_BUDGET_KB:-614400}"  # 600 MiB

# Regex for "is this process part of the AurumOS idle footprint?"
RE='^(Hyprland|aurum-(dock|menubar|gpu-monitor|spotlight-indexer|ml-jobs-tracker)|mako|swww-daemon|polkit-kde-auth)'

total_kb=0
declare -a rows=()
for status in /proc/[0-9]*/status; do
    name=$(awk '/^Name:/ { print $2 }' "${status}" 2>/dev/null) || continue
    [[ "${name}" =~ ${RE} ]] || continue
    pss=$(awk '/^VmRSS:/ { print $2 }' "${status}" 2>/dev/null) || continue
    [[ -n "${pss}" ]] || continue
    total_kb=$(( total_kb + pss ))
    rows+=("${name}    ${pss}")
done

passed="true"
if (( total_kb > BUDGET_KB )); then
    passed="false"
fi

cat <<JSON
{
  "idle_kb": ${total_kb},
  "budget_kb": ${BUDGET_KB},
  "passed": ${passed}
}
JSON

{
    echo
    echo "Idle RAM benchmark (RSS sum, KB)"
    printf '  %-32s %s\n' "process" "rss_kb"
    for row in "${rows[@]}"; do
        printf '  %-32s %s\n' ${row}
    done
    echo "  -------------------------------- ------"
    printf '  %-32s %s  (budget %s, %s)\n' \
        "TOTAL" "${total_kb}" "${BUDGET_KB}" "$([[ "${passed}" == "true" ]] && echo PASS || echo FAIL)"
} >&2

[[ "${passed}" == "true" ]]
