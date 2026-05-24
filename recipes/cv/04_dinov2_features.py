#!/usr/bin/env python3
"""DINOv2 feature extraction — AurumOS reference recipe.

DINOv2 produces strong self-supervised image embeddings useful for retrieval,
clustering, and downstream linear probes. This recipe loads `facebook/dinov2-base`
via HuggingFace transformers (no upstream-repo dependency) and computes a
single pooled embedding for a sample image.

Run:
    aurum-cv-download-models dinov2     # one-off, downloads weights
    /opt/aurum-dl-venv/bin/python recipes/cv/04_dinov2_features.py [image.jpg]
"""
from __future__ import annotations

import os
import sys
from pathlib import Path

import torch
from PIL import Image
from transformers import AutoImageProcessor, AutoModel

REPO = os.environ.get("AURUM_DINOV2_REPO", "facebook/dinov2-base")
SAMPLE_URL = "https://ultralytics.com/images/bus.jpg"


def load_image(src: str) -> Image.Image:
    if src.startswith("http"):
        import urllib.request
        tmp = Path("/tmp/aurum-dinov2-input.jpg")
        urllib.request.urlretrieve(src, tmp)
        src = str(tmp)
    return Image.open(src).convert("RGB")


def main() -> int:
    src = sys.argv[1] if len(sys.argv) > 1 else SAMPLE_URL
    out_dir = Path(os.environ.get("AURUM_CV_OUT", "~/cv-out/dinov2")).expanduser()
    out_dir.mkdir(parents=True, exist_ok=True)

    print(f"[dinov2] loading {REPO}")
    processor = AutoImageProcessor.from_pretrained(REPO)
    model = AutoModel.from_pretrained(REPO)
    model.eval()

    device = "cuda" if torch.cuda.is_available() else "cpu"
    model = model.to(device)
    print(f"[dinov2] running on {device}")

    img = load_image(src)
    inputs = processor(images=img, return_tensors="pt").to(device)

    with torch.inference_mode():
        out = model(**inputs)

    # DINOv2 returns a (B, 1+N_patch, D) tensor; the first token is the CLS
    # token that downstream consumers usually want as the global descriptor.
    cls = out.last_hidden_state[:, 0]
    cls_np = cls.detach().cpu().numpy()

    print(f"[dinov2] embedding shape: {cls_np.shape} dtype={cls_np.dtype}")
    print(f"[dinov2] first 8 dims: {cls_np[0, :8].round(4).tolist()}")
    print(f"[dinov2] L2 norm: {float((cls_np ** 2).sum() ** 0.5):.4f}")

    # Save the embedding alongside the recipe so it's easy to pipe into a
    # nearest-neighbour notebook downstream.
    out_path = out_dir / "embedding.pt"
    torch.save({"image": src, "embedding": cls.detach().cpu()}, out_path)
    print(f"[dinov2] embedding saved: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
