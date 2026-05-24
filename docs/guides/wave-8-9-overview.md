# Waves 8 & 9 — AI/ML stack overview

Waves 8 and 9 transform AurumOS from a Hyprland desktop into a *batteries-
included AI workstation*. Every fresh install — from a CPU-only Docker
preview to a dual-RTX-4090 build — boots with a coherent, locally-served,
2026-era model stack tuned to its hardware.

This guide is the **map**. Each row links to the deep-dive guide written by
the agent who built that piece.

## What gets installed

```
                   ┌──────────────────────────────────────┐
                   │   /etc/aurum/profile.conf            │
                   │   ──────────────────────────────     │
                   │   AURUM_PROFILE=standard             │
                   │   AURUM_VRAM_MB=8192                 │
                   │   AURUM_RAM_GB=32                    │
                   │   AURUM_OLLAMA_DEFAULT=qwen2.5:7b    │
                   │   …                                  │
                   └────────────────────┬─────────────────┘
                                        │
            ┌───────────────────────────┼────────────────────────────┐
            ▼                           ▼                            ▼
   ┌───────────────────┐    ┌──────────────────────┐     ┌──────────────────────┐
   │  Inference        │    │  Workflows           │     │  Tooling             │
   │  ─────────        │    │  ─────────           │     │  ───────             │
   │  Ollama           │    │  DSPy                │     │  Continue.dev        │
   │  vLLM             │    │  Instructor          │     │  Aider               │
   │  LiteLLM proxy    │    │  Outlines            │     │  Claude Code tmpl    │
   │  ComfyUI          │    │  Pydantic-AI         │     │  ComfyUI workflows   │
   │  llama.cpp        │    │  MCP servers         │     │  Marimo notebooks    │
   └───────────────────┘    └──────────────────────┘     └──────────────────────┘
                                        │
                                        ▼
                          ┌──────────────────────────┐
                          │  Observability + Eval    │
                          │  ────────────────────    │
                          │  Langfuse (self-host)    │
                          │  Phoenix (in-process)    │
                          │  TruLens / Ragas / DE    │
                          └──────────────────────────┘
```

## Per-domain guides

| Domain                    | Owner     | Guide                                                |
|---------------------------|-----------|------------------------------------------------------|
| Hardware profile system   | Agent G   | [hardware-profiles.md](./hardware-profiles.md)       |
| **SOTA-2026 install tiers** | Agent J | [sota-2026-stack.md](./sota-2026-stack.md)           |
| **Upgrade path (lite→pro)** | Agent J | [upgrade-path.md](./upgrade-path.md)                 |
| **LLM workflows cookbook**  | Agent J | [llm-workflows-cookbook.md](./llm-workflows-cookbook.md) |
| Quantization & fine-tune  | Agent A   | `recipes/quantization/`, `recipes/unsloth/`          |
| LLM serving (vLLM, sglang)| Agent B   | `distro/post-install/03-install-llm-runtimes.sh`     |
| Workflows (DSPy, Inst...) | Agent C   | `recipes/dspy/`, `recipes/instructor/`, `recipes/mcp/` |
| AI coding (Continue, Aider) | Agent D | `distro/post-install/09-install-ai-coding.sh`        |
| Observability             | Agent E   | `distro/post-install/10-install-observability.sh`    |
| CV + multimodal           | Agent F   | `distro/post-install/11-install-cv-multimodal.sh`    |
| Model Pack GUI            | Agent H   | `desktop/apps/aurum-settings/qml/ModelPackPanel.qml` |
| Model Pack CLI            | Agent I   | `tools/aurum-model-pack`                             |

## End-to-end user journey

1. **Boot** — `aurum-detect-profile.service` runs `00-detect-profile.sh`
   and writes `/etc/aurum/profile.conf`. Settings → Hardware shows the tier.
2. **First login** — the dock pins `Model Packs`, `LM Studio`, `JupyterLab`,
   `Marimo`, and `Ollama`. The `Continue.dev` VSCode extension is
   pre-configured to talk to the local Ollama at `:11434`.
3. **Install model packs** — the user opens *Model Packs* in Settings (or
   runs `aurum-model-pack install coding`) and one-click downloads
   `qwen2.5-coder:7b` + `nomic-embed-text`. The CLI streams progress;
   the GUI shows a per-pack progress card.
4. **Code** — `aider` works from any terminal; Continue.dev works from
   VSCode; both route to local Ollama.
5. **Build a workflow** — the user opens `recipes/dspy/01_simple_qa.py`
   in JupyterLab, edits the signature, and runs it. Traces stream to the
   in-process Phoenix UI on `:6006`.
6. **Train or fine-tune** — `recipes/unsloth/qlora_7b_standard.py` does
   a QLoRA on the user's dataset; the *ML Jobs Tracker* daemon shows the
   live tensorboard.
7. **Generate images** — ComfyUI lives at `:8188`; the imagegen pack
   drops SDXL Turbo into its checkpoint dir.
8. **Upgrade hardware** — see [upgrade-path.md](./upgrade-path.md).

## Reading order for new contributors

1. [hardware-profiles.md](./hardware-profiles.md) — start here. Every
   later script keys off the profile detection.
2. [sota-2026-stack.md](./sota-2026-stack.md) — the big "what's installed
   where" matrix. Tape this to your monitor.
3. [llm-workflows-cookbook.md](./llm-workflows-cookbook.md) — pick one of
   DSPy / Instructor / Outlines / Pydantic-AI for your task.
4. [upgrade-path.md](./upgrade-path.md) — the 60-second recipe for
   migrating from CPU to GPU.

## Verifying your install

```bash
# Smoke-test the whole Wave 8/9 surface (skips items that don't apply to
# your profile, e.g. vLLM on lite):
bash tests/run-wave-8-9-smoke.sh

# Or the underlying per-domain tests:
bash tests/test_hardware_profile.sh
bash tests/test_model_packs.sh
bash tests/test_llm_workflows.sh
bash tests/test_ai_coding.sh
bash tests/test_observability.sh
bash tests/test_cv_multimodal.sh
```

Output is colour-coded `PASS / WARN / SKIP / FAIL`. WARN and SKIP are
expected on lite (no GPU); FAIL is a real regression.
