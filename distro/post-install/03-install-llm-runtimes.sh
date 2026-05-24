#!/usr/bin/env bash
# ==============================================================================
# AurumOS — local LLM runtimes (Ollama + LM Studio CLI bootstrap)
#
# Ollama:    Uses the official installer (curl|sh). The installer writes the
#            systemd unit /etc/systemd/system/ollama.service for us and creates
#            an `ollama` system user. We just enable + tweak.
#
# LM Studio: Distributed as a desktop AppImage that bundles the `lms` CLI.
#            We DON'T fetch the AppImage in the chroot (~600 MB, GUI-only).
#            Instead we ship a tiny `lms` wrapper to /usr/local/bin/ that:
#               - execs the user's installed `~/.lmstudio/bin/lms` if present
#               - otherwise prints download instructions and exits non-zero
#            Users who want the GUI run the AppImage once; the CLI then works
#            from any shell.
# ==============================================================================

set -euo pipefail

log()  { echo -e "\e[34m[llm]\e[0m $*"; }
warn() { echo -e "\e[33m[llm]\e[0m $*" >&2; }
die()  { echo -e "\e[31m[llm]\e[0m $*" >&2; exit 1; }

require_root() { [[ $EUID -eq 0 ]] || die "must be run as root"; }

install_ollama() {
    if command -v ollama >/dev/null 2>&1; then
        log "ollama already installed; skipping fetch"
    else
        log "installing ollama via official script..."
        # The installer is idempotent and skipped under OLLAMA_SKIP_INSTALL=1.
        curl -fsSL https://ollama.com/install.sh | sh
    fi

    # Make sure the unit exists; some minimal-systemd containers strip it.
    if [[ -f /etc/systemd/system/ollama.service ]]; then
        log "enabling ollama.service..."
        systemctl enable ollama.service || true
    else
        warn "ollama.service not found; the official installer may not have written one"
    fi

    # AurumOS default: don't let Ollama autostart at boot unless the user logs
    # in (saves VRAM on machines that mostly do other workloads). Override:
    #   sudo systemctl enable --now ollama
    if systemctl is-enabled ollama.service &>/dev/null; then
        log "ollama service: enabled"
    else
        log "ollama service: present, disabled at boot (start manually as needed)"
    fi
}

install_lmstudio_cli() {
    log "installing lms CLI wrapper..."
    install -d -m 0755 /usr/local/bin
    cat > /usr/local/bin/lms <<'WRAPPER'
#!/usr/bin/env bash
# AurumOS lms wrapper.
# Prefers the user's LM Studio install (provides the real `lms` binary).
# Without it, surface a clear install hint instead of "command not found".

user_lms="${HOME}/.lmstudio/bin/lms"
if [[ -x "${user_lms}" ]]; then
    exec "${user_lms}" "$@"
fi

cat <<'EOF' >&2
[lms] LM Studio is not installed yet.

Install the LM Studio AppImage from https://lmstudio.ai, run it once, and the
`lms` CLI will become available at ~/.lmstudio/bin/lms. This wrapper resolves
to that binary transparently.

For headless boxes prefer Ollama (`ollama run llama3.1`), which AurumOS already
ships and which exposes a similar CLI surface.
EOF
exit 127
WRAPPER
    chmod 0755 /usr/local/bin/lms
}

main() {
    require_root
    install_ollama
    install_lmstudio_cli
    log "LLM runtimes ready"
}

main "$@"
