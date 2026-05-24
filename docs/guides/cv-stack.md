# Computer Vision & Multimodal stack

AurumOS ships a curated computer-vision and multimodal stack: **YOLOv11**
detection, **SAM2** segmentation, **DINOv2** embeddings, **OpenCLIP**
zero-shot classification, **LLaVA / InternVL2 / Qwen2-VL** vision-language
notebooks, and **ComfyUI** for diffusion-based image generation.

Everything below is profile-adaptive — `aurum-cv-download-models` and the
ComfyUI launcher both read `/etc/aurum/profile.conf` and pick model sizes
that match your hardware tier.

## Quick start

```bash
# 1. (One-time) install the stack. The ISO already runs this; on an existing
#    AurumOS box it's safe to re-run.
sudo bash /usr/share/aurum-os/post-install/11-install-cv-multimodal.sh

# 2. Fetch model weights. Pick what you need — or grab everything:
aurum-cv-download-models yolo           # ~25 MB on standard
aurum-cv-download-models sam            # ~150 MB
aurum-cv-download-models clip           # ~600 MB
aurum-cv-download-models dinov2         # ~330 MB
aurum-cv-download-models comfyui        # 6 GB+ (SDXL-Turbo)
aurum-cv-download-models llava          # 5-30 GB depending on profile
aurum-cv-download-models all            # all of the above

# 3. Run a recipe
/opt/aurum-dl-venv/bin/python ~/aurum-recipes/cv/01_yolov11_detect.py
```

> **Note:** model weights are deliberately NOT downloaded during install —
> they add 5-30 GB and would balloon ISO size + first-boot bandwidth. The
> `aurum-cv-download-models` CLI is the opt-in entry point.

## Profile recommendations

| Profile     | Hardware              | YOLO       | SAM2       | LLaVA           | SD checkpoint     |
|-------------|-----------------------|------------|------------|-----------------|-------------------|
| lite        | CPU-only / <6 GB VRAM | `yolov11n` | `sam2-tiny`| `llava-phi-int4`| _(ComfyUI off)_   |
| standard    | RTX 5060 / 4060 (8 GB)| `yolov11s` | `sam2-base`| `llava-7b-int4` | `sdxl-turbo-int8` |
| pro         | RTX 4070/4080 (12–16) | `yolov11m` | `sam2-large`| `llava-13b-int4`| `sdxl-fp16`      |
| workstation | RTX 4090 / A6000      | `yolov11x` | `sam2-large`| `llava-34b-int4`| `sdxl-fp16`      |

Override the auto-detected profile by setting `AURUM_PROFILE=...` in
`/etc/environment` (then re-source `profile.conf` or reboot).

## Components

### YOLOv11 — detection / tracking / segmentation / pose

Wave 7 installed `ultralytics`; Wave 8 added the profile-aware launcher and
two reference recipes:

```bash
# Inference
/opt/aurum-dl-venv/bin/python ~/aurum-recipes/cv/01_yolov11_detect.py path/to/img.jpg

# Fine-tune on COCO128 (downloads automatically)
/opt/aurum-dl-venv/bin/python ~/aurum-recipes/cv/02_yolov11_train.py
```

The recipes pick `$AURUM_YOLO_MODEL` from your profile by default; override
via `AURUM_YOLO_MODEL=yolov11x`.

### SAM2 — Segment Anything 2

```bash
aurum-cv-download-models sam
/opt/aurum-dl-venv/bin/python ~/aurum-recipes/cv/03_sam2_segment.py path/to/img.jpg
```

Outputs an overlay PNG with per-mask colour fills under `~/cv-out/sam2/`.

**Note on the pip name:** SAM2's pypi distribution flip-flopped between
`sam-2` and `segment-anything-2`. The installer tries both names and falls
back to a git install (`git+https://github.com/facebookresearch/sam2.git`)
if neither resolves. Whichever wins, the import (`import sam2`) is the same.

### DINOv2 — self-supervised image embeddings

```bash
aurum-cv-download-models dinov2
/opt/aurum-dl-venv/bin/python ~/aurum-recipes/cv/04_dinov2_features.py path/to/img.jpg
```

Saves a (1, 768) CLS embedding to `~/cv-out/dinov2/embedding.pt`. Useful as
a feature backbone for retrieval, k-NN classification, and linear probes.

> **Pip detail:** Facebook does not publish DINOv2 to pypi. The installer
> falls back to `pip install git+https://github.com/facebookresearch/dinov2.git`
> only if needed; the default recipe goes through HuggingFace's
> `transformers.AutoModel("facebook/dinov2-base")` which doesn't require the
> upstream repo at all.

### OpenCLIP — zero-shot classification

```bash
aurum-cv-download-models clip
AURUM_CLIP_LABELS="dog,cat,bus,car,person" \
    /opt/aurum-dl-venv/bin/python ~/aurum-recipes/cv/05_clip_zero_shot.py path/to/img.jpg
```

