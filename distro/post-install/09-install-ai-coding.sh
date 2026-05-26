#!/usr/bin/env bash
# ==============================================================================
# AurumOS — AI-augmented coding tools (Wave 8 / Agent D)
#
# Installs the three coding assistants AurumOS ships pre-wired to the local
# Ollama runtime that 03-install-llm-runtimes.sh has already set up:
#
#   1. Continue.dev — VSCode extension; chat + autocomplete inside the editor.
#                     Backed by local Ollama by default; can swap to Claude /
#                     GPT-4o by pasting an API key in the model dropdown.
#   2. Aider        — terminal pair-programmer; whole-file edits, git auto-
#                     commits (we DISABLE auto-commits in the shipped config,
#                     users opt back in per-repo with `--auto-commits`).
#   3. Claude Code  — Anthropic's official CLI; needs ANTHROPIC_API_KEY in env.
#
# The pre-built Continue config (distro/assets/continue-config.json) is
# templated with ${AURUM_OLLAMA_DEFAULT}; this script sources
# /etc/aurum/profile.conf and runs envsubst so the rendered config picks the
# tier-appropriate model (1.5b for `lite`, 7b for `standard`, 14b for `pro`,
# 32b for `workstation`). The rendered file lands in:
#   - /etc/skel/.continue/config.json   (new users created post-install)
#   - $SUDO_USER's ~/.continue/config.json (the install user, if any)
#
# Templates for ~/Templates/CLAUDE.md, ~/Templates/.cursorrules and
# ~/Templates/.aider.conf.yml are installed to /etc/skel/Templates/ so the
# user's Finder "New from template" picks them up.
#
# Docker preview caveats (this script MUST exit 0 in the preview):
#   * `code` (VSCode CLI) may not be present — log warn and skip the
#     extension install instead of failing the script.
#   * `npm` may not be present — install nodejs+npm via apt; if apt itself
#     fails (offline preview), warn and skip Claude Code.
#   * `ollama pull nomic-embed-text` is best-effort: a Continue.dev config
#     pointing at a missing embedding model still works for chat/autocomplete,
#     just without RAG over the workspace.
# ==============================================================================

set -uo pipefail
# NOTE: `set -e` is intentionally off — every install step has its own
# best-effort handling, and a single missing-binary failure (likely in the
# Docker preview) must not abort the rest of the script.

# --- locations ----------------------------------------------------------------
PROFILE_CONF="${AURUM_PROFILE_CONF:-/etc/aurum/profile.conf}"
ASSETS_DIR="${ASSETS_DIR:-}"
PIP_REQS="${PIP_REQS:-}"

# Resolve assets dir + requirements path against the common ISO-builder
# staging spots so this script works from either the chroot or a checkout.
resolve_paths() {
    local self_dir
    self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local repo_root
    repo_root="$(cd "${self_dir}/../.." 2>/dev/null && pwd || echo "")"

    if [[ -z "${ASSETS_DIR}" ]]; then
        for candidate in \
            "/tmp/aurum/distro/assets" \
            "/tmp/aurum-assets" \
            "${repo_root}/distro/assets" \
            "${self_dir}/../assets"; do
            if [[ -f "${candidate}/continue-config.json" ]]; then
                ASSETS_DIR="${candidate}"; break
            fi
        done
    fi
    if [[ -z "${PIP_REQS}" ]]; then
        for candidate in \
            "/tmp/aurum/distro/packages/pip-requirements-coding.txt" \
            "/tmp/packages/pip-requirements-coding.txt" \
            "${repo_root}/distro/packages/pip-requirements-coding.txt" \
            "${self_dir}/../packages/pip-requirements-coding.txt"; do
            if [[ -f "${candidate}" ]]; then PIP_REQS="${candidate}"; break; fi
        done
    fi
}

log()  { echo -e "\e[34m[ai-coding]\e[0m $*"; }
warn() { echo -e "\e[33m[ai-coding]\e[0m $*" >&2; }
skip() { echo -e "\e[36m[ai-coding]\e[0m SKIP — $*"; }

