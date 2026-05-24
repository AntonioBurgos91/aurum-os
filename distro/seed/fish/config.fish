# ==============================================================================
# AurumOS Shell Configuration (Fish 4.0 Adaptation)
# ==============================================================================

# Disable welcome message
set -g fish_greeting ""

# Environment path expansions
fish_add_path ~/.local/bin
fish_add_path /usr/local/bin
fish_add_path /opt/aurum-dl-venv/bin

# --- Runtimes and Package Managers ---
# Integrate mise environment setup
if test -f ~/.local/bin/mise
    ~/.local/bin/mise activate fish | source
end

# --- Framework & Tooling Aliases ---
alias l="ls -lh"
alias la="ls -A"
alias ll="ls -lAh"

# Python / UV integrations
alias pip="uv pip"
alias venv="uv venv"
alias py="python3"

# Git CLI enhancements
alias lg="lazygit"
alias g="git"

# DL Quick Actions
alias killpython="killall -9 python python3 || echo 'No active python workloads.'"
alias gpurestart="sudo nvidia-smi --gpu-reset || echo 'GPU reset failed or not supported.'"
alias gpus="nvidia-smi"

# --- Starship Prompt Initialization ---
if command -v starship &>/dev/null
    starship init fish | source
end
