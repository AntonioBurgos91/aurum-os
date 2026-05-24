# AurumOS desktop preview

Container that boots a **real Hyprland session** with the AurumOS dock,
menubar, finder and settings running on top, then exposes it via VNC over
HTTP. Lets you experience the macOS-like UX without installing the ISO.

The same image works against a real GPU (full speed, smooth animations
were they enabled) or against the software renderer (no GPU at all, slow
but functional).

## Quick start

Pick the profile that matches your hardware:

```bash
# AMD or Intel GPU (Mesa)
docker compose --profile amd-intel up --build

# NVIDIA GPU (needs nvidia-container-toolkit installed on host)
docker compose --profile nvidia up --build

# No GPU at all — pixman software renderer
docker compose --profile software up --build
```

First build downloads ~3 GB and compiles Hyprland from source (≈5 min).
Subsequent runs are seconds.

Then open: **http://localhost:6080/vnc.html** → click "Connect" (no password).

## What you'll see

- Hyprland compositor running on a 1600×1000 virtual monitor.
- `aurum-menubar` strip at the top with live GPU/VRAM/temp/network/clock
  (simulated NVML when no real GPU is attached).
- `aurum-dock` at the bottom with macOS-style magnification (Gaussian
  falloff to neighbours) + GPU utilization badge.
- `aurum-finder` window with the ML sidebar (~/datasets, ~/models,
  ~/notebooks); Quick Look previews .ipynb / .safetensors / .parquet.
- `aurum-settings` with five sections including CUDA toolkit picker and
  uv-driven Python venv manager.

Press `Cmd+Space` (Super+Space) to invoke `aurum-spotlight` and search
through the synthetic file workspace.

## Tweaking

- **Resolution**: edit `monitor = HEADLESS-1, 1600x1000@60, 0x0, 1` in
  `preview.conf`. Re-build the image (`up --build`).
- **GPU backend override**: `GPU_BACKEND=headless docker compose …` to
  force software rendering even when a GPU is available.
- **Direct VNC** (Tiger VNC, RealVNC, etc.): connect to `localhost:5900`
  bypassing the HTML5 client.

## Limitations

- No animations / fancy shadows even on real GPU because the production
  AurumOS config disables them deliberately (ADR-0006 performance budget
  — keep VRAM free for tensor ops).
- The Aurum.Aqua glass panels are opaque tinted fills, not real KDE-style
  blur, for the same reason.
- This preview is **not** the same as installing the ISO: kernel tuning,
  bcachefs, NVIDIA driver, and the actual DL stack live only on a real
  installation. This is a UI / desktop preview.
