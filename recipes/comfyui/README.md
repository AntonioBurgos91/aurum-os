# ComfyUI workflows

Ready-to-load ComfyUI workflows, tuned for AurumOS's profile defaults.

## Workflows

| File                          | What it does                                          | Profile target  |
|-------------------------------|-------------------------------------------------------|-----------------|
| `txt2img_sdxl_turbo.json`     | Text-to-image with SDXL-Turbo (4 steps, CFG 1.0).     | standard (8 GB) |
| `inpaint_basic.json`          | Mask-driven inpainting via VAEEncodeForInpaint.       | standard        |
| `controlnet_canny.json`       | Canny edge-guided generation with ControlNet.         | standard        |

All three default to `sd_xl_turbo_1.0_fp16.safetensors` because that's the
checkpoint `aurum-cv-download-models comfyui` fetches on the standard profile.
On `pro`/`workstation` you'll want to swap the `CheckpointLoaderSimple` widget
to `sd_xl_base_1.0.safetensors` (more steps, higher CFG, slower but higher
fidelity) — set `AURUM_SD_MODEL=sdxl-fp16` before running the downloader.

## How to load a workflow

The post-install script copies these JSON files into
`/opt/aurum-comfyui/user/default/workflows/`, so they appear in the **Workflows**
sidebar inside ComfyUI on first launch — click the workflow name to load it.

You can also drag any of these `.json` files **directly onto the ComfyUI canvas
in your browser**. ComfyUI's frontend detects workflow JSON via MIME sniff and
loads the graph in place.

From the CLI you can convert + run them headless via:

```bash
cd /opt/aurum-comfyui
python main.py --quick-test-for-ci          # smoke check
# Then POST to /prompt with the workflow JSON; see ComfyUI's API docs.
```

## Prerequisites

```bash
# 1. Install ComfyUI (skipped automatically on lite profile)
sudo bash /usr/share/aurum-os/post-install/11-install-cv-multimodal.sh

# 2. Download a checkpoint matching the workflow's CheckpointLoaderSimple
aurum-cv-download-models comfyui

# 3. (optional) ControlNet weights for controlnet_canny.json
# These are not auto-downloaded — fetch manually from
#   https://huggingface.co/stabilityai/control-lora
# and drop into /opt/aurum-comfyui/models/controlnet/
```

## Profile tuning crib

| Profile     | `AURUM_COMFYUI_FLAGS`                              | `AURUM_SD_MODEL`   |
|-------------|----------------------------------------------------|--------------------|
| lite        | (ComfyUI skipped — install only on `standard+`)    | —                  |
| standard    | `--medvram --use-pytorch-cross-attention`          | `sdxl-turbo-int8`  |
| pro         | `--highvram --use-pytorch-cross-attention`         | `sdxl-fp16`        |
| workstation | `--highvram --use-pytorch-cross-attention --bf16-vae` | `sdxl-fp16`     |

Set `AURUM_PROFILE=...` in `/etc/environment` to override the auto-detected
profile. The launcher (`aurum-launch-comfyui`) reads `AURUM_COMFYUI_FLAGS`
straight out of `/etc/aurum/profile.conf` — no extra config needed.
