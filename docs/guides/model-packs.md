# Model Packs

AurumOS ships with the *engines* (Ollama, ComfyUI, vLLM, Whisper, Piper)
pre-installed. The *weights* are large, profile-sensitive, and frequently
updated, so they live behind a separate fetch-on-demand layer: **model packs**.

A model pack is a YAML manifest plus the install/remove machinery to bring
all of its weights onto disk and register them with whichever engine consumes
them. Six packs ship in the base image:

| ID          | Title              | Min profile | Approx size | What you get                                                      |
|-------------|--------------------|-------------|-------------|-------------------------------------------------------------------|
| coding      | Coding Pack        | standard    | 12 GB       | qwen2.5-coder 7B (+14B on `pro`), nomic-embed-text                |
| vision      | Vision Pack        | lite        | 3 GB        | YOLO11s, SAM 2 base+, DINOv2-base, OpenCLIP ViT-B/32              |
| chat        | Chat Pack          | lite        | 6 GB        | llama3.2:3b (CPU-fast), qwen2.5:7b (quality, `standard`+)         |
| imagegen    | Image Gen Pack     | standard    | 8 GB        | SDXL-Turbo, ControlNet Canny SDXL, sd-vae-ft-ema (for ComfyUI)    |
| speech      | Speech Pack        | lite        | 2 GB        | faster-whisper small + medium-int8, Piper en_US-amy-medium        |
| workstation | Workstation Pack   | workstation | 55 GB       | llama3.3:70b, qwen2.5:72b, Flux.1-dev, SDXL 1.0 base              |

## CLI quickstart

```bash
# What's available?
aurum-model-pack list

# Inspect a pack before pulling.
aurum-model-pack info coding

# Install — progress lines stream to stdout.
aurum-model-pack install coding

# Free the disk.
aurum-model-pack remove coding
```

Other commands:

| Command                     | Effect                                                           |
|-----------------------------|------------------------------------------------------------------|
| `cache-size`                | Total bytes under `~/.cache/aurum/models/`                       |
| `clear-cache --yes`         | Wipe the entire cache (asks for `--yes` to confirm)              |
| `refresh`                   | Re-scan disk + `ollama list` and rebuild sentinels                |
| `--json list` / `--json info <id>` | Machine-readable output for GUIs and scripts              |

## Profile gating

`aurum-detect-profile` writes one of four tiers to `/etc/aurum/profile.conf`:

- `lite`         — CPU-only or <6 GB VRAM
- `standard`     — RTX 5060 / 4060-class (the 80% target)
- `pro`          — RTX 4070 / 4080
- `workstation`  — RTX 4090 / A6000 / dual-GPU, 24 GB+ VRAM

Each pack declares a `min_profile`; trying to install one that exceeds your
tier is refused unless you pass `--force`. Individual models inside a pack
can also be gated (e.g. `qwen2.5-coder:14b` in the coding pack ships only
for `pro+`); when your tier is lower, those models are silently skipped and
you get an `INFO:` line in the output, but the rest of the pack still
installs.

```bash
$ cat /etc/aurum/profile.conf
AURUM_PROFILE=standard
...
$ aurum-model-pack install workstation
ERROR:workstation:profile gate: pack requires 'workstation', current is 'standard'. Re-run with --force to override.
```

## Cache layout

Everything lives under `~/.cache/aurum/models/` (overridable with
`$AURUM_MODEL_CACHE`). Layout:

```
~/.cache/aurum/models/
├── .installed/                  # one sentinel file per installed pack
│   ├── coding                   #   JSON: {pack_id, installed_at, models, profile}
│   └── vision
├── hf/<repo-id>/                # arbitrary HF downloads
├── gguf/<name>.gguf             # GGUF files for llama.cpp / LM Studio
├── ollama/                      # metadata only — Ollama owns its own blob store
└── comfyui-mirror/              # symlinks back to /opt/aurum-comfyui/models/
    ├── checkpoints/
    ├── controlnet/
    └── vae/
```

The cache is per-user; system-wide weights (ComfyUI base checkpoints, Flux.1)
land under `/opt/aurum-comfyui/models/` and are merely mirrored here for
ownership tracking.

## Progress protocol (for GUI integrations)

The CLI emits exactly one of four line shapes on stdout, line-buffered.
Anything else (human-readable text from sub-tools, etc.) is informational
and may be ignored.

```
PROGRESS:<pack-id>:<percent>      # 0–100, monotonically non-decreasing
DONE:<pack-id>                    # pack fully installed
ERROR:<pack-id>:<message>         # install failed; <message> has no newlines
INFO:<message>                    # general informational text
```

This is what the AurumOS Spotlight "Models" panel parses to drive its
progress bars. Tools wrapping the CLI should consume stdout line-by-line
(QProcess `readyReadStandardOutput`, Python `subprocess.Popen(text=True)`
with iteration, etc.) and treat exit code 0 plus a `DONE:` line as success.

## Manifest format

```yaml
id: coding
title: Coding Pack
description: ...
size_bytes: 13594504208
min_profile: standard
docs_url: https://docs.aurumos.dev/model-packs/coding
tags: [llm, code]

models:
  - source: ollama
    name: qwen2.5-coder:7b
    size_bytes: 4683304960

  - source: ollama
    name: qwen2.5-coder:14b
    size_bytes: 8988366000
    min_profile: pro          # gated to a higher tier than the pack itself

  - source: hf
    repo: bartowski/Qwen2.5-Coder-7B-Instruct-GGUF
    files: ["Qwen2.5-Coder-7B-Instruct-Q4_K_M.gguf"]
    dest: ~/.cache/aurum/models/gguf/
```

Supported `source` values today: `ollama` (pulled with `ollama pull`) and
`hf` (fetched via `huggingface_hub.hf_hub_download`). Manifests are loaded
in alphabetical order from the first existing directory in:

1. `$AURUM_MODEL_PACKS_DIR` (env override, used by tests)
2. `/etc/aurum/model-packs/` (the installed location)
3. `<repo>/distro/assets/model-packs/` (dev checkout fallback)

## Adding a custom pack

Drop a new `.yaml` file into `/etc/aurum/model-packs/`. The next
`aurum-model-pack list` picks it up — no daemon restart, no rebuild.

## Troubleshooting

- **"profile gate: pack requires …"** — your hardware tier is below the
  pack's `min_profile`. Re-run with `--force` if you know what you're doing
  (e.g. you have plenty of RAM and accept slow CPU inference).
- **"ollama pull … exited with code 1"** — usually `ollama.service` isn't
  running. Start it with `systemctl --user start ollama` (or `sudo systemctl
  start ollama` on the system unit).
- **"huggingface_hub not installed"** — the helpers fell back to the system
  python instead of the Aurum DL venv. Activate the venv
  (`source /opt/aurum-dl-venv/bin/activate`) or set `AURUM_PYTHON=` to your
  preferred interpreter.
- **GUI shows no progress** — the wrapping process likely captured stdout
  with block buffering. The shipped shim already invokes Python with `-u`;
  if you're calling the helpers script directly, do the same.