# --- profile sourcing --------------------------------------------------------
# Continue.dev's local-model field is templated; we need AURUM_OLLAMA_DEFAULT
# in env for envsubst. If profile.conf doesn't exist yet (very early in the
# chroot, before 00-detect-profile.sh ran), fall back to the `standard` 7b
# model — the worst case is the user re-runs aurum-configure-continue after
# first boot.
source_profile() {
    if [[ -f "${PROFILE_CONF}" ]]; then
        # `set -a` and `set +a` are split onto separate lines so shellcheck
        # honours the `source=/dev/null` directive (it ignores it when source
        # is preceded by another command on the same line).
        set -a
        # shellcheck source=/dev/null
        source "${PROFILE_CONF}"
        set +a
        log "sourced profile: ${AURUM_PROFILE:-?} (default model = ${AURUM_OLLAMA_DEFAULT:-?})"
    else
        warn "profile.conf not found at ${PROFILE_CONF}; using standard-tier fallback"
        export AURUM_OLLAMA_DEFAULT="qwen2.5-coder:7b"
        export AURUM_PROFILE="standard"
    fi
    # Final safety net — envsubst on an empty var would silently produce
    # `"model": ""` which Continue.dev rejects at load time.
    if [[ -z "${AURUM_OLLAMA_DEFAULT:-}" ]]; then
        warn "AURUM_OLLAMA_DEFAULT empty after sourcing; pinning to qwen2.5-coder:7b"
        export AURUM_OLLAMA_DEFAULT="qwen2.5-coder:7b"
    fi
}

# --- 1. Continue.dev VSCode extension ----------------------------------------
install_continue_extension() {
    if ! command -v code >/dev/null 2>&1; then
        warn "code (VSCode CLI) not found on PATH — Wave 7 should have installed it"
        warn "skipping Continue.dev extension install; user can run later:"
        warn "  code --install-extension Continue.continue --force"
        return 0
    fi
    log "installing Continue.dev VSCode extension..."
    # --force makes this idempotent across re-runs.
    # Run as the install user if we know it; root-installed extensions go to
    # /root/.vscode/extensions and never become visible to a normal user.
    local runner="code"
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        # Try as the invoking user (so the extension lands in ~/.vscode/extensions).
        if sudo -u "${SUDO_USER}" -H code --install-extension Continue.continue --force >/dev/null 2>&1; then
            log "✓ Continue.dev installed for user ${SUDO_USER}"
            return 0
        fi
        warn "user-context install failed; falling back to system-wide"
    fi
    if ${runner} --install-extension Continue.continue --force --no-sandbox >/dev/null 2>&1; then
        log "✓ Continue.dev installed (system context)"
    else
        warn "Continue.dev install failed (likely no display in this Docker preview)"
        warn "user can install manually from the Extensions sidebar at first launch"
    fi
}

# --- 2. Render Continue.dev config from template -----------------------------
render_continue_config() {
    local tpl="${ASSETS_DIR}/continue-config.json"
    if [[ ! -f "${tpl}" ]]; then
        warn "continue-config.json template not found at ${tpl}; skipping render"
        return 0
    fi
    local rendered
    if ! command -v envsubst >/dev/null 2>&1; then
        warn "envsubst not available (gettext-base); doing literal copy with sed fallback"
        # sed-only fallback: substitute the single var we care about.
        rendered=$(sed "s|\${AURUM_OLLAMA_DEFAULT}|${AURUM_OLLAMA_DEFAULT}|g" "${tpl}")
    else
        # Limit envsubst to JUST our vars — a bare envsubst would chew on every
        # $-token in the file, including arbitrary user content if the template
        # ever gains free-form fields.
        rendered=$(envsubst '${AURUM_OLLAMA_DEFAULT}' < "${tpl}")
    fi

    # /etc/skel — new users created after install inherit this.
    # Guard for non-root preview runs where /etc/skel isn't writable; we still
    # want to drop the per-user copy below so the install user gets working
    # tooling even when running this script unprivileged.
    if install -d -m 0755 /etc/skel/.continue 2>/dev/null; then
        printf '%s\n' "${rendered}" > /etc/skel/.continue/config.json
        chmod 0644 /etc/skel/.continue/config.json
        log "✓ wrote /etc/skel/.continue/config.json (model=${AURUM_OLLAMA_DEFAULT})"
    else
        warn "cannot write /etc/skel/.continue (not root?); skipping system-skel copy"
    fi

    # The install user (if invoked via sudo) — give them the config immediately
    # so they don't have to re-run aurum-configure-continue manually.
    local user_home="" user_name="" user_group=""
    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        user_home=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
        user_name="${SUDO_USER}"
        user_group="${SUDO_USER}"
    elif [[ "${EUID:-$(id -u)}" -ne 0 && -n "${HOME:-}" ]]; then
        user_home="${HOME}"
        user_name="$(id -un)"
        user_group="$(id -gn)"
    fi
    if [[ -n "${user_home}" && -d "${user_home}" ]]; then
        install -d -o "${user_name}" -g "${user_group}" -m 0755 "${user_home}/.continue" 2>/dev/null \
            || mkdir -p "${user_home}/.continue"
        printf '%s\n' "${rendered}" > "${user_home}/.continue/config.json"
        chown "${user_name}:${user_group}" "${user_home}/.continue/config.json" 2>/dev/null || true
        chmod 0644 "${user_home}/.continue/config.json"
        log "✓ wrote ${user_home}/.continue/config.json for ${user_name}"
    fi
}

