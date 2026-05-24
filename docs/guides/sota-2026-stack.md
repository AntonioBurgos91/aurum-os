# The SOTA-2026 stack — what's installed at each profile tier

> **Tape this to your monitor.** Every Wave 8/9 launcher reads
> `/etc/aurum/profile.conf` (set by `aurum-detect-profile`) and selects
> its defaults from this table. If a row disagrees with your machine,
> [override the tier](./hardware-profiles.md#overriding-the-tier) or file
> an issue.

## Tier reminder

| Tier          | Trigger                          | "Who is this?"                |
|---------------|----------------------------------|-------------------------------|
| `lite`        | No CUDA, or VRAM < 6 GB          | Laptop CPU, Docker preview    |
| `standard`    | VRAM 6–12 GB and RAM 16–32 GB    | **The 80% target.** RTX 5060. |
| `pro`         | VRAM 12–16 GB and RAM 32–64 GB   | RTX 4070 / 4080               |
| `workstation` | VRAM ≥ 24 GB or RAM ≥ 64 GB      | RTX 4090, A6000, multi-GPU    |

## The big matrix

Legend: ✅ installed + working · ⚠️ installed, runs on CPU (slow) ·
❌ not installed · ⭐ recommended default for the tier.

### LLM inference

| Tool / Model            | Lite (CPU)              | Standard (5060) ⭐                  | Pro (4070+)                         | Workstation (4090+)              |
|-------------------------|-------------------------|-------------------------------------|-------------------------------------|----------------------------------|
| Ollama (default chat)   | `qwen2.5:1.5b` ⭐       | `qwen2.5:7b` ⭐                     | `qwen2.5:14b` ⭐                    | `qwen2.5:32b` ⭐                 |
| Ollama (default coder)  | `qwen2.5-coder:1.5b`    | `qwen2.5-coder:7b`                  | `qwen2.5-coder:14b`                 | `qwen2.5-coder:32b`              |
| Ollama (extras)         | `gemma2:2b`             | `llama3.2:3b`                       | `llama3.2:8b`, `mistral-nemo`       | `llama3.3:70b-q4`                |
| vLLM                    | ❌                      | ✅ AWQ, 8 k ctx                     | ✅ AWQ + spec-decode, 16 k ctx      | ✅ FP16, 32 k ctx, TP=1          |
| llama.cpp / llamafile   | ✅ (CPU)                | ✅                                  | ✅                                  | ✅                               |
| LiteLLM proxy (`:4000`) | ✅                      | ✅                                  | ✅                                  | ✅                               |
| sglang                  | ❌                      | ⚠️ (untested)                       | ✅                                  | ✅                               |
| Open WebUI              | ✅                      | ✅                                  | ✅                                  | ✅                               |
| LM Studio               | ✅                      | ✅                                  | ✅                                  | ✅                               |

### LLM workflow libraries (all profiles — pure Python orchestrators)

| Library                 | Lite | Standard | Pro  | Workstation | Purpose                                         |
|-------------------------|------|----------|------|-------------|-------------------------------------------------|
| `dspy-ai` (≥ 2.5)       | ✅   | ✅       | ✅   | ✅          | Declarative prompt programs, auto-optimised     |
| `instructor` (≥ 1.6)    | ✅   | ✅       | ✅   | ✅          | Pydantic-typed structured output via LiteLLM    |
| `outlines` (≥ 0.1)      | ✅   | ✅       | ✅   | ✅          | Regex / JSON-schema / CFG constrained gen       |
| `guidance` (≥ 0.2)      | ✅   | ✅       | ✅   | ✅          | Token-level constrained generation              |
| `pydantic-ai` (≥ 0.0.14)| ✅   | ✅       | ✅   | ✅          | Pydantic-native agent framework                 |
| `mcp` (≥ 0.9)           | ✅   | ✅       | ✅   | ✅          | Model Context Protocol SDK (Anthropic)          |
| `litellm` (≥ 1.50)      | ✅   | ✅       | ✅   | ✅          | One API for 100+ providers + local              |

### Fine-tuning & quantization

| Tool                    | Lite      | Standard          | Pro                       | Workstation              |
|-------------------------|-----------|-------------------|---------------------------|--------------------------|
| `peft`                  | ✅        | ✅                | ✅                        | ✅                       |
| `trl`                   | ✅        | ✅                | ✅                        | ✅                       |
| `unsloth`               | ❌        | ✅ 7B QLoRA       | ✅ 13B QLoRA              | ✅ 70B QLoRA             |
| `axolotl`               | ❌        | ❌                | ✅ ZeRO-2                 | ✅ ZeRO-3                |
| `torchtune`             | ⚠️ CPU    | ✅                | ✅                        | ✅                       |
| `deepspeed`             | ❌        | ❌                | ✅ ZeRO-2                 | ✅ ZeRO-3                |
| `bitsandbytes` (NF4/int8)| ⚠️ CPU   | ✅                | ✅                        | ✅                       |
| `auto-gptq`             | ⚠️ CPU    | ✅                | ✅                        | ✅                       |
| `autoawq`               | ⚠️ CPU    | ✅                | ✅                        | ✅                       |
| Default QLoRA recipe    | ❌        | `qlora-4bit-7b`   | `qlora-4bit-13b`          | `qlora-4bit-70b`         |

### AI-augmented coding

| Tool                    | Lite | Standard | Pro  | Workstation | Notes                                          |
|-------------------------|------|----------|------|-------------|------------------------------------------------|
| `aider-chat`            | ✅   | ✅       | ✅   | ✅          | Routes to local Ollama by default              |
| Continue.dev (VSCode)   | ✅   | ✅       | ✅   | ✅          | Pre-configured at `~/.continue/config.json`    |
| Claude Code template    | ✅   | ✅       | ✅   | ✅          | `/etc/skel/Templates/CLAUDE.md`                |
| Cody / Tabby / TabbyML  | optional | optional | optional | optional | Documented; not auto-installed                 |
| Default code model      | `qwen2.5-coder:1.5b` | `qwen2.5-coder:7b` | `qwen2.5-coder:14b` | `qwen2.5-coder:32b` | Pinned in Continue + Aider |

### Computer vision & multimodal

| Library / Model         | Lite              | Standard           | Pro                 | Workstation          |
|-------------------------|-------------------|--------------------|---------------------|----------------------|
| `ultralytics` (YOLOv11) | ✅ `yolov11n`     | ✅ `yolov11s` ⭐   | ✅ `yolov11m`       | ✅ `yolov11x`        |
| `sam-2` (Segment Anything 2) | ✅ `sam2-tiny` | ✅ `sam2-base` ⭐ | ✅ `sam2-large`     | ✅ `sam2-large`      |
| `dinov2`                | ✅                | ✅                 | ✅                  | ✅                   |
| `open-clip-torch`       | ✅                | ✅                 | ✅                  | ✅                   |
| `controlnet-aux`        | ✅                | ✅                 | ✅                  | ✅                   |
| `diffusers`             | ✅ (CPU SDXL ≈ 25 s) | ✅ SDXL Turbo ⭐ | ✅ SDXL fp16        | ✅ SD3 / Flux        |
| ComfyUI                 | ❌ (no GPU)       | ✅ `--medvram`     | ✅ `--highvram`     | ✅ `--highvram --bf16-vae` |
| LLaVA / multimodal LLM  | `llava-phi-int4`  | `llava-7b-int4`    | `llava-13b-int4`    | `llava-34b-int4`     |
| Whisper                 | `tiny`            | `small`            | `medium`            | `large-v3`           |

### Observability & evaluation

| Tool                    | Lite           | Standard       | Pro            | Workstation    |
|-------------------------|----------------|----------------|----------------|----------------|
| Phoenix (in-process)    | ✅ `:6006`     | ✅             | ✅             | ✅             |
| Langfuse (self-host)    | ❌ (needs Docker + 4 GB RAM) | ✅ `:3000` | ✅       | ✅             |
| `trulens`               | ✅             | ✅             | ✅             | ✅             |
| `ragas`                 | ✅             | ✅             | ✅             | ✅             |
| `deepeval`              | ✅             | ✅             | ✅             | ✅             |
| OpenInference instrumentors | ✅         | ✅             | ✅             | ✅             |

### Model packs (curated weights bundles)

All six packs are *declared* on every profile; whether the user can
actually run them depends on the pack's `min_profile`:

| Pack          | `min_profile` | Lite | Standard | Pro | Workstation | What it ships                                        |
|---------------|---------------|------|----------|-----|-------------|------------------------------------------------------|
| `chat`        | lite          | ✅   | ✅       | ✅  | ✅          | `llama3.2:3b`, `qwen2.5:7b`                          |
| `coding`      | standard      | —    | ✅       | ✅  | ✅          | `qwen2.5-coder:7b`, `qwen2.5-coder:14b` (pro+), embed |
| `vision`      | lite          | ✅   | ✅       | ✅  | ✅          | YOLO11s, SAM 2, DINOv2, OpenCLIP                     |
| `imagegen`    | standard      | —    | ✅       | ✅  | ✅          | SDXL Turbo, ControlNet Canny, sd-vae-ft-ema          |
| `speech`      | lite          | ✅   | ✅       | ✅  | ✅          | Whisper (`tiny`/`small`/`medium`/`large-v3`)         |
| `workstation` | workstation   | —    | —        | —   | ✅          | Llama 3.3 70B Q4, DeepSeek R1 distill, SD 3.5 large  |

### Desktop integration

| Component                       | Lite | Standard | Pro | Workstation |
|---------------------------------|------|----------|-----|-------------|
| Settings → Hardware panel       | ✅   | ✅       | ✅  | ✅          |
| Settings → Model Packs panel    | ✅   | ✅       | ✅  | ✅          |
| `aurum-detect-profile.service`  | ✅   | ✅       | ✅  | ✅          |
| `aurum-gpu-monitor` D-Bus       | ✅ (no-GPU mode) | ✅ | ✅  | ✅          |
| `aurum-ml-jobs-tracker` D-Bus   | ✅   | ✅       | ✅  | ✅          |
| `aurum-spotlight-indexer`       | ✅   | ✅       | ✅  | ✅          |

## How to read the matrix

* **Default for tier (⭐)** — `aurum-detect-profile` writes this value into
  `/etc/aurum/profile.conf`. Launchers (vLLM wrapper, ComfyUI launcher,
  Continue config) pick it up automatically.
* **✅** — the package is installed and runs on this tier. For inference
  tools, this also means it has a GPU to use.
* **⚠️** — the package installs and imports, but runs slow (CPU only) or
  is untested at this tier.
* **❌** — the package is *not* installed by the post-install scripts at
  this tier. The user can still `pip install` it manually.

## Where the values come from

* **Profile tier classification** —
  [`distro/post-install/00-detect-profile.sh`](../../distro/post-install/00-detect-profile.sh)
  contains the `classify_profile()` function.
* **Per-tier defaults** — `emit_profile_keys()` in the same file. To
  change a default, edit that table; every launcher will pick up the new
  value on next boot.
* **Model packs** — `distro/assets/model-packs/*.yaml`. Each pack also
  carries its own `min_profile` gate.
* **pip requirements** —
  `distro/packages/pip-requirements-{base,coding,cv,quant,finetune,workflows,observability}.txt`.

## Filling gaps

If you upgrade one component (e.g. swap `qwen2.5-coder:7b` for
`deepseek-coder-v2:16b`):

1. Edit `00-detect-profile.sh`'s `emit_profile_keys()`.
2. Run `sudo aurum-detect-profile` to rewrite `/etc/aurum/profile.conf`.
3. Run `aurum-configure-continue` to refresh `~/.continue/config.json`.
4. Restart the affected service (Open WebUI / Continue / vLLM).

> TODO (Wave 10 candidate): expose this matrix in the Settings UI as a
> live "what's installed on my profile" table cross-referenced against
> `pip freeze` and `ollama ls`.
