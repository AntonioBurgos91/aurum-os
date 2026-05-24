# Post-install scripts

Numbered scripts the ISO chroot runs in order. Each is idempotent and can
also be re-run on a live install for recovery.

| Script                       | What it does                                              |
|------------------------------|-----------------------------------------------------------|
| `01-add-nvidia-repo.sh`      | Adds the NVIDIA developer repo (CUDA, cuDNN, TRT, NCCL)   |
| `02-install-dl-stack.sh`     | Creates `/opt/aurum-dl-venv` and installs `pip-requirements.txt` via `uv` |
| `03-install-llm-runtimes.sh` | Installs Ollama; drops the `lms` wrapper for LM Studio    |
| `04-perf-tune.sh`            | Masks non-essential services, applies GRUB cmdline (ADR-0006) |
| `05-install-quantization.sh` | Installs bitsandbytes, AutoGPTQ, AutoAWQ, optimum, accelerate (pinned via `pip-requirements-quant.txt`) |
| `06-install-finetuning.sh`   | Installs peft/trl/Unsloth/TorchTune/Axolotl/DeepSpeed; subset chosen from `/etc/aurum/profile.conf` (lite -> peft only; standard -> +Unsloth; pro/workstation -> +Axolotl+DeepSpeed) |
| `09-install-ai-coding.sh`    | Installs Continue.dev (VSCode ext), Aider, Claude Code CLI. Renders Continue config from `/etc/aurum/profile.conf` so the local-Ollama model matches the user's tier. Drops `~/Templates/{CLAUDE.md,.cursorrules,.aider.conf.yml}` into `/etc/skel`. |

Order matters: 01 must run before 02 (CUDA must be present so wheels link).
02 must run before 05 and 06 (they install into `/opt/aurum-dl-venv`).
03 must run before 09 (Continue.dev / Aider point at the Ollama runtime 03 installs).
03 and 04 can run in either order. 05 and 06 can run in either order.
