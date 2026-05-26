#!/usr/bin/env bash
# ==============================================================================
# aurum-configure-continue — regenerate ~/.continue/config.json from the
# current AurumOS profile.
#
# When to run:
#   * After installing a different GPU and re-detecting the profile
#     (`sudo aurum-detect-profile` → tier may change → default model shifts).
#   * After manually editing /etc/aurum/profile.conf.
#   * If you blew away ~/.continue/ and want the AurumOS defaults back.
#
# What it does:
#   1. Sources /etc/aurum/profile.conf to pick up AURUM_OLLAMA_DEFAULT.
#   2. Finds the shipped template at /etc/skel/.continue/config.json OR
#      /usr/share/aurum-os/continue-config.json OR the in-repo path.
#   3. Renders ${AURUM_OLLAMA_DEFAULT} into a fresh ~/.continue/config.json.
#   4. Backs up any existing config to config.json.bak.<timestamp> first —
#      because we don't want to silently clobber a user's hand-tuned config.
#
# This runs as the invoking user (NOT root); the config lives in their $HOME.
# ==============================================================================

set -uo pipefail

PROFILE_CONF="${AURUM_PROFILE_CONF:-/etc/aurum/profile.conf}"
TARGET="${HOME}/.continue/config.json"

log()  { echo -e "\e[34m[continue]\e[0m $*"; }
warn() { echo -e "\e[33m[continue]\e[0m $*" >&2; }
die()  { echo -e "\e[31m[continue]\e[0m $*" >&2; exit 1; }

if [[ ! -f "${PROFILE_CONF}" ]]; then
    warn "${PROFILE_CONF} not found — running with standard-tier fallback (qwen2.5-coder:7b)"
    export AURUM_OLLAMA_DEFAULT="qwen2.5-coder:7b"
    export AURUM_PROFILE="standard"
else
    # shellcheck source=/dev/null
    set -a; source "${PROFILE_CONF}"; set +a
fi
: "${AURUM_OLLAMA_DEFAULT:=qwen2.5-coder:7b}"

# Find the template. Prefer the rendered /etc/skel copy (already has the
# correct embedding/autocomplete defaults), fall back to the raw asset.
TEMPLATE=""
for candidate in \
    "/etc/skel/.continue/config.json" \
    "/usr/share/aurum-os/continue-config.json" \
    "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/../distro/assets/continue-config.json"; do
    if [[ -f "${candidate}" ]]; then TEMPLATE="${candidate}"; break; fi
done
[[ -n "${TEMPLATE}" ]] || die "no Continue.dev template found (looked in /etc/skel, /usr/share/aurum-os, repo)"

log "template: ${TEMPLATE}"
log "profile : ${AURUM_PROFILE:-?} → model = ${AURUM_OLLAMA_DEFAULT}"

# --- Render -----------------------------------------------------------------
# The template's $-tokens may already have been substituted (if we picked the
# /etc/skel copy); a second envsubst pass on a clean string is a no-op, so
# this is safe either way. We use sed if envsubst is missing.
if command -v envsubst >/dev/null 2>&1; then
    RENDERED=$(envsubst '${AURUM_OLLAMA_DEFAULT}' < "${TEMPLATE}")
else
    RENDERED=$(sed "s|\${AURUM_OLLAMA_DEFAULT}|${AURUM_OLLAMA_DEFAULT}|g" "${TEMPLATE}")
fi

# Replace the model line whether or not the template still has a literal
# ${AURUM_OLLAMA_DEFAULT} token — this handles the /etc/skel pre-rendered
# case where we need to switch from (say) 7b to 14b after a GPU upgrade.
# We target the first model object only; jq would be cleaner but we can't
# guarantee it on the install host.
RENDERED=$(printf '%s' "${RENDERED}" | awk -v m="${AURUM_OLLAMA_DEFAULT}" '
    BEGIN { swapped=0 }
    /"title": "Local Ollama \(Auto\)"/ { in_local=1 }
    in_local && /"model":/ && swapped==0 {
        sub(/"model": *"[^"]*"/, "\"model\": \"" m "\"")
        swapped=1; in_local=0
    }
    { print }
')

# --- Back up existing config + write new ------------------------------------
mkdir -p "$(dirname "${TARGET}")"
if [[ -f "${TARGET}" ]]; then
    bak="${TARGET}.bak.$(date +%Y%m%d-%H%M%S)"
    cp -p "${TARGET}" "${bak}"
    log "backed up existing config → ${bak}"
fi
printf '%s\n' "${RENDERED}" > "${TARGET}"
chmod 0644 "${TARGET}"
log "✓ wrote ${TARGET}"

# Sanity-print the resolved model name so the user can confirm.
if command -v grep >/dev/null 2>&1; then
    log "resolved local model: $(grep -m1 '"model":' "${TARGET}" | sed 's/.*"model": *"\([^"]*\)".*/\1/')"
fi