Default model is `ViT-B-32 / laion2b_s34b_b79k` (~600 MB) — fits on every
profile and is enough for prototyping. For production retrieval, swap to
`ViT-L-14` (~1.7 GB) or `ViT-H-14` (~3.9 GB) via `AURUM_CLIP_MODEL=...`.

### LLaVA / InternVL2 / Qwen2-VL — multimodal chat

JupyterLab notebooks under `recipes/multimodal/`:

- `01_llava_image_qa.ipynb` — single-turn image question answering
- `02_internvl2_chat.ipynb` — multi-turn chat with strong OCR
- `03_qwen2_vl.ipynb` — dynamic-resolution + multilingual + video frames

Each notebook reads `AURUM_PROFILE` and `AURUM_LLAVA_MODEL` from the
environment to pick the appropriate model size. Open from JupyterLab
(`Cmd+Space` → "jupyter" → Enter) or run headless:

```bash
/opt/aurum-dl-venv/bin/jupyter nbconvert --execute \
    ~/aurum-recipes/multimodal/01_llava_image_qa.ipynb \
    --to notebook --output-dir ~/cv-out/
```

LLaVA-1.5 / Qwen2-VL repos are public. Some LLaVA-NeXT variants are gated —
export `HF_TOKEN=<your_token>` first if you hit a 401.

### ComfyUI — image generation

ComfyUI is the node-based diffusion frontend. It runs as a local web server
on `127.0.0.1:8188` and you interact via a browser canvas.

```bash
# Launch (opens the browser automatically)
aurum-launch-comfyui
```

The launcher reads `AURUM_COMFYUI_FLAGS` from your profile:

- standard → `--medvram --use-pytorch-cross-attention` (8 GB-safe)
- pro → `--highvram --use-pytorch-cross-attention`
- workstation → `--highvram --use-pytorch-cross-attention --bf16-vae`
- **lite → ComfyUI is not installed.** Diffusion on CPU is so slow it's
  rarely worth the disk space; if you really need it on a no-GPU box, set
  `AURUM_PROFILE=standard` before running the installer and pass
  `AURUM_COMFYUI_FLAGS="--cpu --use-pytorch-cross-attention"` to the launcher.

Three pre-made workflows ship under
`/opt/aurum-comfyui/user/default/workflows/`:

- `txt2img_sdxl_turbo.json` — 4-step txt2img tuned for 8 GB VRAM
- `inpaint_basic.json` — mask-driven inpainting
- `controlnet_canny.json` — edge-guided generation (needs ControlNet
  weights from `https://huggingface.co/stabilityai/control-lora` in
  `/opt/aurum-comfyui/models/controlnet/`)

To load: click the workflow name in ComfyUI's **Workflows** sidebar, OR
drag the JSON file directly onto the canvas.

## Where things live

| What                                | Path                                                |
|-------------------------------------|-----------------------------------------------------|
| Python venv                         | `/opt/aurum-dl-venv/`                               |
| ComfyUI checkout                    | `/opt/aurum-comfyui/`                               |
| ComfyUI checkpoints                 | `/opt/aurum-comfyui/models/checkpoints/`            |
| ComfyUI workflows (pre-loaded)      | `/opt/aurum-comfyui/user/default/workflows/`        |
| YOLO / OpenCLIP model cache         | `~/.cache/torch/hub/`                               |
| HuggingFace model cache (LLaVA etc) | `~/.cache/huggingface/hub/`                         |
| Recipe outputs                      | `~/cv-out/{yolo-detect, sam2, dinov2, ...}/`        |
| Launcher logs                       | `~/.local/state/aurum-comfyui/server.log`           |

## Troubleshooting

- **"No CUDA devices detected" warning** — Expected if the host has no GPU
  (Docker preview, CPU-only laptop). YOLOv11n + SAM2-tiny + OpenCLIP all
  run in pure-CPU mode; LLaVA / ComfyUI will be unusably slow.

- **`sam2` import fails** — The installer tries `sam-2` → `segment-anything-2`
  → git fallback. If all three fail (no internet during install), re-run:
  ```bash
  /opt/aurum-dl-venv/bin/pip install git+https://github.com/facebookresearch/sam2.git
  ```

- **ComfyUI launcher hangs on "waiting for port 8188"** — Check
  `~/.local/state/aurum-comfyui/server.log`. Most common culprits: missing
  CUDA libraries, no checkpoint in `models/checkpoints/`, or a port conflict
  (another ComfyUI / Stable Diffusion WebUI already on 8188 — set
  `LISTEN_PORT=8189` before launching).

- **LLaVA notebook: "401 Unauthorized"** — The repo is gated. Visit
  https://huggingface.co/settings/tokens, create a token, then:
  ```bash
  export HF_TOKEN=hf_xxx
  aurum-cv-download-models llava
  ```

- **Out-of-memory during ComfyUI sampling** — Drop the output resolution
  in `EmptyLatentImage` to 512×512, switch the workflow to SDXL-Turbo
  (4 steps, CFG 1.0), and add `--lowvram` to `AURUM_COMFYUI_FLAGS`.