# --- 3. Aider CLI ------------------------------------------------------------
install_aider() {
    if command -v aider >/dev/null 2>&1; then
        log "aider already installed: $(aider --version 2>&1 | head -1 || true)"
        return 0
    fi
    if ! command -v pip3 >/dev/null 2>&1 && ! command -v pip >/dev/null 2>&1; then
        warn "pip not found; cannot install aider"
        return 0
    fi
    local pipbin
    pipbin=$(command -v pip3 || command -v pip)
    log "installing aider via ${pipbin}..."
    if [[ -n "${PIP_REQS}" && -f "${PIP_REQS}" ]]; then
        ${pipbin} install --break-system-packages -r "${PIP_REQS}" \
            || warn "aider install failed via requirements file"
    else
        ${pipbin} install --break-system-packages "aider-chat>=0.60" \
            || warn "aider install failed via direct pip"
    fi
    if command -v aider >/dev/null 2>&1; then
        log "✓ aider installed: $(aider --version 2>&1 | head -1)"
    else
        warn "aider not on PATH after install; pip may have placed it in ~/.local/bin"
    fi
}

# --- 4. Claude Code CLI ------------------------------------------------------
install_claude_code() {
    if command -v claude >/dev/null 2>&1; then
        log "claude (Claude Code CLI) already installed"
        return 0
    fi
    if ! command -v npm >/dev/null 2>&1; then
        log "npm not found; installing nodejs + npm via apt..."
        if command -v apt-get >/dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
                nodejs npm >/dev/null 2>&1 \
                || warn "apt install nodejs+npm failed (offline preview?)"
        else
            warn "no apt-get available; cannot bootstrap npm — skipping Claude Code"
            return 0
        fi
    fi
    if ! command -v npm >/dev/null 2>&1; then
        warn "npm still missing after apt — skipping Claude Code install"
        warn "user can install later: 'npm install -g @anthropic-ai/claude-code'"
        return 0
    fi
    log "installing @anthropic-ai/claude-code globally..."
    if npm install -g @anthropic-ai/claude-code >/dev/null 2>&1; then
        log "✓ Claude Code installed: $(claude --version 2>&1 | head -1 || echo present)"
    else
        warn "npm install -g @anthropic-ai/claude-code failed (likely no network in preview)"
        warn "user can install later: 'npm install -g @anthropic-ai/claude-code'"
    fi
}

# --- 5. Pre-pull nomic-embed-text (used by Continue.dev RAG) -----------------
prepull_embedding_model() {
    if ! command -v ollama >/dev/null 2>&1; then
        skip "ollama not installed; nomic-embed-text pull deferred to first use"
        return 0
    fi
    # Don't block forever in a container with no /etc/systemd/system; just try
    # the API endpoint once. If unreachable, defer.
    if ! curl -fsS --max-time 2 http://localhost:11434/api/tags >/dev/null 2>&1; then
        skip "ollama service not reachable on :11434; nomic-embed-text pull deferred"
        return 0
    fi
    log "pulling nomic-embed-text (Continue.dev embeddings; ~270MB)..."
    if ollama pull nomic-embed-text >/dev/null 2>&1; then
        log "✓ nomic-embed-text pulled"
    else
        warn "ollama pull nomic-embed-text failed; Continue.dev RAG will be disabled until pulled manually"
    fi
}

# --- 6. Install /etc/skel/Templates/ entries ---------------------------------
install_skel_templates() {
    # If we're not root we can't touch /etc/skel; in that case still seed the
    # current user's ~/Templates below so the preview run isn't a no-op.
    local skel_ok=0
    if install -d -m 0755 /etc/skel/Templates 2>/dev/null; then
        skel_ok=1
    else
        warn "cannot write /etc/skel/Templates (not root?); will still try per-user copy"
    fi
    if [[ ${skel_ok} -eq 1 ]]; then
    # CLAUDE.md starter
    cat > /etc/skel/Templates/CLAUDE.md <<'EOF'
# Project: <name>

## Overview
<one-paragraph description of what this codebase does and who uses it>

## Build
- `make build` or `npm run build` or `cargo build --release` or ...

## Test
- `make test` or `pytest -q` or `cargo test` or ...

## Code Style
- Indentation: 4 spaces
- Line length: 100 chars
- Imports: stdlib, third-party, local (blank line between groups)
- Naming: snake_case for python/rust, camelCase for JS/TS, PascalCase for types

## Important Context
- <decisions, gotchas, key files Claude should know about>
- <e.g. "auth lives in src/auth/; never touch session.py without reading session_test.py first">
- <e.g. "we target Python 3.13, no f-string nesting hacks please">
EOF
    chmod 0644 /etc/skel/Templates/CLAUDE.md

    # .cursorrules — generic AI-augmented dev rules
    cat > /etc/skel/Templates/.cursorrules <<'EOF'
# .cursorrules — AurumOS default AI pair-programming rules
# Drop this in the root of any project; Cursor / Continue.dev / Claude Code
# all read it as context. Tighten per-project as the codebase matures.

You are an AI pair-programmer for this codebase.

## General rules
- Prefer editing existing files over creating new ones.
- Match the existing code style (indent width, naming, import order) — read a
  neighbouring file first if unsure.
- Never add a dependency without flagging it explicitly in the response.
- Never invent APIs: if a function name isn't in the imports of nearby files,
  search before claiming it exists.
- When making non-trivial changes, run the test command afterwards.

## Comments
- Comments explain *why*, not *what*. The code already shows *what*.
- Don't add "this function does X" headers above self-explanatory functions.
- Don't add change-log style comments ("// changed by AI on 2025-..."): git
  history is the change log.

## Errors
- Don't swallow exceptions silently. Either handle (and log) or re-raise.
- Validate inputs at the public boundary, trust them internally.

## Tests
- New behaviour ships with a test.
- Modifying behaviour means updating the test that pins the old behaviour.
EOF
    chmod 0644 /etc/skel/Templates/.cursorrules

    # .aider.conf.yml — point Aider at the local Ollama model by default,
    # with a smaller "weak model" (1.5b) for fast cheap tasks like commit msgs.
    cat > /etc/skel/Templates/.aider.conf.yml <<EOF
# .aider.conf.yml — AurumOS default
# Aider auto-loads this when present in the project root or \$HOME.
# Override per-invocation with CLI flags (e.g. --model openrouter/claude-3.5-sonnet).

model: ollama/${AURUM_OLLAMA_DEFAULT}
weak-model: ollama/qwen2.5-coder:1.5b
edit-format: whole
auto-commits: false

# Hide noisy "model warnings" banner for known-local-only Ollama models.
show-model-warnings: false
EOF
    chmod 0644 /etc/skel/Templates/.aider.conf.yml

    log "✓ /etc/skel/Templates/ populated (CLAUDE.md, .cursorrules, .aider.conf.yml)"
    fi  # skel_ok

    # Also drop these for the install user so the first boot has them.
    # Source preferred: /etc/skel/Templates; if that wasn't writable above,
    # regenerate on the fly using the same heredocs (cheap enough).
    seed_user_templates() {
        local target_home="$1" target_user="$2" target_group="$3"
        install -d -o "${target_user}" -g "${target_group}" -m 0755 "${target_home}/Templates" 2>/dev/null \
            || mkdir -p "${target_home}/Templates"

        if [[ -f /etc/skel/Templates/CLAUDE.md ]]; then
            for f in CLAUDE.md .cursorrules .aider.conf.yml; do
                if [[ -f "/etc/skel/Templates/${f}" && ! -f "${target_home}/Templates/${f}" ]]; then
                    cp "/etc/skel/Templates/${f}" "${target_home}/Templates/${f}"
                    chown "${target_user}:${target_group}" "${target_home}/Templates/${f}" 2>/dev/null || true
                fi
            done
        else
            # Non-root preview fallback: inline minimal stubs so the directory
            # isn't empty and the user can see the structure.
            : > "${target_home}/Templates/CLAUDE.md"
            : > "${target_home}/Templates/.cursorrules"
            cat > "${target_home}/Templates/.aider.conf.yml" <<EOF2
model: ollama/${AURUM_OLLAMA_DEFAULT}
weak-model: ollama/qwen2.5-coder:1.5b
edit-format: whole
auto-commits: false
EOF2
        fi
        log "✓ seeded ${target_home}/Templates/ for ${target_user}"
    }

    if [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
        local home
        home=$(getent passwd "${SUDO_USER}" | cut -d: -f6)
        if [[ -n "${home}" && -d "${home}" ]]; then
            seed_user_templates "${home}" "${SUDO_USER}" "${SUDO_USER}"
        fi
    elif [[ "${EUID:-$(id -u)}" -ne 0 && -n "${HOME:-}" && -d "${HOME}" ]]; then
        # Non-root preview: seed the running user's home.
        seed_user_templates "${HOME}" "$(id -un)" "$(id -gn)"
    fi
}

main() {
    resolve_paths
    source_profile
    install_continue_extension
    render_continue_config
    install_aider
    install_claude_code
    prepull_embedding_model
    install_skel_templates
    log "AI-augmented coding tools install complete (profile=${AURUM_PROFILE:-?}, model=${AURUM_OLLAMA_DEFAULT})"
}

main "$@"
